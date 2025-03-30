# Continuous Delivery Setup for a Sinatra App with Docker and GitHub Actions

This guide demonstrates how to containerize a Ruby Sinatra project and set up continuous delivery using Docker and GitHub Actions. We will create separate Docker configurations for development (with hot-reloading) and production, manage environment variables securely with Dotenv, and configure a CI workflow to build and push the Docker image to GitHub Container Registry (GHCR) on each push to the main branch. We’ll also update the Makefile with convenient commands. The goal is a smooth development experience and an automated delivery pipeline following best practices.

## Dockerfile for Development (Hot-Reloading with Rerun)

For the development environment, we'll use a Dockerfile that sets up the Sinatra app with all dependencies and enables hot-reloading. Sinatra’s recommended approach for reloading code in development is to run the app via an external file-watcher tool like `rerun`, which restarts the app when files change.

### `Dockerfile.dev` (development Dockerfile)

```Dockerfile
# Use an official lightweight Ruby image for development
FROM ruby:3.2-slim

# Install build tools and SQLite library (needed to install the sqlite3 gem)
RUN apt-get update -qq && apt-get install -y build-essential libsqlite3-dev

# Set working directory
WORKDIR /app

# Install app dependencies (Gemfile should list all gems)
COPY Gemfile Gemfile.lock ./
RUN gem install bundler && bundle install

# Install 'rerun' for auto-reloading in development
RUN gem install rerun

# Copy the application code
COPY . .

# Expose Sinatra's default port
EXPOSE 4567

# Set environment to development by default
ENV RACK_ENV=development

# Command: use rerun to restart the app on code changes
CMD ["rerun", "--", "ruby", "app.rb", "-o", "0.0.0.0"]
```

### Key points:
- We start from a Ruby base image and install any needed system libraries (like `libsqlite3-dev` for the `sqlite3` gem).
- We install `rerun` so the container can automatically reload on file changes.
- `RACK_ENV=development` ensures Sinatra runs in development mode.
- Changes to code are reflected without rebuilding the container each time.

## Dockerfile for Production (Optimized for Deployment)

We create a separate Dockerfile focused on a slim, secure image. This uses multi-stage builds to reduce image size.

### `Dockerfile` (production Dockerfile)

```Dockerfile
# Stage 1: Builder – install gems and assets
FROM ruby:3.2-slim AS builder

# Install build tools and dependencies for building gems
RUN apt-get update -qq && apt-get install -y build-essential libsqlite3-dev

WORKDIR /app

# Install app gems (without dev and test groups for a leaner production image)
COPY Gemfile Gemfile.lock ./
RUN gem install bundler && bundle install --without development test

# Copy application source code
COPY . .

# Stage 2: Final image – only includes runtime necessities
FROM ruby:3.2-slim

# Install runtime dependencies (no build tools)
RUN apt-get update -qq && apt-get install -y libsqlite3-0 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy app code and gem bundles from builder stage
COPY --from=builder /app . 
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Set environment to production
ENV RACK_ENV=production

# Expose port
EXPOSE 4567

# Use an appropriate command to run the Sinatra app in production
CMD ["bundle", "exec", "ruby", "app.rb", "-o", "0.0.0.0", "-p", "4567"]
```

### Key optimizations and practices:
- Slim base image + runtime-only packages.
- Multi-stage builds exclude dev tools from the final image.
- `bundle exec` with array form for proper signal handling.

## Docker Compose for Development vs Production

### `docker-compose.dev.yml` (Local Development)

```yaml
version: '3'
services:
  app:
    build:
      context: . 
      dockerfile: Dockerfile.dev
    ports:
      - "4567:4567"
    volumes:
      - .:/app
    env_file:
      - .env.development
    environment:
      - RACK_ENV=development
```

### `docker-compose.prod.yml` (Production/Deployment)

```yaml
version: '3'
services:
  app:
    image: ghcr.io/<GHCR_USERNAME>/sinatra-app:latest
    env_file:
      - .env
    ports:
      - "4567:4567"
    volumes:
      - sinatra_data:/app/data
    restart: unless-stopped

volumes:
  sinatra_data:
```

## Managing Environment Variables Securely with Dotenv

### Setup

Add to your `Gemfile`:

```ruby
gem 'dotenv'
```

Then run:

```bash
bundle install
```

### In `app.rb`:

```ruby
require 'dotenv/load'
require 'sinatra'

configure do
  enable :sessions
  set :session_secret, ENV['SESSION_SECRET']
end
```

### Example `.env.development`

```bash
DATABASE_PATH=DB_path
SESSION_SECRET=dev-secret-key
WEATHERBIT_API_KEY=your_dev_api_key
```

> 🔒 Do **not** commit `.env` files. Add them to `.gitignore`.

## GitHub Actions Workflow for Continuous Delivery

### `.github/workflows/continuous_delivery.yml`

```yaml
name: Continuous Delivery

on:
  push:
    branches: [ "main" ]

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Log in to GHCR
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ secrets.GHCR_USERNAME }}
          password: ${{ secrets.GHCR_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v3
        with:
          context: .
          file: Dockerfile
          push: true
          tags: |
            ghcr.io/${{ secrets.GHCR_USERNAME }}/sinatra-app:latest
            ghcr.io/${{ secrets.GHCR_USERNAME }}/sinatra-app:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  
```

## Makefile Updates for Docker Commands

```Makefile
# Bring up the development environment (build image and start containers)
docker-dev-up:
	docker compose -f docker-compose.dev.yml up --build

# Build the production image (similar to what CI does), tagging it for local use
docker-prod-build:
	docker build -f Dockerfile -t sinatra-app:local .

# Run tests inside the development container (if you have a test suite)
docker-test:
	docker compose -f docker-compose.dev.yml run --rm app bundle exec rspec



## Best Practices and Considerations

- **Environment variables & secrets**: Keep `.env` files out of version control. Use GitHub Secrets in CI.
- **Caching**: Use Docker layer caching in Dockerfiles and GitHub Actions to speed up builds.
- **Image tagging**: Tag with `latest` for deployments and commit SHAs for traceability.
- **Security**: Use non-root user in production Dockerfile (optional hardening).
- **Logging & monitoring**: Capture logs and add health checks to containers.
- **Testing**: Run tests in CI before building and deploying images.

By following this setup, you ensure a clear separation between development and production, use secure config management, and implement an automated delivery pipeline from source to deployment.
