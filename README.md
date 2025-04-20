# DevOpsDynamite / DynaSearch 🧨

A simple Ruby project using Sinatra refining legacy code, creating a simple search engine with weather features. This version has been refactored for better structure and maintainability.

## Prerequisites

Make sure you have the following installed:

- **Ruby** (Check version, see below)
- **Bundler** (Ruby gem for managing dependencies)

## Installation & Setup

### 1. Check Ruby Version

Ensure you have a compatible Ruby version installed, should be 3.4.2 or newer.

Bash

`ruby -v`

If you need to manage Ruby versions, consider using tools like `rbenv`, `rvm`, or `asdf`.

### 2. Clone the Repository

Bash

`git clone https://github.com/DevOpsDynamite/DynaSearch
cd sinatra`

### 3. Environment Variables

This application uses environment variables for configuration. Create a `.env` file in the  sinatra directory.
Now, edit the `.env` file and fill in the required values:


- `SESSION_SECRET`: A long, random string for securing user sessions. Generate one using `ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'`.
- `WEATHERBIT_API_KEY`: Your API key from Weatherbit.io for the weather forecast feature.


### 4. Install Dependencies

Install all required gems specified in the `Gemfile` using Bundler. This includes Sinatra, Puma (web server), Rack, database drivers, etc.

Bash

`bundle install`

This command installs gems locally for the project, ensuring consistent dependencies.

### 5. Database Setup

Ensure your database file exists and the schema is loaded. The application expects `schema.sql` and `fts5.sql` to define the database structure. If starting fresh, you  need to create the database and load the schema manually using the SQLite CLI:

Bash

`# Example: Create DB and load schema (adjust path if needed)
sqlite3 sinatra/development.db < sinatra/schema.sql
sqlite3 sinatra/development.db < sinatra/fts5.sql`

*(Note: The test setup (`setup` method in `app_test.rb`) does this automatically for the test database).*

### 6. Run the Application (Development)

Start the Sinatra application using `rackup`. This command uses the `config.ru` file to launch the app with the Puma web server (usually the default with `rackup`).

Bash

`# Runs on http://localhost:4568 by default (or port set in app.rb)
bundle exec rackup -p 4568`

- `bundle exec`: Ensures you use the gems installed via Bundler.
- `rackup`: The command to start a Rack-based application using `config.ru`.
- `p 4568`: Specifies the port number (matching the one set in `app.rb`).

You should now be able to access the application at `http://localhost:4568`.

You can also run the application as a Docker container by running
`make docker-dev-up`as specified in the Makefile

## Development

### Running Tests

Execute the test suite using Minitest:

Bash

`bundle exec ruby -Itest test/app_test.rb`


### Running End-to-End Tests (Playwright)

We’ve already configured Playwright in `sinatra/tests`. To run the full E2E suite:

1. **Start the Sinatra app** in one terminal:
   ```bash
   cd sinatra
   bundle exec rackup -p 4568
   ```

2. **Install dependencies & run Playwright** in another terminal:
   ```bash
   cd sinatra/tests
   npm install
   npx playwright install
   npx playwright test
   ```

3. **View the HTML report**:
   ```bash
   npx playwright show-report
   ```
   - For headed mode:  
     `npx playwright test --headed`  
   - To launch the interactive Playwright UI:  
     `npx playwright test --ui`

### End-to-End Test Report

We publish the latest Playwright E2E test report to GitHub Pages.  
View it here: [https://devopsdynamite.github.io/DynaSearch/](https://devopsdynamite.github.io/DynaSearch/)

### Linting / Code Style

Check code style using RuboCop (if configured via `.rubocop.yml`):

Bash

`bundle exec rubocop`

To auto-correct offenses:

Bash

`bundle exec rubocop -A`

## Production Notes

- Ensure the `RACK_ENV` environment variable is set to `production`.
- Run the application using the production command, typically binding to `0.0.0.0`:
Bash
    
    `bundle exec rackup --host 0.0.0.0 --port 4568 --env production`
    
- Use a reverse proxy like Nginx in front of the Puma server for handling external traffic, SSL termination, etc.
- Refer to `Dockerfile.prod` and `docker-compose.prod.yml` for building a production Docker image.
