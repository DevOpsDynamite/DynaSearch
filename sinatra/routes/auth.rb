# frozen_string_literal: true

# Defines routes related to user authentication (login, logout, register actions)
# These routes handle form submissions and result in redirects or re-rendering forms.

# POST /api/login - Handle login form submission
# NOTE: Path is '/api/login' but behavior is form-based (render/redirect)
post '/api/login' do
  username = params[:username]&.strip
  password = params[:password] # Don't strip password

  user = nil
  error = nil

  # Basic validation
  if username.nil? || username.empty? || password.nil? || password.empty?
    error = 'Username and password are required.'
  else
    # Fetch user from database
    begin
      user = db.get_first_row('SELECT * FROM users WHERE username = ?', username)
    rescue SQLite3::Exception => e
      logger.error "Database error during login for user '#{username}': #{e.message}"
      error = 'An internal error occurred. Please try again.'
    end
  end

  # If no DB error, proceed with password verification
  if error.nil?
    if user && verify_password(user['password'], password)
      # Login successful: Set session and redirect
      session[:user_id] = user['id']
      flash[:notice] = 'You were successfully logged in.'
      redirect '/'
    else
      # Login failed: Invalid credentials
      error = 'Invalid username or password.'
      logger.warn "Failed login attempt for username: '#{username}'"
    end
  end

  # If we reached here, there was an error (validation, DB, or credentials)
  # Re-render the login page with the error message.
  flash.now[:error] = error # Use flash.now for rendering within the same request cycle
  erb :login, locals: { error: error } # Pass error for compatibility if view uses it directly
end

# GET /api/logout - Handle logout action
# NOTE: Path is '/api/logout' but behavior is redirect-based.
get '/api/logout' do
  # Preserve original behavior: Clear session, set flash, redirect.
  session.clear
  flash[:notice] = 'You were logged out.'
  redirect '/'
end

# POST /api/register - Handle registration form submission
# NOTE: Path is '/api/register' but behavior is form-based (render/redirect)
post '/api/register' do
  # Redirect if already logged in
  redirect '/' if current_user

  # Trim input values for consistency
  username = params[:username]&.strip
  email = params[:email]&.strip
  password = params[:password] # Keep original password for comparison/hashing
  password2 = params[:password2]

  error = nil

  # --- Input Validation ---
  if username.nil? || username.empty?
    error = 'You have to enter a username'
  elsif email.nil? || email.empty? || !email.include?('@') # Basic email format check
    error = 'You have to enter a valid email address'
  elsif password.nil? || password.empty? # Check original password for emptiness
    error = 'You have to enter a password'
  elsif password != password2
    error = 'The two passwords do not match'
  else
    # --- Check for existing user/email (Database interaction) ---
    begin
      existing_user = db.get_first_row('SELECT id FROM users WHERE username = ?', username)
      existing_email = db.get_first_row('SELECT id FROM users WHERE email = ?', email)

      if existing_user
        error = 'The username is already taken'
      elsif existing_email
        error = 'This email is already registered'
      end
    rescue SQLite3::Exception => e
      logger.error "Database error during registration check for '#{username}'/'#{email}': #{e.message}"
      error = 'An internal error occurred during registration check. Please try again.'
    end
  end

  # --- Process Registration or Show Errors ---
  if error
    # Preserve original behavior: Re-render form with error and submitted values.
    flash.now[:error] = error
    erb :register, locals: {
      error: error,
      username: params[:username], # Pass back original params for form repopulation
      email: params[:email]
    }
  else
    # --- Create User (Database interaction) ---
    begin
      hashed_password = hash_password(password) # Hash the valid password
      db.execute('INSERT INTO users (username, email, password) VALUES (?, ?, ?)',
                 [username, email, hashed_password])

      new_user_id = db.last_insert_row_id

      # Preserve original behavior: Log the new user in and redirect.
      session[:user_id] = new_user_id
      flash[:notice] = 'You were successfully registered and are now logged in.'
      redirect '/'
    rescue SQLite3::Exception => e
      logger.error "Database error during user insertion for '#{username}': #{e.message}"
      # Render registration form again with a generic error
      flash.now[:error] = 'An internal error occurred while creating your account. Please try again.'
      erb :register, locals: {
        error: flash.now[:error],
        username: params[:username],
        email: params[:email]
      }
    end
  end
end
