# frozen_string_literal: true

# Defines routes for standard HTML pages (non-API, non-auth actions)

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
