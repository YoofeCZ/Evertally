CREATE TABLE IF NOT EXISTS et_live_positions (
  profile_id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  grant_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  observed_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  map_id INTEGER NOT NULL,
  x REAL NOT NULL,
  y REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS live_positions_user ON et_live_positions(user_id);
CREATE INDEX IF NOT EXISTS live_positions_expiry ON et_live_positions(expires_at);
