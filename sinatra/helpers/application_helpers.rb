# frozen_string_literal: true

# This file contains helper methods accessible from routes and views.
# Sinatra automatically makes methods defined in files required after
# the initial 'require "sinatra"' available as helpers.
# Alternatively, wrap this in a module ApplicationHelpers; helpers ApplicationHelpers

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
  end # End of helpers block
  