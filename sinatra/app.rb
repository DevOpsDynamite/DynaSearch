# frozen_string_literal: true

require 'sinatra'
require 'sinatra/flash'
require 'sqlite3'
require 'json'
require 'sinatra/contrib'
require 'dotenv/load'
require 'digest'
require 'bcrypt'

set :bind, '0.0.0.0'
set :port, 4568
enable :sessions
set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(32)

register Sinatra::Flash

################################################################################
# Database Functions
################################################################################


DB_PATH = if ENV['RACK_ENV'] == 'test'
  # Use a separate test database
  File.join(__dir__, 'test', 'test_whoknows.db')
elsif ENV['DATABASE_PATH']
  # Use the path from an environment variable if provided
  ENV['DATABASE_PATH']
else
  # Fallback for development
  File.join(__dir__, 'whoknows.db')
end



configure do
  if ENV['RACK_ENV'] == 'test'
    # Don’t exit if the file doesn’t exist—tests will create it.
    unless File.exist?(DB_PATH)
      # Create an empty file so SQLite can open it.
      SQLite3::Database.new(DB_PATH).close
    end
  else
    # Production/Development logic
    unless File.exist?(DB_PATH)
      puts "Database not found at #{DB_PATH}"
      exit(1)
    end
  end

  # Create a single, shared SQLite cadasonnection
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
end

################################################################################
# Page Routes
################################################################################

get '/' do
  q = params[:q]
  language = params[:language] || 'en'

  @search_results = if q.nil? || q.empty?
                      []
                    else
                      db.execute(
                        'SELECT * FROM pages WHERE language = ? AND content LIKE ?',
                        [language, "%#{q}%"]
                      )
                    end

  # Render the ERB template named "search"
  erb :search
end

get '/about' do
  erb :about
end

get '/weather' do
  'This is weather page'
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
  'Test api search'
end

get '/api/weather' do
  'Test api weather'
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

  # Validate input
  if params[:username].to_s.strip.empty?
    error = 'You have to enter a username'
  elsif params[:email].to_s.strip.empty? || !params[:email].include?('@')
    error = 'You have to enter a valid email address'
  elsif params[:password].to_s.strip.empty?
    error = 'You have to enter a password'
  elsif params[:password] != params[:password2]
    error = 'The two passwords do not match'
  elsif db.execute('SELECT id FROM users WHERE username = ?', params[:username]).first
    error = 'The username is already taken'
  end

  if error
    # Re-render the registration form with an error message
    erb :register, locals: { error: error }
  else
    # Hash the password using BCrypt
    hashed_password = hash_password(params[:password])

    # Insert the new user into the database
    db.execute('INSERT INTO users (username, email, password) VALUES (?, ?, ?)',
               [params[:username], params[:email], hashed_password])

    flash[:notice] = 'You were successfully registered and can login now'
    redirect '/login'
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
