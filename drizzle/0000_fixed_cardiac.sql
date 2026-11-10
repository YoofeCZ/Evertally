CREATE TABLE `atlas_grants` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`producer_id` text NOT NULL,
	`consent_epoch` integer NOT NULL,
	`since` integer NOT NULL,
	`scopes` text NOT NULL,
	`created_at` integer NOT NULL,
	`revoked_at` integer
);
--> statement-breakpoint
CREATE INDEX `grants_user` ON `atlas_grants` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `grants_epoch` ON `atlas_grants` (`user_id`,`producer_id`,`consent_epoch`);--> statement-breakpoint
CREATE TABLE `atlas_observations` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`producer_id` text NOT NULL,
	`event_id` text NOT NULL,
	`grant_id` text NOT NULL,
	`kind` text NOT NULL,
	`scope` text NOT NULL,
	`observed_at` integer NOT NULL,
	`profile_id` text,
	`payload` text NOT NULL,
	`game` text NOT NULL,
	`evidence` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `observations_event` ON `atlas_observations` (`user_id`,`producer_id`,`event_id`);--> statement-breakpoint
CREATE INDEX `observations_profile` ON `atlas_observations` (`profile_id`);--> statement-breakpoint
CREATE INDEX `observations_kind` ON `atlas_observations` (`kind`);--> statement-breakpoint
CREATE INDEX `observations_user` ON `atlas_observations` (`user_id`);--> statement-breakpoint
CREATE TABLE `atlas_profiles` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`producer_id` text NOT NULL,
	`character_key` text NOT NULL,
	`name` text,
	`realm` text,
	`class_id` integer,
	`race_id` integer,
	`level` integer,
	`public` integer DEFAULT false NOT NULL,
	`last_seen` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `profiles_user` ON `atlas_profiles` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `profiles_source_character` ON `atlas_profiles` (`user_id`,`producer_id`,`character_key`);--> statement-breakpoint
CREATE TABLE `atlas_sources` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`producer_id` text NOT NULL,
	`max_epoch` integer NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `sources_user_producer` ON `atlas_sources` (`user_id`,`producer_id`);--> statement-breakpoint
CREATE TABLE `atlas_uploads` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`grant_id` text NOT NULL,
	`created_at` integer NOT NULL,
	`accepted` integer NOT NULL,
	`duplicates` integer NOT NULL,
	`rejected` integer NOT NULL
);
