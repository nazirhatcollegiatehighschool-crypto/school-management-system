CREATE TABLE IF NOT EXISTS `guardian_sessions` (
  `guardian_id` INT NOT NULL PRIMARY KEY,
  `session_id` VARCHAR(64) NULL,
  `last_login_at` DATETIME NULL,
  `last_seen_at` DATETIME NULL,
  `logout_at` DATETIME NULL,
  `last_logout_at` DATETIME NULL,
  CONSTRAINT `fk_guardian_sessions_user` FOREIGN KEY (`guardian_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  INDEX `ix_guardian_sessions_last_seen` (`last_seen_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- The CREATE TABLE above is skipped when the table already exists (for example
-- when a mirror/snapshot created it without the secondary index), so add the
-- index separately and idempotently.
SET @gs_idx := (
  SELECT COUNT(*) FROM information_schema.statistics
  WHERE table_schema = DATABASE()
    AND table_name = 'guardian_sessions'
    AND index_name = 'ix_guardian_sessions_last_seen'
);
SET @gs_sql := IF(@gs_idx = 0,
  'CREATE INDEX `ix_guardian_sessions_last_seen` ON `guardian_sessions` (`last_seen_at`)',
  'DO 0');
PREPARE gs_stmt FROM @gs_sql;
EXECUTE gs_stmt;
DEALLOCATE PREPARE gs_stmt;
