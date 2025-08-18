-- 001_create_schema.sql
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS manufacturers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS shishas (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  flavor TEXT,
  manufacturer_id INTEGER REFERENCES manufacturers(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS ratings (
  id SERIAL PRIMARY KEY,
  shisha_id INTEGER REFERENCES shishas(id) ON DELETE CASCADE,
  "user" TEXT,
  score INTEGER
);

CREATE TABLE IF NOT EXISTS comments (
  id SERIAL PRIMARY KEY,
  shisha_id INTEGER REFERENCES shishas(id) ON DELETE CASCADE,
  "user" TEXT,
  message TEXT
);