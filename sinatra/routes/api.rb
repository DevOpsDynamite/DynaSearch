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
    # Use ILIKE for case-insensitive search, $1, $2 placeholders
    # Removed FTS5 join and ORDER BY rank
    sql = <<-SQL.squish
        SELECT *
        FROM pages
        WHERE content ILIKE $1 AND language::text = $2;
    SQL
    begin
      # Use exec_params, add wildcards
      search_result_obj = db.exec_params(sql, ["%#{q}%", language])
      # Convert PG::Result to array of hashes
      search_results = search_result_obj.to_a
    rescue PG::Error => e # Catch PostgreSQL errors
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