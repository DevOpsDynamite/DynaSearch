.PHONY: test

run:
	rerun 'ruby app.rb'

lint:
	bundle exec rubocop

lint-fix:
	bundle exec rubocop -a

test:
	ruby -Itest test/app_test.rb