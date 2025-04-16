# benchmark_search.rb
require 'sqlite3'
require 'benchmark'
require 'dotenv/load' # If needed for DB path, though likely not if using default

# --- Configuration ---
# Ensure this path points correctly to your database
DB_PATH = if ENV['RACK_ENV'] == 'test'
            File.join(__dir__, 'test', 'test_whoknows.db')
          elsif ENV['DATABASE_PATH']
            ENV['DATABASE_PATH']
          else
            File.join(__dir__, 'whoknows.db') # Assuming whoknows.db is in the same dir
          end

unless File.exist?(DB_PATH)
  puts "Database not found at #{DB_PATH}"
  exit(1)
end

# Terms to test
search_terms = ['technology', 'database', 'performance', 'Copenhagen', 'spring java', 'database performance']
language = 'en'

# --- Database Connection ---
db = SQLite3::Database.new(DB_PATH)
db.results_as_hash = true # Match app.rb setting if needed, though not strictly required for benchmark timing

puts "Benchmarking search queries on database: #{DB_PATH}"
puts "Using language: #{language}"
puts '--------------------------------------------------'

# --- Run Benchmarks ---
search_terms.each do |q|
  puts "Term: '#{q}'"

  like_time = Benchmark.measure do
    # Important: Use the exact LIKE query structure we had before
    db.execute('SELECT title FROM pages WHERE language = ? AND content LIKE ?', [language, "%#{q}%"])
  end
  puts "  LIKE query took: #{format('%.4f', like_time.real)} seconds"

  fts5_time = Benchmark.measure do
    # Important: Use the exact FTS5 query structure you have now
    db.execute(
      'SELECT p.title FROM pages p JOIN pages_fts f ON p.rowid = f.rowid WHERE f.pages_fts MATCH ? AND p.language = ? ORDER BY f.rank DESC',
      [q, language]
    )
    # NOTE: We select only 'title' here just to reduce data transfer overhead during benchmark,
    # the core search work (LIKE vs MATCH) is what we're measuring. You could use p.* too.
  end
  puts "  FTS5 query took: #{format('%.4f', fts5_time.real)} seconds"
  puts '' # Add a newline for readability
end

puts '--------------------------------------------------'
puts 'Benchmark complete.'

db.close # Close the database connection
