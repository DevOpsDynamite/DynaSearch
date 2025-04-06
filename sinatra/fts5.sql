-- Adds FTS5 virtual table and synchronization triggers for the 'pages' table.
-- Includes DROP statements to make the script idempotent (re-runnable).

-- Drop existing FTS table and triggers if they exist
DROP TRIGGER IF EXISTS pages_ai;
DROP TRIGGER IF EXISTS pages_ad;
DROP TRIGGER IF EXISTS pages_au;
DROP TABLE IF EXISTS pages_fts;

-- Create the FTS5 virtual table, indexing the 'content' column
-- 'pages_fts' is the name of our new virtual table
-- 'content' refers to the column in the 'pages' table we want to index
-- 'content_rowid' stores the rowid of the original row in the 'pages' table
-- 'tokenize' specifies how to break text into words (unicode61 is generally good)
-- 'language' is added as an UNINDEXED column; we'll filter it later but keep it for potential direct queries
CREATE VIRTUAL TABLE pages_fts USING fts5(
    content,                      -- Column to be indexed by FTS5
    language UNINDEXED,           -- Store language, but don't FTS-index it
    content='pages',              -- Link to the 'pages' table (optional but good practice)
    content_rowid='rowid'         -- Link using the rowid of the 'pages' table
    -- Use the default tokenizer (unicode61) or specify: tokenize = 'unicode61'
    -- Or use 'porter' for English stemming: tokenize = 'porter'
);

-- Create Triggers for Synchronization --

-- Trigger for INSERTs on the 'pages' table
-- When a new row is inserted into 'pages', insert the corresponding
-- content and language into 'pages_fts', linking via rowid.
CREATE TRIGGER pages_ai AFTER INSERT ON pages BEGIN
    INSERT INTO pages_fts (rowid, content, language)
    VALUES (new.rowid, new.content, new.language);
END;

-- Trigger for DELETEs on the 'pages' table
-- When a row is deleted from 'pages', delete the corresponding row
-- from 'pages_fts' using the rowid.
CREATE TRIGGER pages_ad AFTER DELETE ON pages BEGIN
    DELETE FROM pages_fts WHERE rowid = old.rowid;
END;

-- Trigger for UPDATEs on the 'pages' table
-- When a row in 'pages' is updated, update the corresponding row
-- in 'pages_fts'.
CREATE TRIGGER pages_au AFTER UPDATE ON pages BEGIN
    UPDATE pages_fts SET
        content = new.content,
        language = new.language
    WHERE rowid = old.rowid;
END;

-- Reminder: After running this script against your database using:
-- sqlite3 whoknows.db < fts5.sql
--
-- You MUST run the following command once to populate the FTS table
-- with your existing data:
-- sqlite3 whoknows.db "INSERT INTO pages_fts (rowid, content, language) SELECT rowid, content, language FROM pages;"