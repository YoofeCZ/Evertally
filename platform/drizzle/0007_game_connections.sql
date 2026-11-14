CREATE TABLE IF NOT EXISTS et_game_connections (
  source_profile_id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  grant_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  observed_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  roster_key INTEGER NOT NULL,
  product TEXT NOT NULL,
  region TEXT NOT NULL,
  self_key INTEGER NOT NULL,
  entries TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS game_connections_user ON et_game_connections(user_id);
CREATE INDEX IF NOT EXISTS game_connections_expiry ON et_game_connections(expires_at);
CREATE INDEX IF NOT EXISTS game_connections_identity ON et_game_connections(product,region,self_key);
