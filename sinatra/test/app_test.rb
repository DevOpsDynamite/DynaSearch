# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'sqlite3'
require 'fileutils'
require 'dotenv'
Dotenv.load

puts "SESSION_SECRET: #{ENV['SESSION_SECRET']}" # Note: Often better to avoid printing secrets, even in tests.

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

    # Create a fresh DB file
    db = SQLite3::Database.new(@test_db_path)

    # Load the main schema
    schema_file = File.join(File.dirname(__dir__), 'schema.sql')
    db.execute_batch(File.read(schema_file)) if File.exist?(schema_file)

    # Load the FTS5 schema additions
    fts5_schema_file = File.join(File.dirname(__dir__), 'fts5.sql')
    if File.exist?(fts5_schema_file)
      db.execute_batch(File.read(fts5_schema_file))
    else
      # Optional: Warn if the file is missing, helps debugging CI environments
      puts "WARNING: FTS5 setup file not found at #{fts5_schema_file}. FTS5 tables/triggers will be missing in test DB."
    end

    # Close the connection used for setup
    db.close

    # Re-open Sinatra's DB connection to point to the newly set up test DB file
    Sinatra::Application.set :db, SQLite3::Database.new(@test_db_path)
    Sinatra::Application.db.results_as_hash = true
  end

  def teardown
    # Ensure the DB connection is closed before deleting the file
    # Check if db is set and is an instance of SQLite3::Database
    if Sinatra::Application.settings.db.is_a?(SQLite3::Database) && !Sinatra::Application.settings.db.closed?
       Sinatra::Application.settings.db.close
    end
    FileUtils.rm_f(@test_db_path)
  end

  # Helper method for registration
  def register(username, password, password2 = nil, email = nil)
    password2 ||= password
    email ||= "#{username}@example.com"
    post '/api/register', { username: username, email: email, password: password, password2: password2 }
    # Removed potentially noisy puts statement
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
    assert_includes response.body, 'You were successfully registered and are now logged in.'
    # Make sure we are actually logged in (e.g., check for logout link)
    assert_includes response.body, 'href="/api/logout">Log out [user1]</a>'

    logout
    # Verify logout worked (e.g., check for login link)
    # assert_includes last_response.body, 'href="/login">Login</a>' # Old assertion with incorrect text
    assert_includes last_response.body, 'href="/login">Log in</a>'  # Corrected assertion with actual text

    # Trying to register with the same username should now fail (as user is logged out)
    response = register('user1', 'default')

    # --- Assertions for failed registration ---
    assert_includes response.body, 'The username is already taken'
    # Add checks to ensure it's the registration page showing the error:
    assert response.ok? # Should be status 200 OK (re-rendered form)
    refute response.redirect? # Should not redirect on validation failure
    assert_includes response.body, '<form action="/api/register"'



    # Test missing username (user is already logged out from previous step)
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

  # This test now just checks if the search page loads without errors
  # It doesn't verify actual search results because the DB is empty by default.
  # TODO: Add sample data in setup and assertions for specific search results
  #       if detailed search testing is needed.
  def test_search
    # Test searching when there are no results (empty DB)
    get '/', { q: 'some search term', language: 'en' }
    assert last_response.ok?, "Search page should load even with no results. Status: #{last_response.status}"
    # Optional: Assert that a "no results found" message appears if applicable
    # assert_includes last_response.body, "No results found"

    # Test loading the search page with no query
    get '/'
    assert last_response.ok?, "Search page should load without query parameters. Status: #{last_response.status}"
  end
end