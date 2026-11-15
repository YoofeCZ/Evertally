-- A player may show the journey recording ("Kronika") of a public character to everyone on the website. Off until the player turns it on
-- (in the game or on the website), and it only matters while the character itself is public.
ALTER TABLE atlas_profiles ADD COLUMN show_chronicle INTEGER NOT NULL DEFAULT 0;
