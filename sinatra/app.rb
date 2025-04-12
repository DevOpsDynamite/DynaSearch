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
set :bind, '0.0.0.0' # Bind to all interfaces, crucial for Docker/containers
set :port, 4568      # Set the application port
enable :sessions    # Enable session handling
# Set a secure session secret. Use ENV variable or generate a random one.
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(32) }

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
    # Original code exited here, but allowing it to continue might be preferable
    # depending on whether other parts of the app can run without the DB.
    # Consider uncommenting exit(1) if DB is absolutely required from the start.
    # exit(1)
  end

  # Initialize the database connection.
  # Use begin/rescue to handle potential errors during DB initialization.
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
# Helpers
################################################################################

helpers do
  # Provides easy access to the database connection within routes and views.
  def db
    settings.db
  end

  # Retrieves the currently logged-in user based on session data.
  # Memoized (@current_user ||= ...) for performance within a single request.
  def current_user
    return @current_user if defined?(@current_user) # Return if already memoized

    user_id = session[:user_id]
    return @current_user = nil unless user_id # No user ID in session

    begin
      user = db.get_first_row('SELECT * FROM users WHERE id = ?', user_id)
      if user.nil?
        # User ID in session is invalid (user might have been deleted).
        session.delete(:user_id)
        @current_user = nil
      else
        @current_user = user
      end
    rescue SQLite3::Exception => e
      logger.error "Database error fetching current user (ID: #{user_id}): #{e.message}"
      @current_user = nil # Don't assume user is logged in if DB error occurs
    end
    @current_user
  end

  # --- Weather Forecast Helpers (Original Logic Preserved) ---

  # Fetches forecast data from the Weatherbit API.
  def fetch_forecast
    api_key = ENV['WEATHERBIT_API_KEY']
    # Check if API key is configured
    unless api_key
      logger.error "WEATHERBIT_API_KEY is not set. Cannot fetch forecast."
      return { 'error' => 'Weather service is not configured.' }
    end

    city = 'Copenhagen' # Original city
    api_url = "https://api.weatherbit.io/v2.0/forecast/daily?city=#{city}&key=#{api_key}&days=7"

    begin
      response = HTTParty.get(api_url, timeout: 10) # Added timeout

      if response.success? # Check for 2xx status codes
        JSON.parse(response.body)
      else
        logger.error "Failed to retrieve weather data. API response code: #{response.code}, Body: #{response.body}"
        { 'error' => "Failed to retrieve weather data. API responded with status: #{response.code}" }
      end
    rescue HTTParty::Error, Timeout::Error, StandardError => e # Catch specific and general errors
      logger.error "Error fetching forecast from #{api_url}: #{e.class} - #{e.message}"
      { 'error' => "Failed to connect to weather service: #{e.message}" }
    end
  end

  # Retrieves forecast data, using cache if valid, otherwise fetches fresh data.
  # Original caching logic (1 hour) is preserved.
  def get_cached_forecast
    cache = settings.forecast_cache
    expiration = settings.forecast_cache_expiration

    # Check if cache is invalid (nil or expired)
    if cache.nil? || expiration < Time.now
      logger.info "Weather forecast cache miss or expired. Fetching new data."
      new_forecast = fetch_forecast
      # Only update cache if fetch was successful (no 'error' key)
      unless new_forecast.key?('error')
        settings.forecast_cache = new_forecast
        settings.forecast_cache_expiration = Time.now + 3600 # 1 hour cache
        logger.info "Weather forecast cache updated."
        return new_forecast # Return the newly fetched data
      else
        logger.warn "Failed to fetch new forecast data. Returning error or potentially stale data if available."
        # If there's old data in cache, return it to avoid showing nothing,
        # but maybe add a flag indicating it's stale? For now, return error.
        return new_forecast # Return the error message from fetch_forecast
      end
    else
      logger.debug "Weather forecast cache hit." # Use debug for less noise
      return cache # Return data from cache
    end
  end

  # --- Security Helpers (Original Logic Preserved) ---

  # Hashes a password using BCrypt.
  def hash_password(password)
    BCrypt::Password.create(password)
  end

  # Verifies a given password against a stored BCrypt hash.
  def verify_password(stored_hash, password)
    # Ensure stored_hash is not nil or empty before proceeding
    return false if stored_hash.nil? || stored_hash.empty?

    begin
      bcrypt_hash = BCrypt::Password.new(stored_hash)
      bcrypt_hash == password
    rescue BCrypt::Errors::InvalidHash
      logger.error "Attempted to verify password against an invalid hash."
      false # Treat invalid hash as verification failure
    end
  end
end

################################################################################
# Page Routes (HTML Responses)
################################################################################

# GET / - Search page (and homepage)
get '/' do
  # Use safe navigation (&.) and strip whitespace
  q = params[:q]&.strip
  language = params[:language] || 'en'

  @search_results = [] # Initialize to ensure it's always an array

  # Perform search only if query parameter 'q' is present and not empty
  if q && !q.empty?
    # Use squish to normalize whitespace in the SQL query string
    sql = <<-SQL.squish
      SELECT p.*
      FROM pages p
      JOIN pages_fts f ON p.rowid = f.rowid
      WHERE f.pages_fts MATCH ? AND p.language = ?
      ORDER BY f.rank DESC; -- Original ranking logic
    SQL

    begin
      # Execute the search query
      @search_results = db.execute(sql, [q, language])
    rescue SQLite3::Exception => e
      # Log database errors and inform the user via flash message
      logger.error "Database error during search for '#{q}' (lang: #{language}): #{e.message}"
      flash.now[:error] = 'An error occurred during the search. Please try again later.'
      # @search_results remains empty as initialized
    end
  end

  # Render the search view
  erb :search
end

# GET /about - About page
get '/about' do
  erb :about
end

# GET /weather - Weather forecast page
get '/weather' do
  # Fetch cached or fresh forecast data
  @forecast_data = get_cached_forecast
  # Render the weather view
  erb :weather
end

# GET /register - Registration page
get '/register' do
  # Redirect logged-in users away from the registration page
  redirect '/' if current_user
  # Render the registration view
  erb :register
end

# GET /login - Login page
get '/login' do
  # Redirect logged-in users away from the login page
  redirect '/' if current_user
  # Render the login view
  erb :login
end

################################################################################
# User Authentication Routes (POST requests, HTML/Redirect Responses)
# Preserving original flow: Render form with error OR redirect on success
################################################################################

# POST /api/login - Handle login form submission
# NOTE: Path is '/api/login' but behavior is form-based (render/redirect)
post '/api/login' do
  username = params[:username]&.strip
  password = params[:password] # Don't strip password

  user = nil
  error = nil

  # Basic validation
  if username.nil? || username.empty? || password.nil? || password.empty?
    error = 'Username and password are required.'
  else
    # Fetch user from database
    begin
      user = db.get_first_row('SELECT * FROM users WHERE username = ?', username)
    rescue SQLite3::Exception => e
      logger.error "Database error during login for user '#{username}': #{e.message}"
      error = 'An internal error occurred. Please try again.'
    end
  end

  # If no DB error, proceed with password verification
  if error.nil?
    if user && verify_password(user['password'], password)
      # Login successful: Set session and redirect
      session[:user_id] = user['id']
      flash[:notice] = 'You were successfully logged in.'
      redirect '/'
    else
      # Login failed: Invalid credentials
      error = 'Invalid username or password.'
      logger.warn "Failed login attempt for username: '#{username}'"
    end
  end

  # If we reached here, there was an error (validation, DB, or credentials)
  # Re-render the login page with the error message.
  # Preserve original behavior: render :login with locals.
  flash.now[:error] = error # Use flash.now for rendering within the same request cycle
  erb :login, locals: { error: error } # Pass error for compatibility if view uses it directly
end

# GET /api/logout - Handle logout action
# NOTE: Path is '/api/logout' but behavior is redirect-based.
get '/api/logout' do
  # Preserve original behavior: Clear session, set flash, redirect.
  session.clear
  flash[:notice] = 'You were logged out.'
  redirect '/'
end

# POST /api/register - Handle registration form submission
# NOTE: Path is '/api/register' but behavior is form-based (render/redirect)
post '/api/register' do
  # Redirect if already logged in
  redirect '/' if current_user

  # Trim input values for consistency
  username = params[:username]&.strip
  email = params[:email]&.strip
  password = params[:password] # Keep original password for comparison/hashing
  password2 = params[:password2]

  error = nil

  # --- Input Validation ---
  if username.nil? || username.empty?
    error = 'You have to enter a username'
  elsif email.nil? || email.empty? || !email.include?('@') # Basic email format check
    error = 'You have to enter a valid email address'
  elsif password.nil? || password.empty? # Check original password for emptiness
    error = 'You have to enter a password'
  elsif password != password2
    error = 'The two passwords do not match'
  else
    # --- Check for existing user/email (Database interaction) ---
    begin
      existing_user = db.get_first_row('SELECT id FROM users WHERE username = ?', username)
      existing_email = db.get_first_row('SELECT id FROM users WHERE email = ?', email)

      if existing_user
        error = 'The username is already taken'
      elsif existing_email
        error = 'This email is already registered'
      end
    rescue SQLite3::Exception => e
      logger.error "Database error during registration check for '#{username}'/'#{email}': #{e.message}"
      error = 'An internal error occurred during registration check. Please try again.'
    end
  end

  # --- Process Registration or Show Errors ---
  if error
    # Preserve original behavior: Re-render form with error and submitted values.
    flash.now[:error] = error
    erb :register, locals: {
      error: error,
      username: params[:username], # Pass back original params for form repopulation
      email: params[:email]
    }
  else
    # --- Create User (Database interaction) ---
    begin
      hashed_password = hash_password(password) # Hash the valid password
      db.execute('INSERT INTO users (username, email, password) VALUES (?, ?, ?)',
                 [username, email, hashed_password])

      new_user_id = db.last_insert_row_id

      # Preserve original behavior: Log the new user in and redirect.
      session[:user_id] = new_user_id
      flash[:notice] = 'You were successfully registered and are now logged in.'
      redirect '/'
    rescue SQLite3::Exception => e
      logger.error "Database error during user insertion for '#{username}': #{e.message}"
      # Render registration form again with a generic error
      flash.now[:error] = 'An internal error occurred while creating your account. Please try again.'
      erb :register, locals: {
        error: flash.now[:error],
        username: params[:username],
        email: params[:email]
      }
    end
  end
end

################################################################################
# API Routes (JSON Responses)
# These routes are intended to return JSON data.
################################################################################

# GET /api/search - JSON search results
get '/api/search' do
  content_type :json # Indicate JSON response

  q = params[:q]&.strip
  language = params[:language] || 'en'
  search_results = []

  if q && !q.empty?
    sql = <<-SQL.squish
      SELECT p.*
      FROM pages p
      JOIN pages_fts f ON p.rowid = f.rowid
      WHERE f.pages_fts MATCH ? AND p.language = ?
      ORDER BY f.rank DESC;
    SQL
    begin
      search_results = db.execute(sql, [q, language])
    rescue SQLite3::Exception => e
      logger.error "API Search Error: #{e.message}"
      # Halt with a 500 error and JSON response for API consumers
      halt 500, { status: 'error', message: 'Database error occurred during search.' }.to_json
    end
  end

  # Original JSON response structure
  {
    results: search_results,
    count: search_results.length,
    query: q,
    language: language
  }.to_json
end

# GET /api/weather - JSON weather forecast
get '/api/weather' do
  content_type :json # Indicate JSON response

  forecast_data = get_cached_forecast

  # Check if the forecast data contains an error from the helper
  if forecast_data.key?('error')
    # Return an error status and message in JSON format
    status 503 # Service Unavailable might be appropriate if weather API fails
    { status: 'error', message: forecast_data['error'] }.to_json
  else
    # Return the successful forecast data
    forecast_data.to_json
  end
end

################################################################################
# Error Handling Routes
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
# Note: Specific rescues within routes handle errors more granularly first.
# This catches unhandled exceptions.
error do
  status 500
  error_message = env['sinatra.error']&.message || 'An unexpected error occurred.'
  logger.error "Unhandled Application Error: #{env['sinatra.error']&.class} - #{error_message}"
  logger.error env['sinatra.error']&.backtrace&.join("\n") # Log backtrace if available

  # Check if the request expects JSON
  if request.accept?('application/json')
    content_type :json
    { status: 'error', message: 'Internal server error.' }.to_json
  else
    # Render a generic HTML error page
    # You should create an 'erb :server_error' template
    @error_message = error_message # Pass message to the view if needed
    erb :server_error rescue "<h1>Internal Server Error</h1><p>Sorry, something went wrong.</p>" # Fallback HTML
  end
end
