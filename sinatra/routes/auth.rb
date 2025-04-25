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
      user = db.get_first_row('SELECT * FROM users WHERE username = ?', username)
    rescue SQLite3::Exception => e
      logger.error "Database error during login for user '#{username}': #{e.message}"
      error = 'An internal error occurred. Please try again.'
    end
  end

  # Proceed with password verification only if no prior errors occurred
  if error.nil?
    # Check if user exists and password is correct
    if user && verify_password(user['password'], password)
      # Check if the user is required to reset their password
      if user['force_password_reset'] == 1
        # If forced password reset, clear the session and redirect to reset page
        session[:user_id] = nil
        flash[:error] = 'Due to a recent security incident, you must reset your password before continuing.'
        redirect '/reset_password'  # Redirect to reset password page
      else
        # Login successful: Set session and redirect to home/dashboard
        session[:user_id] = user['id']
        flash[:notice] = 'You were successfully logged in.'
        redirect '/'  # Redirect to home page (or dashboard) after successful login
      end
    else
      # Login failed: Invalid credentials (user not found or password mismatch)
      error = 'Invalid username or password.'
      logger.warn "Failed login attempt for username: '#{username}'"
    end
  end

  # If any error occurred (validation, DB, credentials), re-render login form
  flash.now[:error] = error  # Use flash.now for rendering within the same request cycle
  erb :login, locals: { error: error }  # Pass error for compatibility if view uses it directly
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
      db.execute('INSERT INTO users (username, email, password) VALUES (?, ?, ?)',
                 [username, email, hashed_password])

      new_user_id = db.last_insert_row_id

      # Log the new user in and redirect.
      session[:user_id] = new_user_id
      flash[:notice] = 'You were successfully registered and are now logged in.'
      redirect '/'
    rescue SQLite3::Exception => e
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

# GET /reset_password - form to enter new password
get '/reset_password' do
  erb :reset_password
end

# POST /reset_password - handle password reset submission
post '/reset_password' do
  new_password = params[:password]
  new_password2 = params[:password2]
  token = params[:token] # optional if you're using email tokens

  if new_password.blank? || new_password2.blank?
    flash[:error] = 'Both password fields are required.'
    redirect '/reset_password'
  elsif new_password != new_password2
    flash[:error] = 'Passwords do not match.'
    redirect '/reset_password'
  else
    user = current_user
    if user
      hashed = hash_password(new_password)
      db.execute("UPDATE users SET password = ?, force_password_reset = 0 WHERE id = ?", [hashed, user['id']])
      flash[:notice] = 'Password successfully reset. You can now log in.'
      settings.logger.info "User #{user['username']} reset their password after breach"
      redirect '/login'
    else
      flash[:error] = 'You must be logged in to reset your password.'
      redirect '/login'
    end
  end
end

require 'securerandom'

post '/api/request_reset_password' do
  email = params[:email]

  user = db.execute("SELECT * FROM users WHERE email = ?", [email]).first

  if user
    reset_token = SecureRandom.hex(32)  # Generate a random token
    expiration = (Time.now + 3600).to_s # Token expiration time (1 hour from now)

    # Store the token and expiration in the database
    db.execute("UPDATE users SET reset_token = ?, reset_token_expiration = ? WHERE id = ?", [reset_token, expiration, user['id']])

    # Send the reset link (you can replace this with actual email logic)
    puts "Send this link to the user: https://your-app.com/reset_password?token=#{reset_token}"
    
    flash[:notice] = "Password reset instructions sent."
  else
    flash[:error] = "Email not found."
  end

  redirect '/login'
end

get '/reset_password' do
  token = params[:token]

  user = db.execute("SELECT * FROM users WHERE reset_token = ?", [token]).first

  if user && Time.now < Time.parse(user['reset_token_expiration'])
    erb :reset_password_form # Render reset password form
  else
    flash[:error] = "Invalid or expired token."
    redirect '/login'
  end
end

post '/reset_password' do
  token = params[:token]
  new_password = params[:password]

  user = db.execute("SELECT * FROM users WHERE reset_token = ?", [token]).first

  if user && Time.now < Time.parse(user['reset_token_expiration'])
    # Update the user's password
    db.execute("UPDATE users SET password = ?, reset_token = NULL, reset_token_expiration = NULL WHERE id = ?", [new_password, user['id']])

    flash[:notice] = "Password successfully reset."
    redirect '/login'
  else
    flash[:error] = "Invalid or expired token."
    redirect '/login'
  end
end