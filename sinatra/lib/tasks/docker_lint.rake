namespace :lint do
  desc 'Lint a specific Dockerfile using hadolint'
  task :dockerfile, [:dockerfile] do |_t, args|
    # Default to 'Dockerfile.dev' if no argument is passed
    dockerfile = args[:dockerfile] || 'Dockerfile.dev'

    unless File.exist?(dockerfile)
      puts "#{dockerfile} not found in the project root."
      exit 1
    end

    # Run Hadolint using the local executable
    puts "Running Hadolint on #{dockerfile}..."
    if system("./hadolint.exe #{dockerfile}")
      puts 'No issues found. Good job!'
    else
      puts 'Hadolint found issues!'
      exit 1
    end
  end
end
