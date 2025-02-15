require 'sinatra'

set :port, 4568

#Get pages
get '/' do
  'Hello, World!'
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