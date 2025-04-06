# Untitled

`# Search Implementation: From LIKE to SQLite FTS5`

## Written by ChatGPT based on my guidance of what I have done. Have read it thoroughly and changed wherever it hallucinated, or misinterpreted my prompt. 

`**Date:** April 6, 2025

## 1. Introduction & Goal

This document outlines the implementation of the SQLite FTS5 extension to replace the previous `LIKE`-based search functionality in the application.

The primary goals, based on the user story, were to:
* Improve search performance, especially as the data grows.
* Enable relevance-based ranking of search results.
* Evaluate the pros and cons of both approaches.

## 2. Previous Implementation (`LIKE`)

### Description

The previous search implementation used the standard SQL `LIKE` operator with leading and trailing wildcards. The query structure was:

```sql
SELECT * FROM pages WHERE language = ? AND content LIKE ?
-- Example Parameter Binding: ['en', '%searchterm%']`

### Limitations

- **Performance:** Using `LIKE '%term%'` prevents the database from effectively utilizing standard indexes on the `content` column, often leading to full table scans. This becomes increasingly slow as the number of pages grows.
- **Relevance:** `LIKE` provides no concept of search relevance. Results are returned in an arbitrary order (e.g., database insertion order) unless explicitly sorted by other columns. A page where the term appears once is treated the same as a page where it's central to the content.
- **Functionality:** Basic substring matching only. No understanding of word variations (stemming), phrases, or proximity.

## 3. New Implementation (SQLite FTS5)

### Setup

1. **Virtual Table:** An FTS5 virtual table named `pages_fts` was created to index the `content` column from the `pages` table. It also stores the `language` (unindexed) and links back to the original table via `rowid`.
SQL
    - `- Simplified definition from fts5.sql
    CREATE VIRTUAL TABLE pages_fts USING fts5( content, language UNINDEXED, content='pages', content_rowid='rowid'
    );`
2. **Synchronization Triggers:** Database triggers (`pages_ai`, `pages_ad`, `pages_au`) were created on the `pages` table. These triggers automatically update the `pages_fts` table whenever rows are inserted, deleted, or updated in `pages`, ensuring the search index stays synchronized.
3. **Initial Population:** Existing data from `pages` was loaded into `pages_fts` using an `INSERT INTO ... SELECT ...` command.

*(Refer to `fts5.sql` for the full table and trigger definitions).*

### Query Changes

The application code (`app.rb`) was updated to use the `MATCH` operator against the `pages_fts` table and `ORDER BY rank` for relevance. The new query structure is:

SQL

`SELECT p.*
FROM pages p
JOIN pages_fts f ON p.rowid = f.rowid
WHERE f.pages_fts MATCH ? AND p.language = ?
ORDER BY f.rank DESC;
-- Example Parameter Binding: ['en', 'searchterm']`

- `f.pages_fts MATCH ?`: Performs the efficient full-text search using the FTS index.
- `ORDER BY f.rank DESC`: Sorts the results using FTS5's built-in relevance ranking (higher rank is more relevant).

## 4. Evaluation

### 4.1. Performance Benchmarking

Benchmarking was performed using the `benchmark_search.rb` script on April 6, 2025, against the `whoknows.db` database (path: `/Users/aleksandergregersen/Desktop/Datamatiker/DynaSearch/sinatra/whoknows.db`). The script compared the execution time of the old `LIKE` query against the new `FTS5 MATCH` query for several terms in English (`language = 'en'`).

**Results:**

| Search Term | LIKE Time (s) | FTS5 Time (s) | Speedup Factor |
| --- | --- | --- | --- |
| 'technology' | 0.0055 | 0.0010 | 5.5x |
| 'database' | 0.0007 | 0.0002 | 3.5x |
| 'performance' | 0.0007 | 0.0001 | 7.0x |
| 'Copenhagen' | 0.0012 | 0.0001 | 12.0x |
| 'a_less_common_word' | 0.0019 | 0.0002 | 9.5x |
| 'multi word phrase' | 0.0009 | 0.0001 | 9.0x |

Eksportér til Sheets

**Analysis:**
The results clearly demonstrate a significant performance improvement using FTS5. Speedups ranged from **3.5x to 12.0x** across the tested terms. While the absolute times are currently small (milliseconds), this efficiency gain is crucial as the database size increases, ensuring a responsive search experience. FTS5 consistently outperformed `LIKE '%term%'`.

### 4.2. Accuracy & Relevance

This was evaluated manually by comparing the search results returned by both the old `LIKE` method and the new FTS5 method for the same set of search terms.

**Observations:**

- **Result Ordering:** FTS5 results were consistently ordered by apparent relevance. Pages where the search term appeared multiple times, in the title, or seemed more central to the topic were ranked higher. In contrast, LIKE results appeared to be ordered by the internal database `rowid`, which is not meaningful for search relevance.
- **Result Quality:** FTS5 generally provided more pertinent results at the top of the list. For most queries, the first few FTS5 results felt like better answers to the search query compared to the first few LIKE results, which often included pages where the term was only mentioned in passing.
- **Completeness:** For the terms tested, both methods generally found the same core set of relevant documents. FTS5 did not appear to miss any significant pages found by LIKE. In some cases, FTS5 found slightly more matches due to better handling of word boundaries near punctuation compared to the simple `%term%` LIKE pattern.

**Examples:**

- Searching for '**database performance**': FTS5 returned several more pages, where all of them were related to database performance, both in general and information about different languages, where the wiki page contained information about database performances for that specific language, like objective-C, Smalltalk, Perl and PHP. LIKE returned only one named Database, which was also returned by FTS5.

## 5. Conclusion

The implementation of SQLite FTS5 successfully meets the goals outlined in the user story.

- **Performance:** Search query execution time has been significantly reduced, as demonstrated by benchmarks (3.5x - 12.0x speedup on tested terms).
- **Relevance:** Search results are now ranked by relevance using FTS5's built-in capabilities (`ORDER BY rank`), providing a much more useful and intuitive ordering for the user.

This change provides a foundation for a more robust and scalable search experience within the application. Future considerations might include exploring more advanced FTS5 query syntax or tokenizers if needed.

## 6. Appendix / Links (Optional)

- `fts5.sql`: SQL script for FTS5 table and trigger setup.
- `benchmark_search.rb`: Script used for performance benchmarking.
- SQLite FTS5 Documentation: <https://sqlite.org/fts5.html>