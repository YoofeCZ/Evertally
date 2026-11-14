CREATE TABLE IF NOT EXISTS `et_sharing` (
	`user_id` text PRIMARY KEY NOT NULL,
	`friends` integer DEFAULT 0 NOT NULL,
	`signed_in` integer DEFAULT 0 NOT NULL,
	`public` integer DEFAULT 0 NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `et_friends` (
	`user_a` text NOT NULL,
	`user_b` text NOT NULL,
	`requested_by` text NOT NULL,
	`status` text NOT NULL,
	`created_at` integer NOT NULL,
	`answered_at` integer,
	PRIMARY KEY(`user_a`, `user_b`)
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `friends_b` ON `et_friends` (`user_b`);
