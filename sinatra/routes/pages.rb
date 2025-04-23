# frozen_string_literal: true

# Defines routes for standard HTML pages (non-API, non-auth actions)

# GET / - Search page (and homepage)
get '/' do
  # Use safe navigation (&.) and strip whitespace from query param
  q = params[:q]&.strip
  language = params[:language] || 'en'

  # Initialize results array
  @search_results = []

  # Use present? (requires ActiveSupport) to check for nil, empty, or whitespace-only strings
  if q.present?
    settings.logger.info "User searched (Web): term='#{q}', lang='#{language}'"

    # Use ILIKE for case-insensitive search in PostgreSQL
    # Use $1, $2 placeholders
    # Cast the language enum column to text for comparison, or use the enum value directly if your driver handles it
    # Removed FTS5 join and ORDER BY rank
    sql = <<-SQL.squish
        SELECT *
        FROM pages
        WHERE content ILIKE $1 AND language::text = $2;
    SQL

    begin
      # Execute the search query using exec_params
      # Add wildcards (%) to the query parameter for ILIKE
      search_result_obj = db.exec_params(sql, ["%#{q}%", language])
      # Convert PG::Result object to an array of hashes
      @search_results = search_result_obj.to_a
    rescue PG::Error => e # Catch PostgreSQL errors
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
  # Fetch cached or fresh forecast data using helper
  @forecast_data = cached_forecast
  # Render the weather view
  erb :weather
end

# GET /register - Registration page view
get '/register' do
  # Redirect logged-in users away from the registration page
  redirect '/' if current_user
  # Render the registration view
  erb :register
end

# GET /login - Login page view
get '/login' do
  # Redirect logged-in users away from the login page
  redirect '/' if current_user
  # Render the login view
  erb :login
end