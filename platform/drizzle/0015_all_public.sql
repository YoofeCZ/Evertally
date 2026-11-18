-- Since 2026-11-18 every character is public with everything shown (the leaderboards, the chronicle, the stats and the
-- armory, like raider.io); the bags stay behind the player's own permission in the game (armory.view). Earlier choices are
-- replaced. Every live consent and paired device carries every kind of data (lib/publish.ts ALL_PUBLIC).
UPDATE atlas_profiles SET "public"=1, show_item_level=1, show_guild=1, show_gear=1, show_chronicle=1;
UPDATE atlas_grants SET scopes='["world_facts","own_runs","own_character","own_professions","own_track","guild_share"]' WHERE revoked_at IS NULL;
UPDATE et_devices SET scopes='["world_facts","own_runs","own_character","own_professions","own_track","guild_share"]' WHERE revoked_at IS NULL;
