-- When the player last chose the leaderboard visibility of a character, on the website or in the game.
-- A choice from the game applies only when it is newer, so neither side silently overrides a later choice of the other.
ALTER TABLE atlas_profiles ADD COLUMN visibility_at INTEGER;
