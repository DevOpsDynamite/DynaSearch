# frozen_string_literal: true

require 'forwardable' # Required for delegation

# This file contains helper methods accessible from routes and views.

helpers do
  # Use Forwardable to delegate db method to settings object
  extend Forwardable
  def_delegator :settings, :db

  # Retrieves the currently logged-in user based on session data.
  def current_user
    # Return memoized value if already calculated for this request
    return @current_user if defined?(@current_user)

    user_id = session[:user_id]
    # Return nil immediately if no user_id in session
    return @current_user = nil unless user_id

    begin
      # Use exec_params with $1 placeholder, .first to get the single row hash
      user_result = db.exec_params('SELECT * FROM users WHERE id = $1', [user_id])
      user = user_result.first # Get the hash or nil

      if user.nil?
        # Clear invalid session ID if user not found
        session.delete(:user_id)
        @current_user = nil
      else
        # Store valid user hash
        @current_user = user
      end
    rescue PG::Error => e # Catch PostgreSQL errors
      # Log DB error and ensure user is not considered logged in
      logger.error "Database error fetching current user (ID: #{user_id}): #{e.message}"
      @current_user = nil
    end
    # Return the result (user hash or nil)
    @current_user
  end

  # --- Weather Forecast Helpers ---
  # (No database changes needed in this section)
  # Fetches forecast data from the Weatherbit API.
  def fetch_forecast
    api_key = ENV['WEATHERBIT_API_KEY']
    unless api_key
      logger.error 'WEATHERBIT_API_KEY is not set. Cannot fetch forecast.'
      return { 'error' => 'Weather service is not configured.' }
    end

    city = 'Copenhagen' # Consider making this configurable
    api_url = "https://api.weatherbit.io/v2.0/forecast/daily?city=#{city}&key=#{api_key}&days=7"

    begin
      # Make the API call with a timeout
      response = HTTParty.get(api_url, timeout: 10)

      # Check for successful HTTP response (2xx)
      if response.success?
        # Parse the JSON response body
        JSON.parse(response.body)
      else
        # Log API error details
        logger.error "Failed to retrieve weather data. API response code: #{response.code}, Body: #{response.body}"
        { 'error' => "Failed to retrieve weather data. API responded with status: #{response.code}" }
      end
    # Catch specific HTTParty and Timeout errors. Removed StandardError rescue.
    rescue HTTParty::Error, Timeout::Error => e
      logger.error "Error fetching forecast from #{api_url}: #{e.class} - #{e.message}"
      { 'error' => "Failed to connect to weather service: #{e.message}" }
    end
  end

  # Retrieves forecast data, using cache if valid, otherwise fetches fresh data.
  def cached_forecast
    cache = settings.forecast_cache
    expiration = settings.forecast_cache_expiration

    if cache.nil? || expiration < Time.now.utc
      logger.info 'Weather forecast cache miss or expired. Fetching new data.'
      new_forecast = fetch_forecast

      if new_forecast.key?('error')
        logger.warn 'Failed to fetch new forecast data. Returning error.'
      else
        settings.forecast_cache = new_forecast
        settings.forecast_cache_expiration = Time.now.utc + 3600 # 1 hour cache
        logger.info 'Weather forecast cache updated.'
      end
      new_forecast
    else
      logger.debug 'Weather forecast cache hit.'
      cache
    end
  end

  # --- Security Helpers ---
  # (No database changes needed in this section)
  # Hashes a password using BCrypt.
  def hash_password(password)
    BCrypt::Password.create(password)
  end

  # Verifies a given password against a stored BCrypt hash.
  def verify_password(stored_hash, password)
    return false if stored_hash.blank?

    begin
      bcrypt_hash = BCrypt::Password.new(stored_hash)
      bcrypt_hash == password
    rescue BCrypt::Errors::InvalidHash
      logger.error 'Attempted to verify password against an invalid hash.'
      false
    end
  end
end