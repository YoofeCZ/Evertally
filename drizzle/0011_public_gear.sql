-- A player may show the gear, stats and talents of a public character on its page (Raider.IO style).
-- Only the latest armory snapshot of the character itself, never its bags; off until the player turns it on,
-- and it only matters while the character is public and the grant that carried the snapshot is live.
ALTER TABLE atlas_profiles ADD COLUMN show_gear INTEGER NOT NULL DEFAULT 0;
