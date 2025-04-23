-- Drop old table if it exists
DROP TABLE IF EXISTS users;

-- Create users with a SERIAL primary key
CREATE TABLE users (
  id      SERIAL        PRIMARY KEY,
  username TEXT         NOT NULL UNIQUE,
  email    TEXT         NOT NULL UNIQUE,
  password TEXT         NOT NULL
);

-- Create an ENUM for language codes
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'language_enum') THEN
    CREATE TYPE language_enum AS ENUM ('en', 'da');
  END IF;
END$$;

DROP TABLE IF EXISTS pages;

CREATE TABLE pages (
  title         TEXT           PRIMARY KEY,
  url           TEXT           NOT NULL UNIQUE,
  language      language_enum  NOT NULL DEFAULT 'en',
  last_updated  TIMESTAMP,
  content       TEXT           NOT NULL
);
