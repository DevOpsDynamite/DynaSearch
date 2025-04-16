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
      # Consider rescuing JSON::ParserError specifically if API might return invalid JSON
      # rescue JSON::ParserError => e
      #   logger.error "Error parsing weather API response: #{e.message}"
      #   { 'error' => 'Failed to parse weather data.' }
    end
  end

  # Retrieves forecast data, using cache if valid, otherwise fetches fresh data.
  def get_cached_forecast
    cache = settings.forecast_cache
    expiration = settings.forecast_cache_expiration

    # Check cache validity using UTC time for comparison
    # Use Time.now.utc for consistent time zone handling
    if cache.nil? || expiration < Time.now.utc
      logger.info 'Weather forecast cache miss or expired. Fetching new data.'
      new_forecast = fetch_forecast

      # Update cache only if the fetch was successful (no 'error' key)
      if new_forecast.key?('error')
        # Log failure but return the error hash from fetch_forecast
        logger.warn 'Failed to fetch new forecast data. Returning error.'
        new_forecast
      else
        settings.forecast_cache = new_forecast
        # Use Time.now.utc when setting the new expiration time
        settings.forecast_cache_expiration = Time.now.utc + 3600 # 1 hour cache
        logger.info 'Weather forecast cache updated.'
        new_forecast # Return the newly fetched data
      end
    else
      # Cache hit, return cached data
      logger.debug 'Weather forecast cache hit.'
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
end # End of helpers block
