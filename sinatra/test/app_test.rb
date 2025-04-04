# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'sqlite3'
require 'fileutils'
require 'dotenv'
Dotenv.load

puts "SESSION_SECRET: #{ENV['SESSION_SECRET']}"

require_relative '../app'

class WhoKnowsTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    @test_db_path = File.join(__dir__, 'test_whoknows.db')

    # Ensure the directory exists
    FileUtils.mkdir_p(File.dirname(@test_db_path))

    # Remove any old file
    FileUtils.rm_f(@test_db_path)

    # Create a fresh DB file and load the schema
    db = SQLite3::Database.new(@test_db_path)
    schema_file = File.join(File.dirname(__dir__), 'schema.sql')
    db.execute_batch(File.read(schema_file)) if File.exist?(schema_file)
    db.close

    # Re-open Sinatra's DB connection to point to the new DB file
    Sinatra::Application.set :db, SQLite3::Database.new(@test_db_path)
    Sinatra::Application.db.results_as_hash = true
  end

  def teardown
    FileUtils.rm_f(@test_db_path)
  end

  # Helper method for registration
  def register(username, password, password2 = nil, email = nil)
    password2 ||= password
    email ||= "#{username}@example.com"
    post '/api/register', { username: username, email: email, password: password, password2: password2 }
    unless last_response.redirect?
      # puts "Registration response (#{last_response.status}): #{last_response.body}"
    end
    follow_redirect! if last_response.redirect?
    last_response
  end

  # Helper method for login
  def login(username, password)
    post '/api/login', { username: username, password: password }
    follow_redirect! if last_response.redirect?
    last_response
  end

  # Helper method for logout
  def logout
    get '/api/logout'
    follow_redirect! if last_response.redirect?
    last_response
  end

  def test_register
    # First registration should succeed
    response = register('user1', 'default')
    assert_includes response.body, 'You were successfully registered and can login now'

    # Trying to register with the same username should fail
    response = register('user1', 'default')
    assert_includes response.body, 'The username is already taken'

    # Test missing username
    response = register('', 'default')
    assert_includes response.body, 'You have to enter a username'

    # Test missing password
    response = register('meh', '')
    assert_includes response.body, 'You have to enter a password'

    # Test non-matching passwords
    response = register('meh', 'x', 'y')
    assert_includes response.body, 'The two passwords do not match'

    # Test invalid email
    response = register('meh', 'foo', nil, 'broken')
    assert_includes response.body, 'You have to enter a valid email address'
  end

  def test_login_logout
    # Register and login the user
    register('user1', 'default')
    response = login('user1', 'default')
    assert_includes response.body, 'You were logged in'

    # Test logout
    response = logout
    assert_includes response.body, 'You were logged out'

    # Test login with wrong password
    response = login('user1', 'wrongpassword')
    assert_includes response.body, 'Invalid username or password'

    # Test login with non-existent user
    response = login('user2', 'wrongpassword')
    assert_includes response.body, 'Invalid username or password'
  end

  def test_search
    get '/', { q: 'some search term', language: 'en' }
    assert last_response.ok?
  end
end
