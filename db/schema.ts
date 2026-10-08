import { index, integer, primaryKey, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const apiUsageDaily = sqliteTable("api_usage_daily", {
  usageDate: text("usage_date").primaryKey(),
  requestCount: integer("request_count").notNull().default(0),
  spentMicrousd: integer("spent_microusd").notNull().default(0),
  reservedMicrousd: integer("reserved_microusd").notNull().default(0),
  dailyLimitMicrousd: integer("daily_limit_microusd").notNull(),
  inputTokens: integer("input_tokens").notNull().default(0),
  outputTokens: integer("output_tokens").notNull().default(0),
  updatedAtMs: integer("updated_at_ms").notNull(),
});

export const apiUsageEvents = sqliteTable(
  "api_usage_events",
  {
    eventId: text("event_id").primaryKey(),
    usageDate: text("usage_date").notNull(),
    model: text("model").notNull(),
    reservedMicrousd: integer("reserved_microusd").notNull(),
    actualMicrousd: integer("actual_microusd").notNull().default(0),
    status: text("status").notNull(),
    inputTokens: integer("input_tokens").notNull().default(0),
    outputTokens: integer("output_tokens").notNull().default(0),
    createdAtMs: integer("created_at_ms").notNull(),
    settledAtMs: integer("settled_at_ms"),
  },
  (table) => [
    index("idx_api_usage_events_status_created").on(table.status, table.createdAtMs),
    index("idx_api_usage_events_usage_date").on(table.usageDate),
  ],
);

export const apiRateLimitWindows = sqliteTable(
  "api_rate_limit_windows",
  {
    clientHash: text("client_hash").notNull(),
    minuteBucket: integer("minute_bucket").notNull(),
    requestCount: integer("request_count").notNull().default(0),
  },
  (table) => [
    primaryKey({ columns: [table.clientHash, table.minuteBucket] }),
    index("idx_api_rate_limit_windows_bucket").on(table.minuteBucket),
  ],
);
