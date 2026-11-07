-- Production gap fix (2026-11-06), MySQL/MariaDB variant.
-- See the postgres migration for the rationale. Add-only.
CREATE TABLE IF NOT EXISTS `event_promotion_grace` (
  `event_id` INT NOT NULL,
  `class_id` INT NOT NULL,
  `subject_id` INT NOT NULL,
  `granted_by` INT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`event_id`, `class_id`, `subject_id`),
  INDEX `ix_event_promotion_grace_class` (`class_id`, `event_id`),
  CONSTRAINT `fk_epg_event` FOREIGN KEY (`event_id`) REFERENCES `exam_events` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_epg_class` FOREIGN KEY (`class_id`) REFERENCES `classes` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_epg_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_epg_user` FOREIGN KEY (`granted_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `marksheet_templates` (
  `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(120) NOT NULL,
  `is_default` TINYINT(1) NOT NULL DEFAULT 0,
  `layout_json` JSON NULL,
  `grading_scale_json` JSON NULL,
  `branding_json` JSON NULL,
  `created_by` INT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `ix_marksheet_templates_default` (`is_default`),
  CONSTRAINT `fk_mst_user` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
