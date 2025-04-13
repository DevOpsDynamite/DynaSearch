# frozen_string_literal: true

# --- Core Dependencies ---
require 'sinatra'
require 'sinatra/flash'
require 'sqlite3'
require 'json'
require 'sinatra/contrib' # Provides namespace, among other things
require 'logger' # Make sure this is here


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
set :session_secret, ENV.fetch('SESSION_SECRET', "default_secret_for_dev_#{SecureRandom.hex(32)}") # Added default for safety
set :root, File.dirname(__FILE__)
set :views, File.join(settings.root, 'views')

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
    $stderr.puts "FATAL: Failed to connect to database at #{DB_PATH}: #{e.message}"
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
  file_logger = Logger.new(log_file_path, 'daily') # 'daily' rotates logs daily, you can also use 'weekly' or just the path
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
    erb :server_error rescue "<h1>Internal Server Error</h1><p>Sorry, something went wrong.</p>"
  end
end

get '/health' do
  content_type :json
  { status: 'ok' }.to_json
end