CREATE TABLE `et_circles` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`owner_user_id` text NOT NULL,
	`invite_code` text NOT NULL,
	`created_at` integer NOT NULL,
	`closed_at` integer
);
--> statement-breakpoint
CREATE UNIQUE INDEX `circles_code` ON `et_circles` (`invite_code`);--> statement-breakpoint
CREATE INDEX `circles_owner` ON `et_circles` (`owner_user_id`);--> statement-breakpoint
CREATE TABLE `et_circle_members` (
	`circle_id` text NOT NULL,
	`user_id` text NOT NULL,
	`profile_id` text NOT NULL,
	`share` text NOT NULL,
	`joined_at` integer NOT NULL,
	PRIMARY KEY(`circle_id`, `user_id`)
);
--> statement-breakpoint
CREATE INDEX `circle_members_user` ON `et_circle_members` (`user_id`);--> statement-breakpoint
CREATE INDEX `circle_members_profile` ON `et_circle_members` (`profile_id`);--> statement-breakpoint
CREATE TABLE `et_meets` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`host` text NOT NULL,
	`kind` text NOT NULL,
	`title` text NOT NULL,
	`note` text NOT NULL,
	`map_id` integer NOT NULL,
	`x` real NOT NULL,
	`y` real NOT NULL,
	`starts_at` integer,
	`ends_at` integer NOT NULL,
	`audience_kind` text NOT NULL,
	`audience_id` text,
	`link_code` text,
	`capacity` integer,
	`data` text NOT NULL,
	`status` text NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `meets_user` ON `et_meets` (`user_id`);--> statement-breakpoint
CREATE INDEX `meets_audience` ON `et_meets` (`audience_kind`,`audience_id`);--> statement-breakpoint
CREATE INDEX `meets_link` ON `et_meets` (`link_code`);--> statement-breakpoint
CREATE TABLE `et_meet_rsvps` (
	`meet_id` text NOT NULL,
	`user_id` text NOT NULL,
	`name` text NOT NULL,
	`status` text NOT NULL,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`meet_id`, `user_id`)
);
--> statement-breakpoint
CREATE INDEX `meet_rsvps_user` ON `et_meet_rsvps` (`user_id`);--> statement-breakpoint
CREATE TABLE `et_meet_access` (
	`meet_id` text NOT NULL,
	`user_id` text NOT NULL,
	PRIMARY KEY(`meet_id`, `user_id`)
);
--> statement-breakpoint
CREATE INDEX `meet_access_user` ON `et_meet_access` (`user_id`);
