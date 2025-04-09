.PHONY: test

run:
	rerun 'ruby app.rb'

lint:
	bundle exec rubocop

lint-fix:
	bundle exec rubocop -a

test:
	ruby -Itest test/app_test.rb

# Bring up the development environment (build image and start containers)
docker-dev-up:
	docker compose -f docker-compose.dev.yml up --build

# Build the production image (similar to what CI does), tagging it for local use
docker-prod-build:
	sudo docker build -f Dockerfile.prod -t sinatra-app:local .

# Run the production image:
docker-prod-up:
	# Ensure the specific image tag mentioned in the compose file is pulled
	docker compose -f docker-compose.prod.yml up -d --pull always --remove-orphans
	# Bring services up (or update them), run in background, and remove any orphaned containers
	docker compose -f docker-compose.prod.yml up -d --remove-orphans

# Run tests inside the development container (if you have a test suite)
docker-test:
	docker compose -f docker-compose.dev.yml run --rm app bundle exec rspec

