# frozen_string_literal: true

# Defines routes that are intended to be consumed as a JSON API.

# GET /api/search - JSON search results
get '/api/search' do
  content_type :json # Indicate JSON response

  q = params[:q]&.strip
  language = params[:language] || 'en'
  search_results = []

  # Use present? (requires ActiveSupport) to check query presence
  if q.present?
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

  # Construct and return the JSON response
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

  # Get forecast data (potentially cached)
  forecast_data = cached_forecast

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
