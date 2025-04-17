# frozen_string_literal: true

# Defines routes for standard HTML pages (non-API, non-auth actions)

# GET / - Search page (and homepage)
get '/' do
  # Use safe navigation (&.) and strip whitespace from query param
  q = params[:q]&.strip
  language = params[:language] || 'en'

  # Initialize results array
  @search_results = []

  # Check if a query string is provided and not just whitespace
  # Using standard Ruby check:
  query_provided = q && !q.strip.empty?
  # Or using ActiveSupport (if available):
  # query_provided = q.present? 

  if query_provided
    # Log the search query here (only when a search is performed)
    settings.logger.info "User searched (Web): term='#{q}', lang='#{language}'"

    # Use squish to normalize whitespace in the SQL query string
    # Requires ActiveSupport, or implement your own squish if needed
    # If not using ActiveSupport for squish, you might just use the query as is
    # or use q.split.join(' ') for basic whitespace normalization.
    sql = <<-SQL
        SELECT p.*
        FROM pages p
        JOIN pages_fts f ON p.rowid = f.rowid
        WHERE f.pages_fts MATCH ? AND p.language = ?
        ORDER BY f.rank DESC; -- Original ranking logic
    SQL
    # Add .squish if using ActiveSupport: sql = <<-SQL.squish ...

    begin
      # Execute the search query
      @search_results = db.execute(sql, [q, language])
    rescue SQLite3::Exception => e
      # Log database errors and inform the user via flash message
      logger.error "Database error during search for '#{q}' (lang: #{language}): #{e.message}"
      # Ensure sinatra-flash or similar is configured for this to work
      flash.now[:error] = 'An error occurred during the search. Please try again later.'
      # @search_results remains empty as initialized
    end
  end # End of query execution block

  # Render the search view ALWAYS
  # The view should handle the case where @search_results is empty
  erb :search
end

# Other routes remain the same...

# GET /about - About page
get '/about' do
  erb :about
end

# GET /weather - Weather forecast page
get '/weather' do
  @forecast_data = cached_forecast # Assumes this helper exists
  erb :weather
end

# GET /register - Registration page view
get '/register' do
  redirect '/' if current_user # Assumes current_user helper exists
  erb :register
end

# GET /login - Login page view
get '/login' do
  redirect '/' if current_user # Assumes current_user helper exists
  erb :login
end