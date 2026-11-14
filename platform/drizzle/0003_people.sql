CREATE TABLE `et_guilds` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`realm` text NOT NULL,
	`owner_user_id` text,
	`owner_name` text,
	`roster` text NOT NULL,
	`roster_at` integer,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `et_guild_members` (
	`guild_id` text NOT NULL,
	`profile_id` text NOT NULL,
	`user_id` text NOT NULL,
	`name` text NOT NULL,
	`rank_index` integer,
	`status` text NOT NULL,
	`share` text NOT NULL,
	`seen_at` integer NOT NULL,
	PRIMARY KEY(`guild_id`, `profile_id`)
);
--> statement-breakpoint
CREATE INDEX `guild_members_user` ON `et_guild_members` (`user_id`);--> statement-breakpoint
CREATE INDEX `guild_members_profile` ON `et_guild_members` (`profile_id`);--> statement-breakpoint
CREATE INDEX `observations_track` ON `atlas_observations` (`user_id`,`kind`,`observed_at`);
