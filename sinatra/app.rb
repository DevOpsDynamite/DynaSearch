require 'sinatra'
require 'sqlite3'
require 'json'
require 'sinatra/contrib'

set :port, 4568

DB_PATH = File.expand_path('../whoknows.db', __FILE__)

configure do
  # Check if DB exists 
  unless File.exist?(DB_PATH)
    puts "Database not found at #{DB_PATH}"
    exit(1)
  end

  # Create a single, shared SQLite connection
  set :db, SQLite3::Database.new(DB_PATH)

  # This line makes SQLite return results as a hash instead of arrays,
  # so we can do row['column_name'] rather than row[0].
  settings.db.results_as_hash = true
end

helpers do
  def db
    settings.db
  end
end



# Basic route to test DB
get '/' do
  # Example query: just read from a table called 'pages'
  results = db.execute('SELECT * FROM pages LIMIT 10')
  # Convert the results to JSON just to see them
  results.to_json
end

get '/weather' do
  'This is weather page'
end

get '/register' do
  'This is register page'
end

get '/login' do
  'This is login page'
end

#GET api pages
get '/api/search' do
  'Test api search'
end

get '/api/weather' do
  'Test api weather'
end

get '/api/logout' do
  'Test api logout'
end

# POST pages

# POST api pags
post '/api/login' do
  'Check login'
end

post '/api/logout' do
  'Check logout'
end