CREATE TABLE `et_device_codes` (
	`code_hash` text PRIMARY KEY NOT NULL,
	`user_code` text NOT NULL,
	`name` text NOT NULL,
	`created_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	`approved_by` text,
	`scopes` text,
	`device_id` text,
	`denied_at` integer
);
--> statement-breakpoint
CREATE UNIQUE INDEX `device_codes_user_code` ON `et_device_codes` (`user_code`);--> statement-breakpoint
CREATE TABLE `et_devices` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`name` text NOT NULL,
	`token_hash` text NOT NULL,
	`scopes` text NOT NULL,
	`created_at` integer NOT NULL,
	`last_seen_at` integer,
	`revoked_at` integer
);
--> statement-breakpoint
CREATE INDEX `devices_user` ON `et_devices` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `devices_token` ON `et_devices` (`token_hash`);--> statement-breakpoint
CREATE TABLE `et_sessions` (
	`token_hash` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`created_at` integer NOT NULL,
	`expires_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `sessions_user` ON `et_sessions` (`user_id`);--> statement-breakpoint
CREATE TABLE `et_users` (
	`id` text PRIMARY KEY NOT NULL,
	`discord_id` text,
	`username` text NOT NULL,
	`display_name` text,
	`avatar` text,
	`created_at` integer NOT NULL,
	`last_login_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `users_discord` ON `et_users` (`discord_id`);