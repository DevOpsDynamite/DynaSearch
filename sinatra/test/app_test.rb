    ENV['RACK_ENV'] = 'test'

    require 'minitest/autorun'
    require 'rack/test'
    require 'fileutils'
    require_relative '../app'

    class WhoKnowsTest < Minitest::Test
        include Rack::Test::Methods
    
        def app
        Sinatra::Application
        end

        def setup
            # Create a temporary test database file and initialize schema
            @test_db_path = File.expand_path('test_whoknows.db', File.dirname(__FILE__))
            FileUtils.rm_f(@test_db_path)
            FileUtils.cp(File.expand_path('whoknows.db', File.dirname(__FILE__)), @test_db_path) if File.exist?(File.expand_path('whoknows.db', File.dirname(__FILE__)))
            # Optionally, run your schema migrations here if you have a schema file.
        end

        def teardown
            # Clean up the test database file
            FileUtils.rm_f(@test_db_path)
        end
        end