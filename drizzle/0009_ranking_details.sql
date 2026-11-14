-- Extra details a player may add to a public character in the leaderboard.
-- show_item_level publishes only the average item level computed from the latest armory snapshot (never the gear);
-- show_guild publishes the guild name from the latest guild snapshot. Both stay off until the player turns them on,
-- and both only matter while the character itself is public.
ALTER TABLE atlas_profiles ADD COLUMN show_item_level INTEGER NOT NULL DEFAULT 0;
ALTER TABLE atlas_profiles ADD COLUMN show_guild INTEGER NOT NULL DEFAULT 0;
