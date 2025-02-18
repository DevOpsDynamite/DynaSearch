require 'sinatra'
require 'sinatra/flash'
require 'sqlite3'
require 'json'
require 'sinatra/contrib'
require 'dotenv/load'
require 'digest'


set :port, 4568
enable :sessions
set :session_secret, ENV['SESSION_SECRET'] || 'fallback_secret'

register Sinatra::Flash

################################################################################ 
# Database Functions
################################################################################


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

  def current_user
    if session[:user_id]
      @current_user ||= db.execute("SELECT * FROM users WHERE id = ?", session[:user_id]).first
    end
  end
end


################################################################################
# Page Routes
################################################################################

get '/' do
  q = params[:q]
  language = params[:language] || 'en'

  if q.nil? || q.empty?
    @search_results = []
  else
    @search_results = db.execute(
      "SELECT * FROM pages WHERE language = ? AND content LIKE ?",
      [language, "%#{q}%"]
    )
  end

  # Render the ERB template named "search"
  erb :search  
end


get '/weather' do
  'This is weather page'
end

get '/register' do
  'This is register page'
end

get '/login' do
  if current_user
    redirect '/'
  else
    erb :login
  end
end


#GET api pages
get '/api/search' do
  'Test api search'
end

get '/api/weather' do
  'Test api weather'
end




################################################################################ 
# POST pages
################################################################################ 


post '/api/login' do
  username = params[:username]
  password = params[:password]

  user = db.execute("SELECT * FROM users WHERE username = ?", username).first

  if user.nil?
    error = "Invalid username"
  elsif !verify_password(user["password"], password)
    error = "Invalid password"
  else
    flash[:notice] = "You were logged in"
    session[:user_id] = user["id"]
    redirect '/'
  end

  # If there's an error, render the login page with error message
  erb :login, locals: { error: error }
end

get '/api/logout' do
  flash[:notice] = "You were logged out"
  session.clear 
  redirect '/'
end


################################################################################ 
#Security functions
################################################################################ 

def hash_password(password)
  Digest::MD5.hexdigest(password)
end

def verify_password(stored_hash, password)
  stored_hash == hash_password(password)
end