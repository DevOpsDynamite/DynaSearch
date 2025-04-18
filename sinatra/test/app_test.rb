# frozen_string_literal: true

# Set environment to test before loading the app
ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'sqlite3'
require 'fileutils'
require 'dotenv'
# Load environment variables from .env files (if any)
Dotenv.load('.env.test', '.env')

# Explicitly require ActiveSupport extensions used in the app/tests if needed
# Note: Often covered by '../app' but explicit is safer.
require 'active_support/core_ext/object/blank'

# Set a default dummy session secret for the test environment if not already set
ENV['SESSION_SECRET'] ||= 'a_secure_random_string_for_testing_purposes_only_1234567890_1234567890'

# Load the Sinatra application entry point
require_relative '../app'

class WhoKnowsTest < Minitest::Test
  # Include Rack::Test helper methods (e.g., get, post, last_response)
  include Rack::Test::Methods

  # Define the Rack application to test
  def app
    # Sinatra::Application is the default instance when using classic style
    Sinatra::Application
  end

  # Runs before each test method
  def setup
    @test_db_path = File.join(__dir__, 'test_whoknows.db')
    db_dir = File.dirname(@test_db_path)

    # Ensure the test database directory exists
    FileUtils.mkdir_p(db_dir) unless Dir.exist?(db_dir)

    # Clean up any previous test database file
    FileUtils.rm_f(@test_db_path)

    # Create and initialize a fresh test database
    begin
      db = SQLite3::Database.new(@test_db_path)
      db.results_as_hash = true # Match application setting

      # Load the main schema
      schema_file = File.join(File.dirname(__dir__), 'schema.sql')
      if File.exist?(schema_file)
        db.execute_batch(File.read(schema_file))
      else
        warn "WARN: Main schema file not found at #{schema_file}. Test DB will be empty."
      end

      # Load the FTS5 schema additions
      fts5_schema_file = File.join(File.dirname(__dir__), 'fts5.sql')
      if File.exist?(fts5_schema_file)
        db.execute_batch(File.read(fts5_schema_file))
      else
        warn "WARN: FTS5 setup file not found at #{fts5_schema_file}. FTS features may not work."
      end
    ensure
      # Ensure the setup connection is closed
      db&.close
    end

    # Configure the Sinatra application instance to use the test database
    # This ensures the running app uses our isolated test DB
    Sinatra::Application.set :db, SQLite3::Database.new(@test_db_path)
    Sinatra::Application.db.results_as_hash = true
  end

  # Runs after each test method
  def teardown
    # Ensure the application's database connection is closed
    db_instance = Sinatra::Application.settings.db
    if db_instance.is_a?(SQLite3::Database) && !db_instance.closed?
      db_instance.close
    end

    # Remove the test database file
    FileUtils.rm_f(@test_db_path)
  end

  # --- Helper Methods for Tests ---

  # Helper to simulate user registration via the form POST endpoint
  def register(username, password, password2 = nil, email = nil)
    password2 ||= password # Default password2 to password if not provided
    email ||= "#{username}@example.com" # Generate default email if not provided
    post '/api/register', { username: username, email: email, password: password, password2: password2 }
    # Follow redirect automatically if registration is successful
    follow_redirect! if last_response.redirect?
    # Return the final response after potential redirect
    last_response
  end

  # Helper to simulate user login via the form POST endpoint
  def login(username, password)
    post '/api/login', { username: username, password: password }
    # Follow redirect automatically if login is successful
    follow_redirect! if last_response.redirect?
    # Return the final response after potential redirect
    last_response
  end

  # Helper to simulate user logout
  def logout
    get '/api/logout'
    # Follow redirect automatically after logout
    follow_redirect! if last_response.redirect?
    # Return the final response after potential redirect
    last_response
  end

  # --- Test Cases ---

  def test_register_flow
    # 1. Successful Registration
    response = register('tester', 'password123')
    assert_equal 200, response.status # Status should be OK after redirect
    assert_equal '/', last_request.path_info # Should redirect to home page
    # Check for flash message (rendered in body) - brittle assertion
    assert_includes response.body, 'You were successfully registered and are now logged in.'
    # Check for content indicating user is logged in (e.g., logout link) - brittle assertion
    assert_includes response.body, 'href="/api/logout">Log out [tester]</a>' # Assumes this exact format in view

    # 2. Logout
    response = logout
    assert_equal 200, response.status # Status should be OK after redirect
    assert_equal '/', last_request.path_info # Should redirect to home page
    # Check for flash message - brittle assertion
    assert_includes response.body, 'You were logged out'
    # Check for content indicating user is logged out (e.g., login link) - brittle assertion
    assert_includes response.body, 'href="/login">Log in</a>'

    # 3. Attempt Duplicate Username Registration (while logged out)
    response = register('tester', 'password123')
    assert_equal 200, response.status # Should re-render form, not redirect
    # Use refute (compatible) instead of assert_not
    # FIX: Disable rule locally using inline comment
    # rubocop:disable Minitest/RefuteInsteadOfAssertNot
    refute last_response.redirect?, "Duplicate registration should not redirect"
    # rubocop:enable Minitest/RefuteInsteadOfAssertNot
    # Check it's the registration page showing the error
    assert_includes response.body, '<form action="/api/register"'
    assert_includes response.body, 'The username is already taken'

    # 4. Attempt Duplicate Email Registration (while logged out)
    response = register('anotheruser', 'password123', nil, 'tester@example.com') # Use existing email
    assert_equal 200, response.status # Should re-render form
    # Use refute (compatible) instead of assert_not
    # FIX: Disable rule locally using inline comment
    # rubocop:disable Minitest/RefuteInsteadOfAssertNot
    refute last_response.redirect?, "Duplicate email registration should not redirect"
    # rubocop:enable Minitest/RefuteInsteadOfAssertNot
    assert_includes response.body, '<form action="/api/register"'
    assert_includes response.body, 'This email is already registered'
  end

  def test_registration_validation_errors
    # Call logout unconditionally to ensure logged-out state for validation tests below.
    logout

    # Test missing username
    response = register('', 'password123')
    assert_equal 200, response.status # Re-renders form
    assert_includes response.body, 'You have to enter a username'
    assert_includes response.body, '<form action="/api/register"'

    # Test missing password (using blank? logic)
    response = register('testuser', '')
    assert_equal 200, response.status # Re-renders form
    assert_includes response.body, 'You have to enter a password'
    assert_includes response.body, '<form action="/api/register"'

    # Test non-matching passwords
    response = register('testuser', 'pass1', 'pass2')
    assert_equal 200, response.status # Re-renders form
    assert_includes response.body, 'The two passwords do not match'
    assert_includes response.body, '<form action="/api/register"'

    # Test invalid email format
    response = register('testuser', 'password123', nil, 'invalid-email')
    assert_equal 200, response.status # Re-renders form
    assert_includes response.body, 'You have to enter a valid email address'
    assert_includes response.body, '<form action="/api/register"'

    # Test blank email (using blank? logic)
    response = register('testuser', 'password123', nil, '   ')
    assert_equal 200, response.status # Re-renders form
    assert_includes response.body, 'You have to enter a valid email address' # blank? triggers this
    assert_includes response.body, '<form action="/api/register"'
  end

  def test_login_logout_flow
    # 1. Register user first
    register('testlogin', 'password')
    logout # Ensure logged out before testing login

    # 2. Successful Login
    response = login('testlogin', 'password')
    assert_equal 200, response.status # After redirect
    assert_equal '/', last_request.path_info # Redirected to home
    # Check flash message - brittle assertion
    assert_includes response.body, 'You were successfully logged in.'
    # Check for logout link - brittle assertion
    assert_includes response.body, 'href="/api/logout">Log out [testlogin]</a>'

    # 3. Logout
    response = logout
    assert_equal 200, response.status # After redirect
    assert_equal '/', last_request.path_info # Redirected to home
    # Check flash message - brittle assertion
    assert_includes response.body, 'You were logged out'
    # Check for login link - brittle assertion
    assert_includes response.body, 'href="/login">Log in</a>'

    # 4. Login with wrong password
    response = login('testlogin', 'wrongpassword')
    assert_equal 200, response.status # Re-renders login form
    # Use refute (compatible) instead of assert_not
    # FIX: Disable rule locally using inline comment
    # rubocop:disable Minitest/RefuteInsteadOfAssertNot
    refute last_response.redirect?, "Login with wrong password should not redirect"
    # rubocop:enable Minitest/RefuteInsteadOfAssertNot
    # Check it's the login page showing the error
    assert_includes response.body, '<form action="/api/login"'
    assert_includes response.body, 'Invalid username or password'

    # 5. Login with non-existent username
    response = login('nosuchuser', 'password')
    assert_equal 200, response.status # Re-renders login form
    # Use refute (compatible) instead of assert_not
    # FIX: Disable rule locally using inline comment
    # rubocop:disable Minitest/RefuteInsteadOfAssertNot
    refute last_response.redirect?, "Login with non-existent user should not redirect"
    # rubocop:enable Minitest/RefuteInsteadOfAssertNot
    assert_includes response.body, '<form action="/api/login"'
    assert_includes response.body, 'Invalid username or password'
  end

  # Test search page loads correctly (doesn't test results without seed data)
  def test_search_page_loads
    # Test loading the search page with no query
    get '/'
    assert last_response.ok?, "Search page should load without query. Status: #{last_response.status}"
    assert_includes last_response.body, '<title>DynaSearch 🧨</title>' # Check for correct title element

    # Test loading the search page with a query (on empty DB)
    get '/', { q: 'some search term', language: 'en' }
    assert last_response.ok?, "Search page should load with query. Status: #{last_response.status}"
    assert_includes last_response.body, '<title>DynaSearch 🧨</title>'
    # Optional: Check for a "no results" message if your view includes one
    # assert_includes last_response.body, "No results found for 'some search term'"
  end

  # Test API endpoints return JSON (basic checks)
  def test_api_endpoints_content_type
    # Test API search
    get '/api/search', { q: 'test' }
    assert last_response.ok?
    assert_equal 'application/json', last_response.content_type

    # Test API weather (might fail if API key missing or service down, but should return JSON error)
    get '/api/weather'
    # Status might be 200 (cached ok), 503 (service unavailable), or 500 (other error)
    # Check that content type is JSON regardless of status code for API errors
    assert [200, 500, 503].include?(last_response.status) # Allow for OK, server error, or service unavailable
    assert_equal 'application/json', last_response.content_type
  end

end
