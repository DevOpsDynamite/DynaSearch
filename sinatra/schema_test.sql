DROP TABLE IF EXISTS users;

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL
);

-- Create a default user, The password is 'password' (MD5 hashed)
INSERT INTO users (username, email, password) 
    VALUES ('test', 'keamonk1@stud.kea.dk', '123');


CREATE TABLE IF NOT EXISTS pages (
    title TEXT PRIMARY KEY UNIQUE,
    url TEXT NOT NULL UNIQUE,
    language TEXT NOT NULL CHECK(language IN ('en', 'da')) DEFAULT 'en', -- How you define ENUM type in SQLite
    last_updated TIMESTAMP,
    content TEXT NOT NULL
);
INSERT INTO pages (title, url, language, content)
VALUES ('JavaScript Page','www','en','This page contains information about JavaScript.');
