-- The last place a character was seen. The app sends it on an event (zone change, /reload, login, now and then, or when
-- the website asks), not every few seconds: a free database only allows 100k written rows a day.
CREATE TABLE IF NOT EXISTS et_last_positions (
  profile_id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  observed_at INTEGER NOT NULL,
  map_id INTEGER NOT NULL,
  x REAL NOT NULL,
  y REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS last_positions_user ON et_last_positions(user_id);
-- "Where are you?" asked on the website: the app picks it up with its next check and answers with one position.
CREATE TABLE IF NOT EXISTS et_locate_requests (
  user_id TEXT PRIMARY KEY NOT NULL,
  requested_at INTEGER NOT NULL
);
