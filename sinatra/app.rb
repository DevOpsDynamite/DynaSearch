# frozen_string_literal: true

require 'sinatra'
require 'sinatra/flash'
require 'sqlite3'
require 'json'
require 'sinatra/contrib'
require 'dotenv/load'
require 'httparty'
require 'digest'
require 'bcrypt'
require 'nokogiri'
require 'open-uri'
require 'active_support/core_ext/string/filters'

set :bind, '0.0.0.0'
set :port, 4568
enable :sessions
set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(32)

register Sinatra::Flash

################################################################################
# Database Functions
################################################################################
DB_PATH = if ENV['RACK_ENV'] == 'test'
  File.join(__dir__, 'test', 'test_whoknows.db')
elsif ENV['DATABASE_PATH']
  ENV['DATABASE_PATH']
else
  File.join(__dir__, 'whoknows.db')
end

configure do
# Only check for the database file if not in test mode
if ENV['RACK_ENV'] != 'test'
unless File.exist?(DB_PATH)
puts "Database not found at #{DB_PATH}"
exit(1)
end
end

set :db, SQLite3::Database.new(DB_PATH)
settings.db.results_as_hash = true
end

helpers do
  def db
    settings.db
  end

  def current_user
    return unless session[:user_id]

    @current_user ||= db.execute('SELECT * FROM users WHERE id = ?', session[:user_id]).first
  end

  # Initialize cache variables (could be done in configure)
  set :forecast_cache, nil
  set :forecast_cache_expiration, Time.now

  def fetch_forecast
    api_key = ENV['WEATHERBIT_API_KEY']
    city = 'Copenhagen' # Change to your desired city
    api_url = "https://api.weatherbit.io/v2.0/forecast/daily?city=#{city}&key=#{api_key}&days=7"

    response = HTTParty.get(api_url)

    if response.code == 200
      JSON.parse(response.body)
    else
      { 'error' => "Failed to retrieve data. API response code: #{response.code}" }
    end
  end
end

# Caching so our weather-forecast only gets updated once an hour, to limit API calls. 3600 secs = 1 hour

def get_cached_forecast
  if settings.forecast_cache.nil? || settings.forecast_cache_expiration < Time.now
    settings.forecast_cache = fetch_forecast
    settings.forecast_cache_expiration = Time.now + 3600
  end
  settings.forecast_cache
end

################################################################################
# Page Routes
################################################################################

get '/' do
  q = params[:q]
  language = params[:language] || 'en'

  @search_results = []
  if q && !q.strip.empty?
    # FTS5 Search Query
    # 1. Search the pages_fts table using MATCH for the query 'q'.
    # 2. Join back to the original 'pages' table using rowid.
    # 3. Filter by the requested language on the original 'pages' table.
    # 4. Order by FTS5 rank (descending - higher rank is more relevant).
    # Apply .squish here as well
    sql = <<-SQL.squish # <--- MODIFIED HERE
      SELECT p.*
      FROM pages p
      JOIN pages_fts f ON p.rowid = f.rowid
      WHERE f.pages_fts MATCH ? AND p.language = ?
      ORDER BY f.rank DESC; -- Added relevance ranking here (Task 5)
    SQL

    @search_results = db.execute(sql, [q, language])
  end

  # Render the ERB template named "search"
  erb :search
end

get '/about' do
  erb :about
end

get '/weather' do
  @forecast_data = get_cached_forecast
  erb :weather
end

get '/register' do
  if current_user
    redirect '/'
  else
    erb :register
  end
end

get '/login' do
  if current_user
    redirect '/'
  else
    erb :login
  end
end

# GET api pages
get '/api/search' do
  content_type :json

  q = params[:q]
  language = params[:language] || 'en'
  search_results = []

  if q && !q.strip.empty?
    sql = <<-SQL.squish
      SELECT p.*
      FROM pages p
      JOIN pages_fts f ON p.rowid = f.rowid
      WHERE f.pages_fts MATCH ? AND p.language = ?
      ORDER BY f.rank DESC;
    SQL

    search_results = db.execute(sql, [q, language])
  end

  { 
        results: search_results, 
        count: search_results.length,
        query: q,
        language: language 
      }.to_json
end

get '/api/weather' do
  content_type :json
  forecast_data = get_cached_forecast
  forecast_data.to_json
end

################################################################################
# NOT FOUND pages
################################################################################

not_found do
  status 404
  erb :not_found
end

################################################################################
# POST API pages
################################################################################

post '/api/login' do
  username = params[:username]
  password = params[:password]

  user = db.execute('SELECT * FROM users WHERE username = ?', username).first

  if user.nil?
    error = 'Invalid username or password'
  elsif !verify_password(user['password'], password)
    error = 'Invalid username or password'
  else
    flash[:notice] = 'You were logged in'
    session[:user_id] = user['id']
    redirect '/'
  end

  # If there's an error, render the login page with error message
  erb :login, locals: { error: error }
end

get '/api/logout' do
  flash[:notice] = 'You were logged out'
  session.clear
  redirect '/'
end

post '/api/register' do
  # If the user is already logged in, redirect to the search page
  redirect '/' if current_user

  error = nil

  # Consider trimming input for checks and consistency
  username = params[:username].to_s.strip
  email = params[:email].to_s.strip
  password = params[:password].to_s # Keep original for comparison/hashing unless you intend to disallow leading/trailing spaces
  password2 = params[:password2].to_s

  # Validate input
  if username.empty?
    error = 'You have to enter a username'
  elsif email.empty? || !email.include?('@')
    error = 'You have to enter a valid email address'
  elsif password.strip.empty? # Check trimmed password for emptiness
    error = 'You have to enter a password'
  elsif password != password2
    error = 'The two passwords do not match'
  elsif db.execute('SELECT id FROM users WHERE username = ?', username).first
    error = 'The username is already taken'
  elsif db.execute('SELECT id FROM users WHERE email = ?', email).first
    error = 'This email is already registered' # Specific error message for existing email
  end

  if error
    # Re-render the registration form with an error message
    # Pass the submitted username and email back to the form for better UX
    erb :register, locals: { error: error, username: params[:username], email: params[:email] }
  else
    # Hash the password using BCrypt
    hashed_password = hash_password(password) # Hash the original password

    # Insert the new user into the database using trimmed values
    db.execute('INSERT INTO users (username, email, password) VALUES (?, ?, ?)',
               [username, email, hashed_password])

    # Get the ID of the user just created
    new_user_id = db.last_insert_row_id

    # Log the new user in by setting the session
    session[:user_id] = new_user_id

    # Update the flash message
    flash[:notice] = 'You were successfully registered and are now logged in.'

    # Redirect to the main page instead of the login page
    redirect '/'
  end
end

################################################################################
# Security functions
################################################################################

def hash_password(password)
  BCrypt::Password.create(password)
end

def verify_password(stored_hash, password)
  BCrypt::Password.new(stored_hash) == password
end
