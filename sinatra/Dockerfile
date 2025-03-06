FROM ruby:3.3.0-alpine

# Install necessary dependencies
RUN apk update && apk add --no-cache sqlite sqlite-dev build-base

# Set the working directory
WORKDIR /app

# Copy Gemfiles and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install