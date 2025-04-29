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
require 'prometheus/client/mmap'
require 'prometheus/client/formats/text'
require 'prometheus/client/support/ruby_vm'
# --- Prometheus Dependencies --- ^^^ ---


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

# Initialize Mmap storage for process metrics (CPU, Memory, FD etc.)
# Ensure the directory (/tmp/prometheus-mmap-metrics by default) is writable
# by the user running the app ('appuser' in your Dockerfile).
# The docker-entrypoint.sh might need adjustment if /tmp isn't writable.
begin
  Prometheus::Client::Mmap.auto_activate_storage!
rescue Errno::EACCES => e
  # Log a warning if the mmap directory isn't writable, metrics won't be collected
  # Consider creating/chowning the default dir in your Dockerfile or entrypoint
  warn "WARN: Prometheus mmap storage activation failed (permissions?): #{e.message}. Process metrics (CPU/Mem) might not be collected."
end


# Register default Ruby VM collectors (GC, Threads, etc.)
Prometheus::Client::Support::RubyVm.register(PROMETHEUS)
# --- Prometheus Setup --- ^^^ ---


# Register Sinatra extensions
register Sinatra::Flash

################################################################################
# Database Configuration & Setup / Logging Configuration
################################################################################

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

# --- Updated Metrics Endpoint --- VVV ---
get '/metrics' do
  @skip_metrics = true # Prevent before/after hooks from running for this request
  begin
    headers['Content-Type'] = 'text/plain; version=0.0.4; charset=utf-8'

    # Get metrics from the default registry (includes request counters, histograms, Ruby VM stats)
    default_metrics = Prometheus::Client::Formats::Text.marshal(PROMETHEUS)

    # Get metrics from the mmap storage (includes process_cpu_seconds_total, process_resident_memory_bytes, etc.)
    mmap_metrics_dir = Prometheus::Client::Mmap.default_metrics_dir
    mmap_metrics = if Dir.exist?(mmap_metrics_dir)
                      begin
                        Prometheus::Client::Formats::Text.marshal_mmap_storage(mmap_metrics_dir)
                      rescue Errno::EACCES => e
                        logger.warn "Prometheus mmap directory not readable: #{mmap_metrics_dir}. #{e.message}"
                        "" # Return empty string if dir not readable
                      end
                    else
                      # This might happen on first startup before any workers write metrics
                      # Or if auto_activate_storage failed due to permissions earlier.
                      logger.debug "Prometheus mmap directory not found or accessible: #{mmap_metrics_dir}"
                      "" # Return empty string if dir doesn't exist
                    end

    # Combine the metrics text output
    default_metrics + mmap_metrics

  rescue => e
    logger.error "Error generating /metrics: #{e.message} Backtrace: #{e.backtrace.join("\n")}"
    status 500
    "Error generating metrics"
  end
end
# --- Updated Metrics Endpoint --- ^^^ ---


# --- Before/After hooks for Request Metrics --- VVV ---
before do
  # Skip metrics endpoint itself and potentially other paths if needed
  pass if request.path_info == '/metrics'

  # Store request start time
  @request_start_time = Time.now

  # --- Optional: Update Gauges ---
  # Example: You could add a gauge for active requests
  # APP_ACTIVE_REQUESTS.increment if defined?(APP_ACTIVE_REQUESTS)
end

after do
  # Use the instance variable set in the /metrics route to skip
  pass if @skip_metrics

  # --- Increment Counters & Observe Histograms ---
  # Labels can be added here, e.g., based on response.status
  # status_label = { code: response.status.to_s } # Example label
  APP_HTTP_RESPONSES_TOTAL.increment #(labels: status_label)

  if @request_start_time
    # Calculate duration in seconds
    duration = Time.now - @request_start_time
    APP_REQUEST_DURATION_SECONDS.observe(duration) #(labels: status_label)
  end

  # Example: Decrement active requests gauge
  # APP_ACTIVE_REQUESTS.decrement if defined?(APP_ACTIVE_REQUESTS)
end
# --- Before/After hooks for Request Metrics --- ^^^ ---