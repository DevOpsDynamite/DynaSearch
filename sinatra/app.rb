# frozen_string_literal: true

# --- Core Dependencies ---
require 'sinatra'
require 'sinatra/flash'
require 'sqlite3'
require 'json'
require 'sinatra/contrib' # Provides namespace, among other things
require 'logger'
# --- Prometheus Dependencies --- VVV ---
require 'prometheus/client'
require 'prometheus/client/formats/text' 
# --- Prometheus Dependencies --- ^^^ ---
# <<< REMOVED: require 'prometheus/client/mmap'
# <<< REMOVED: require 'prometheus/client/support/ruby_vm'


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

# --- Prometheus Setup --- VVV ---
PROMETHEUS = Prometheus::Client.registry
# <<< REMOVED: Prometheus::Client::Mmap.auto_activate_storage!
# <<< REMOVED: Prometheus::Client::Support::RubyVm.register(PROMETHEUS)
# --- Prometheus Setup --- ^^^ ---


# Register Sinatra extensions
register Sinatra::Flash

################################################################################
# Database Configuration & Setup / Logging Configuration
################################################################################
# ... (Keep existing DB, Cache, Logging config) ...
DB_PATH = if ENV['RACK_ENV'] == 'test'
            File.join(__dir__, 'test', 'test_whoknows.db')
          elsif ENV['DATABASE_PATH']
            ENV['DATABASE_PATH']
          else
            File.join(__dir__, 'whoknows.db')
          end

configure do
  # --- Database Setup ---
  if ENV['RACK_ENV'] != 'test' && !File.exist?(DB_PATH)
    warn "WARN: Database not found at #{DB_PATH}. Application might not function correctly."
  end

  begin
    db_connection = SQLite3::Database.new(DB_PATH)
    db_connection.results_as_hash = true
    set :db, db_connection
  rescue SQLite3::Exception => e
    warn "FATAL: Failed to connect to database at #{DB_PATH}: #{e.message}"
    exit(1)
  end

  # --- Weather Cache Setup ---
  set :forecast_cache, nil
  set :forecast_cache_expiration, Time.now.utc

  # --- Logging Configuration ---
  log_dir = File.join(settings.root, 'log')
  Dir.mkdir(log_dir) unless File.exist?(log_dir)
  log_file_path = File.join(log_dir, 'development.log')
  file_logger = Logger.new(log_file_path, 'daily')
  file_logger.level = Logger::INFO
  set :logger, file_logger
end
################################################################################
# Load Helpers & Routes
################################################################################
# ... (Keep existing requires) ...
require_relative 'helpers/application_helpers'
require_relative 'routes/pages'
require_relative 'routes/auth'
require_relative 'routes/api'

################################################################################
# Global Error Handling Routes
################################################################################
# ... (Keep existing error handlers) ...
not_found do
  status 404
  if request.accept?('application/json')
    erb :not_found
  else
    content_type :json
    { status: 'error', message: 'Resource not found.' }.to_json  end
end

error do
  status 500
  error_obj = env['sinatra.error']
  error_message = error_obj&.message || 'An unexpected error occurred.'
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
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
)

WEATHER_FETCH_ATTEMPTS_TOTAL = PROMETHEUS.counter(
  :weather_fetch_attempts_total,
  docstring: 'Total number of weather forecast external API fetch attempts.'
)

WEATHER_FETCH_SUCCESS_TOTAL = PROMETHEUS.counter(
  :weather_fetch_success_total,
  docstring: 'Total number of successful weather forecast external API fetches.'
)
WEATHER_FETCH_FAILURE_TOTAL = PROMETHEUS.counter(
  :weather_fetch_failure_total,
  docstring: 'Total number of failed weather forecast external API fetches.',
  labels: [:reason] # e.g., reason: 'config_error', 'api_error', 'connection_error'
)
# --- Simplified Metrics Endpoint --- VVV ---
get '/metrics' do
  @skip_metrics = true # Prevent before/after hooks from running for this request
  begin
    headers['Content-Type'] = 'text/plain; version=0.0.4; charset=utf-8'

    # Format metrics ONLY from the default registry
    Prometheus::Client::Formats::Text.marshal(PROMETHEUS)

  rescue => e
    logger.error "Error generating /metrics: #{e.message} Backtrace: #{e.backtrace.join("\n")}"
    status 500
    "Error generating metrics"
  end
end
# --- Simplified Metrics Endpoint --- ^^^ ---


# --- Before/After hooks for Request Metrics 
before do
  pass if request.path_info == '/metrics'
  @request_start_time = Time.now
end

after do
  pass if @skip_metrics

  APP_HTTP_RESPONSES_TOTAL.increment

  if @request_start_time
    duration = Time.now - @request_start_time
    # Use the standard single-argument observe method
    APP_REQUEST_DURATION_SECONDS.observe(duration) 
  end
end
# --- Before/After hooks for Request Metrics --- ^^^ ---