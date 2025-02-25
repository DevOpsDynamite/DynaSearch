ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'sqlite3'
require 'fileutils'



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
    follow_redirect!  # to follow the redirect after registration
    last_response
  end

    # Helper method for login
    def login(username, password)
        post '/api/login', { username: username, password: password }
        follow_redirect!
        last_response
      end

        # Helper method for logout
  def logout
    get '/api/logout'
    follow_redirect!
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
        end