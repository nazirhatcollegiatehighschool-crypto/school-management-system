-- ON DUPLICATE KEY / INSERT IGNORE dedup in the notification code requires a
-- real unique index. The prefix keeps the index valid on older TEXT columns.
CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_dedup
  ON notifications(dedup_key);
