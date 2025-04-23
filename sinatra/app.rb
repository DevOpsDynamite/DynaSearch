# frozen_string_literal: true

# --- Core Dependencies ---
require 'sinatra'
require 'sinatra/flash'
require 'sqlite3'
require 'json'
require 'sinatra/contrib' # Provides namespace, among other things
require 'logger'
require 'prometheus/client'
require 'pg'


# --- Utility Dependencies ---
require 'dotenv/load'     # Loads environment variables from .env file
require 'httparty'        # For making HTTP requests (weather API)
require 'bcrypt'          # For secure password hashing
require 'securerandom'    # For generating secure random numbers (session secret)
# --- ActiveSupport Dependencies ---
require 'active_support/core_ext/string/filters' # For String#squish
require 'active_support/core_ext/object/blank' # For present? and blank?

# --- Application Configuration ---
set :bind, '0.0.0.0'
set :port, 4568
enable :sessions
default_secret = "default_secret_for_dev_#{SecureRandom.hex(32)}"
set :session_secret, ENV.fetch('SESSION_SECRET', default_secret) # Added default for safety
set :root, File.dirname(__FILE__)
set :views, File.join(settings.root, 'views')
PROMETHEUS = Prometheus::Client.registry


# Register Sinatra extensions
register Sinatra::Flash

################################################################################
# Database Configuration & Setup / Logging Configuration
################################################################################

DATABASE_URL = if ENV['RACK_ENV'] == 'test'
  # Keep using SQLite for tests for now, or set up a test Postgres DB
  "sqlite://#{File.join(__dir__, 'test', 'test_whoknows.db')}"
elsif ENV['DATABASE_URL']
  ENV['DATABASE_URL'] 
# else
#   # Fallback for local dev *if* you still want SQLite locally sometimes
#   # Or raise an error if DATABASE_URL is required outside of tests
#   "sqlite://#{File.join(__dir__, 'whoknows.db')}"
#   # Or: raise "DATABASE_URL environment variable is not set!"
end

configure do
  # --- Database Setup ---
  if ENV['RACK_ENV'] != 'test' && !File.exist?(DB_PATH)
    warn "WARN: Database not found at #{DB_PATH}. Application might not function correctly."
  end

  begin
    # Use the DATABASE_URL determined earlier
    db_connection = PG::Connection.new(DATABASE_URL)
 
    # Optional: Set notice processor to log PostgreSQL notices
    db_connection.set_notice_processor { |message| settings.logger.warn "PostgreSQL Notice: #{message}" }
 
    # Set the connection object for the app
    set :db, db_connection
  rescue PG::Error => e # Catch PostgreSQL specific errors
    settings.logger.fatal "FATAL: Failed to connect to PostgreSQL database: #{e.message}"
    # Optional: Log connection string details without password for debugging
    settings.logger.fatal "Connection attempt made using DATABASE_URL (password redacted)."
    exit(1)
  end
 
  # Add a disconnect hook for clean shutdown
  at_exit do
    settings.db&.close if settings.db.is_a?(PG::Connection) && !settings.db.finished?
  end

  # --- Weather Cache Setup ---
  set :forecast_cache, nil
  # Use Time.now.utc for consistent time zone handling
  set :forecast_cache_expiration, Time.now.utc

  # --- Logging Configuration ---
  log_dir = File.join(settings.root, 'log')
  Dir.mkdir(log_dir) unless File.exist?(log_dir)

  log_file_path = File.join(log_dir, 'development.log')
  # Use Ruby's standard Logger class
  # 'daily' rotates logs daily, you can also use 'weekly' or just the path
  file_logger = Logger.new(log_file_path, 'daily')
  file_logger.level = Logger::INFO # Set the logging level (DEBUG, INFO, WARN, ERROR, FATAL)

  # Tell Sinatra to use this logger instance. This often handles request logging too.
  set :logger, file_logger
end

################################################################################
# Load Helpers & Routes
################################################################################

require_relative 'helpers/application_helpers'
require_relative 'routes/pages'
require_relative 'routes/auth'
require_relative 'routes/api'

################################################################################
# Global Error Handling Routes
################################################################################

not_found do
  status 404
  if request.accept?('application/json')
    content_type :json
    { status: 'error', message: 'Resource not found.' }.to_json
  else
    erb :not_found
  end
end

error do
  status 500
  error_obj = env['sinatra.error']
  error_message = error_obj&.message || 'An unexpected error occurred.'
  # Use the configured logger instance to log errors
  settings.logger.error "Unhandled Application Error: #{error_obj&.class} - #{error_message}"
  settings.logger.error error_obj&.backtrace&.join("\n") # Log backtrace too

  if request.accept?('application/json')
    content_type :json
    { status: 'error', message: 'Internal server error.' }.to_json
  else
    @error_message = error_message
    begin
      erb :server_error
    rescue StandardError
      '<h1>Internal Server Error</h1><p>Sorry, something went wrong.</p>'
    end
  end
end

get '/health' do
  content_type :json
  { status: 'ok' }.to_json
end

################################################################################
# Metrics 
################################################################################

# Counter for total HTTP responses served
APP_HTTP_RESPONSES_TOTAL = PROMETHEUS.counter(
  :app_http_responses_total,
  docstring: 'Total number of HTTP responses sent by the application.'
)

# Histogram for request duration in seconds (or milliseconds)
APP_REQUEST_DURATION_SECONDS = PROMETHEUS.histogram(
  :app_request_duration_seconds,
  docstring: 'Application request duration distribution in seconds.',
  # Buckets chosen to capture typical web request times (adjust as needed)
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
)

require 'prometheus/middleware/exporter'

# use Prometheus::Middleware::Exporter



get '/metrics' do
@skip_metrics = true
  begin
    # Set the Content-Type header manually with semicolons
    headers['Content-Type'] = 'text/plain; version=0.0.4; charset=utf-8'
    # Format the registry using the correct marshaller
    Prometheus::Client::Formats::Text.marshal(PROMETHEUS)
  rescue => e
    logger.error "Error generating /metrics: #{e.message} Backtrace: #{e.backtrace.join("\n")}"
    status 500
    "Error generating metrics"
  end
end


before do
  # Store request start time
  @request_start_time = Time.now

  # --- Optional: Update Gauges ---
  # Example: Update CPU Gauge if you implement it
  # begin
  #   # Replace with your actual CPU measurement logic
  #   cpu_percent = get_current_cpu_usage_somehow()
  #   APP_CPU_LOAD_PERCENT.set(cpu_percent)
  # rescue => e
  #   logger.warn "Failed to get CPU usage: #{e.message}"
  # end

  # Example: Update Active Sessions Gauge (requires session logic)
  # active_count = get_active_session_count_somehow()
  # APP_ACTIVE_SESSIONS.set(active_count)
end

after do
  return if @skip_metrics
  # --- Increment Counters & Observe Histograms ---
  APP_HTTP_RESPONSES_TOTAL.increment

  if @request_start_time
    # Calculate duration in seconds
    duration = Time.now - @request_start_time
    APP_REQUEST_DURATION_SECONDS.observe(duration)
  end
end

