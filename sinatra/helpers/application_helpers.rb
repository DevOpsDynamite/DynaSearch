# frozen_string_literal: true

require 'forwardable' # Required for delegation
require 'httparty'    # Ensure HTTParty is required here if not already
require 'json'        # Ensure JSON is required here if not already
require 'bcrypt'      # Ensure BCrypt is required for password helpers
require 'active_support/core_ext/object/blank' # For blank?

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
      user = db.get_first_row('SELECT * FROM users WHERE id = ?', user_id)
      if user.nil?
        # Clear invalid session ID if user not found
        session.delete(:user_id)
        @current_user = nil
      else
        # Store valid user hash
        @current_user = user
      end
    rescue SQLite3::Exception => e
      # Log DB error and ensure user is not considered logged in
      logger.error "Database error fetching current user (ID: #{user_id}): #{e.message}"
      @current_user = nil
    end
    # Return the result (user hash or nil)
    @current_user
  end

  # --- Weather Forecast Helpers ---

  # Fetches forecast data from the Weatherbit API.
  # Includes Prometheus metric increments.
  def fetch_forecast
    api_key = ENV['WEATHERBIT_API_KEY']
    unless api_key
      # Increment failure counter for configuration error
      WEATHER_FETCH_FAILURE_TOTAL.increment(labels: { reason: 'config_error' }) # METRIC
      logger.error 'WEATHERBIT_API_KEY is not set. Cannot fetch forecast.' # Keep log for detailed debugging
      return { 'error' => 'Weather service is not configured.' }
    end

    city = 'Copenhagen' # Consider making this configurable
    api_url = "https://api.weatherbit.io/v2.0/forecast/daily?city=#{city}&key=#{api_key}&days=7"

    begin
      # Increment attempt counter right before the call
      WEATHER_FETCH_ATTEMPTS_TOTAL.increment # METRIC

      # Make the API call with a timeout
      response = HTTParty.get(api_url, timeout: 10)

      # Check for successful HTTP response (2xx)
      if response.success?
        # Increment success counter
        WEATHER_FETCH_SUCCESS_TOTAL.increment # METRIC
        # Parse the JSON response body
        JSON.parse(response.body)
      else
        # Increment failure counter for API error (non-2xx status)
        WEATHER_FETCH_FAILURE_TOTAL.increment(labels: { reason: 'api_error' }) # METRIC
        # Log API error details
        logger.error "Failed to retrieve weather data. API response code: #{response.code}, Body: #{response.body}" # Keep log
        { 'error' => "Failed to retrieve weather data. API responded with status: #{response.code}" }
      end
    # Catch specific HTTParty and Timeout errors.
    rescue HTTParty::Error, Timeout::Error => e
      # Increment failure counter for connection/timeout error
      WEATHER_FETCH_FAILURE_TOTAL.increment(labels: { reason: 'connection_error' }) # METRIC
      # Log error details
      logger.error "Error fetching forecast from #{api_url}: #{e.class} - #{e.message}" # Keep log
      { 'error' => "Failed to connect to weather service: #{e.message}" }
    # Consider rescuing JSON::ParserError specifically if API might return invalid JSON
    # rescue JSON::ParserError => e
    #   WEATHER_FETCH_FAILURE_TOTAL.increment(labels: { reason: 'parse_error' }) # METRIC
    #   logger.error "Error parsing weather API response: #{e.message}" # Keep log
    #   { 'error' => 'Failed to parse weather data.' }
    end
  end

  # Retrieves forecast data, using cache if valid, otherwise fetches fresh data.
  def cached_forecast
    cache = settings.forecast_cache
    expiration = settings.forecast_cache_expiration

    # Check cache validity using UTC time for comparison
    # Use Time.now.utc for consistent time zone handling
    if cache.nil? || expiration < Time.now.utc
      logger.info 'Weather forecast cache miss or expired. Fetching new data.' # Existing log
      new_forecast = fetch_forecast # This call now increments metrics internally

      # Update cache only if the fetch was successful (no 'error' key)
      if new_forecast.key?('error')
        # Log failure but return the error hash from fetch_forecast
        logger.warn 'Failed to fetch new forecast data. Returning error.' # Existing log
      else
        settings.forecast_cache = new_forecast
        # Use Time.now.utc when setting the new expiration time
        settings.forecast_cache_expiration = Time.now.utc + 3600 # 1 hour cache
        logger.info 'Weather forecast cache updated.' # Existing log
      end
      new_forecast
    else
      # Cache hit, return cached data
      logger.debug 'Weather forecast cache hit.' # Existing log
      cache
    end
  end

  # --- Security Helpers ---

  # Hashes a password using BCrypt.
  def hash_password(password)
    BCrypt::Password.create(password)
  end

  # Verifies a given password against a stored BCrypt hash.
  def verify_password(stored_hash, password)
    # Use blank? (requires ActiveSupport) to check for nil or empty string
    return false if stored_hash.blank?

    begin
      # Create BCrypt object from the stored hash
      bcrypt_hash = BCrypt::Password.new(stored_hash)
      # Use BCrypt's comparison method
      bcrypt_hash == password
    rescue BCrypt::Errors::InvalidHash
      # Log if the stored hash is invalid
      logger.error 'Attempted to verify password against an invalid hash.'
      false # Treat invalid hash as verification failure
    end
  end
end