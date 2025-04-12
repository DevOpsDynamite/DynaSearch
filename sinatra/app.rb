# frozen_string_literal: true

# --- Core Dependencies ---
require 'sinatra'
require 'sinatra/flash'
require 'sqlite3'
require 'json'
require 'sinatra/contrib' # Provides namespace, among other things

# --- Utility Dependencies ---
require 'dotenv/load'     # Loads environment variables from .env file
require 'httparty'        # For making HTTP requests (weather API)
require 'bcrypt'          # For secure password hashing
require 'securerandom'    # For generating secure random numbers (session secret)
require 'active_support/core_ext/string/filters' # For String#squish

# --- Application Configuration ---
# Use Sinatra::Base for modular applications is often better, but sticking to classic style here.
# class MyApp < Sinatra::Base would be the alternative.

set :bind, '0.0.0.0' # Bind to all interfaces, crucial for Docker/containers
set :port, 4568      # Set the application port
enable :sessions    # Enable session handling
# Set a secure session secret. Use ENV variable or generate a random one.
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(32) }
# Set the root directory explicitly for views and public folders if needed
set :root, File.dirname(__FILE__)
# Set views directory (assuming it's adjacent to app.rb)
set :views, File.join(settings.root, 'views')


# Register Sinatra extensions
register Sinatra::Flash # For displaying flash messages (e.g., success/error notices)

################################################################################
# Database Configuration & Setup
################################################################################

# Determine the database path based on environment variables.
# Preserves the original logic for path determination.
DB_PATH = if ENV['RACK_ENV'] == 'test'
            File.join(__dir__, 'test', 'test_whoknows.db')
          elsif ENV['DATABASE_PATH']
            ENV['DATABASE_PATH']
          else
            File.join(__dir__, 'whoknows.db') # Original default
          end

# Configure block runs once when the application starts.
configure do
  # Check if the database file exists, except in test environment.
  # Preserves the original check.
  if ENV['RACK_ENV'] != 'test' && !File.exist?(DB_PATH)
    warn "WARN: Database not found at #{DB_PATH}. Application might not function correctly."
    # exit(1) # Consider uncommenting if DB is absolutely required
  end

  # Initialize the database connection.
  begin
    db_connection = SQLite3::Database.new(DB_PATH)
    db_connection.results_as_hash = true # Return results as hashes
    set :db, db_connection
  rescue SQLite3::Exception => e
    $stderr.puts "FATAL: Failed to connect to database at #{DB_PATH}: #{e.message}"
    exit(1) # Exit if database connection fails critically
  end

  # Initialize weather forecast cache variables
  set :forecast_cache, nil
  set :forecast_cache_expiration, Time.now
end

################################################################################
# Load Helpers & Routes
# Order matters: Helpers need to be available when routes are defined.
################################################################################

require_relative 'helpers/application_helpers'
require_relative 'routes/pages'
require_relative 'routes/auth'
require_relative 'routes/api'

################################################################################
# Global Error Handling Routes
# These should be defined after loading routes.
################################################################################

# Handle 404 Not Found errors
not_found do
  status 404
  # Check if the request expects JSON
  if request.accept?('application/json')
    content_type :json
    { status: 'error', message: 'Resource not found.' }.to_json
  else
    erb :not_found # Render the standard HTML 404 page
  end
end

# Generic error handler for 500 Internal Server Error
error do
  status 500
  error_obj = env['sinatra.error']
  error_message = error_obj&.message || 'An unexpected error occurred.'
  logger.error "Unhandled Application Error: #{error_obj&.class} - #{error_message}"
  logger.error error_obj&.backtrace&.join("\n") # Log backtrace if available

  # Check if the request expects JSON
  if request.accept?('application/json')
    content_type :json
    { status: 'error', message: 'Internal server error.' }.to_json
  else
    # Render a generic HTML error page
    @error_message = error_message # Pass message to the view if needed
    erb :server_error rescue "<h1>Internal Server Error</h1><p>Sorry, something went wrong.</p>" # Fallback HTML
  end
end

# Optional: Add a simple health check endpoint
get '/health' do
  content_type :json
  { status: 'ok' }.to_json
end
