# frozen_string_literal: true

# This file is used by Rack-based servers to start the application.

# Set the working directory to the directory where this config.ru file is located.
# This ensures that relative paths work correctly from app.rb.
$LOAD_PATH.unshift(File.dirname(__FILE__))

# Load the main application file
require_relative 'app'

# Run the Sinatra application
run Sinatra::Application
