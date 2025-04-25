require 'sqlite3'

# Open the database
db = SQLite3::Database.new('whoknows.db')

# List of usernames affected by the breach
usernames = [] # Add usernames affected by breach

usernames.each do |username|
  db.execute("UPDATE users SET force_password_reset = 1 WHERE username = ?", [username])
end

puts "Marked users for forced password reset."