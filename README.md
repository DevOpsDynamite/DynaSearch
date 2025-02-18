# DevOpsDynamite

A simple Ruby project using Sinatra refining legacy code in Python3, creating a simple search engine.

## Prerequisites

Make sure you have **Ruby** and **Bundler** installed.

## Installation & Setup

### 1. Check your Ruby version
Run:
```sh
ruby -v
```
If the version is below **2.7**, update Ruby.

### 2. Update Ruby (if necessary)
Install Ruby using **Homebrew**:
```sh
brew install ruby
```
Ensure your system uses the newest version:
```sh
echo 'export PATH="/opt/homebrew/opt/ruby/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### 3. Install dependencies
Run:
```sh
bundle install
```
If `bundle install` doesn’t work due to Ruby version issues, ensure you've updated Ruby as shown above.

### 4. Install Puma & Rack (if needed)
If you run into issues, install **Puma** and **Rack** manually:
```sh
gem install rackup puma
```

### 5. Run the application
Start the Sinatra app with:
```sh
ruby app.rb
```

## Notes
- If you encounter missing dependencies, re-run `bundle install`.
- If running the app fails with **rackup/puma errors**, install them using `gem install rackup puma`.

---

This ensures that everything is installed and set up correctly for running the project.
