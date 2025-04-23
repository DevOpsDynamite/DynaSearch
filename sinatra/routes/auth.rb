# frozen_string_literal: true

# Defines routes related to user authentication (login, logout, register actions)
# These routes handle form submissions and result in redirects or re-rendering forms.

# POST /api/login - Handle login form submission
post '/api/login' do
  username = params[:username]&.strip
  password = params[:password] # Don't strip password

  user = nil
  error = nil

  # Use blank? (requires ActiveSupport) for presence validation
  if username.blank? || password.blank?
    error = 'Username and password are required.'
  else
    # Fetch user from database only if input is present
    begin
      # Use exec_params with $1 placeholder, .first to get the single row hash
      user_result = db.exec_params('SELECT * FROM users WHERE username = $1', [username])
      user = user_result.first # Get the first (and only) row if it exists
    rescue PG::Error => e # Catch PostgreSQL errors
      logger.error "Database error during login for user '#{username}': #{e.message}"
      error = 'An internal error occurred. Please try again.'
    end
  end

  # Proceed with password verification only if no prior errors occurred
  if error.nil?
    # Check if user exists and password is correct
    if user && verify_password(user['password'], password) # user is now a hash
      # Login successful: Set session and redirect
      session[:user_id] = user['id'] # Access 'id' key from the hash
      flash[:notice] = 'You were successfully logged in.'
      redirect '/' # Redirect to home page after successful login
    else
      # Login failed: Invalid credentials (user not found or password mismatch)
      error = 'Invalid username or password.'
      logger.warn "Failed login attempt for username: '#{username}'"
    end
  end

  # If any error occurred (validation, DB, credentials), re-render login form
  flash.now[:error] = error # Use flash.now for rendering within the same request cycle
  erb :login, locals: { error: error } # Pass error for compatibility if view uses it directly
end

# GET /api/logout - Handle logout action
get '/api/logout' do
  # Clear the session, set flash message, and redirect
  session.clear
  flash[:notice] = 'You were logged out.'
  redirect '/'
end

# POST /api/register - Handle registration form submission
post '/api/register' do
  # Redirect if already logged in
  redirect '/' if current_user

  # Prepare parameters
  username = params[:username]&.strip
  email = params[:email]&.strip
  password = params[:password] # Keep original password for comparison/hashing
  password2 = params[:password2]

  error = nil

  # --- Input Validation using blank? (requires ActiveSupport) ---
  if username.blank?
    error = 'You have to enter a username'
  # NOTE: blank? doesn't check format, so keep email format check
  elsif email.blank? || !email.include?('@')
    error = 'You have to enter a valid email address'
  # Use blank? for password presence check. Consider password.strip.blank? if whitespace-only passwords are not allowed.
  elsif password.blank?
    error = 'You have to enter a password'
  elsif password != password2
    error = 'The two passwords do not match'
  else
    # --- Check for existing user/email (only if basic validation passes) ---
    begin
      # Use exec_params with $1 placeholder, .ntuples checks if any rows were returned
      existing_user_result = db.exec_params('SELECT 1 FROM users WHERE username = $1 LIMIT 1', [username])
      existing_email_result = db.exec_params('SELECT 1 FROM users WHERE email = $1 LIMIT 1', [email])

      if existing_user_result.ntuples.positive?
        error = 'The username is already taken'
      elsif existing_email_result.ntuples.positive?
        error = 'This email is already registered'
      end
    rescue PG::Error => e # Catch PostgreSQL errors
      logger.error "Database error during registration check for '#{username}'/'#{email}': #{e.message}"
      error = 'An internal error occurred during registration check. Please try again.'
    end
  end

  # --- Process Registration or Show Errors ---
  if error
    # Re-render form with error and submitted values.
    flash.now[:error] = error
    erb :register, locals: {
      error: error,
      username: params[:username], # Pass back original params for form repopulation
      email: params[:email]
    }
  else
    # --- Create User (only if no errors) ---
    begin
      hashed_password = hash_password(password) # Hash the valid password
      # Use exec_params with $1, $2, $3 placeholders
      # Use RETURNING id to get the new user's ID
      insert_result = db.exec_params('INSERT INTO users (username, email, password) VALUES ($1, $2, $3) RETURNING id',
                                     [username, email, hashed_password])

      new_user_id = insert_result.first['id'] # Get the id from the returned row

      # Log the new user in and redirect.
      session[:user_id] = new_user_id
      flash[:notice] = 'You were successfully registered and are now logged in.'
      redirect '/'
    rescue PG::Error => e # Catch PostgreSQL errors
      # Handle potential DB error during insertion
      logger.error "Database error during user insertion for '#{username}': #{e.message}"
      flash.now[:error] = 'An internal error occurred while creating your account. Please try again.'
      erb :register, locals: {
        error: flash.now[:error],
        username: params[:username],
        email: params[:email]
      }
    end
  end
end