CREATE TABLE `api_rate_limit_windows` (
	`client_hash` text NOT NULL,
	`minute_bucket` integer NOT NULL,
	`request_count` integer DEFAULT 0 NOT NULL,
	PRIMARY KEY(`client_hash`, `minute_bucket`)
);
--> statement-breakpoint
CREATE INDEX `idx_api_rate_limit_windows_bucket` ON `api_rate_limit_windows` (`minute_bucket`);--> statement-breakpoint
CREATE TABLE `api_usage_daily` (
	`usage_date` text PRIMARY KEY NOT NULL,
	`request_count` integer DEFAULT 0 NOT NULL,
	`spent_microusd` integer DEFAULT 0 NOT NULL,
	`reserved_microusd` integer DEFAULT 0 NOT NULL,
	`daily_limit_microusd` integer NOT NULL,
	`input_tokens` integer DEFAULT 0 NOT NULL,
	`output_tokens` integer DEFAULT 0 NOT NULL,
	`updated_at_ms` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `api_usage_events` (
	`event_id` text PRIMARY KEY NOT NULL,
	`usage_date` text NOT NULL,
	`model` text NOT NULL,
	`reserved_microusd` integer NOT NULL,
	`actual_microusd` integer DEFAULT 0 NOT NULL,
	`status` text NOT NULL,
	`input_tokens` integer DEFAULT 0 NOT NULL,
	`output_tokens` integer DEFAULT 0 NOT NULL,
	`created_at_ms` integer NOT NULL,
	`settled_at_ms` integer
);
--> statement-breakpoint
CREATE INDEX `idx_api_usage_events_status_created` ON `api_usage_events` (`status`,`created_at_ms`);--> statement-breakpoint
CREATE INDEX `idx_api_usage_events_usage_date` ON `api_usage_events` (`usage_date`);