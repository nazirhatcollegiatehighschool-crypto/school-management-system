-- Incremental migration on top of schema_v5.sql / seed_v5.sql
-- Adds: 'submitted' exam status (result lock workflow),
--       exam_shares (admin explicitly sharing teacher exams),
--       notification target columns for section-level notices.
-- NOTE (user decision): no fees module in the system for now — fees table
-- intentionally NOT created here.

USE school_db;

-- 1) exam status gains 'submitted' (draft -> submitted -> published)
ALTER TABLE `exams`
  MODIFY COLUMN `status` ENUM('draft','submitted','published') NOT NULL DEFAULT 'draft';

-- 2) exam_shares: admin grants a teacher-created exam to other teachers
CREATE TABLE IF NOT EXISTS `exam_shares` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `exam_id` INT(11) NOT NULL,
  `teacher_id` INT(11) NOT NULL,
  `created_by` INT(11) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_share` (`exam_id`,`teacher_id`),
  KEY `idx_share_teacher` (`teacher_id`),
  CONSTRAINT `fk_share_exam` FOREIGN KEY (`exam_id`) REFERENCES `exams` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3) notifications: optional per-student/guardian targeting already covered by
--    student_id/class_id; add target_type to distinguish notice scopes
ALTER TABLE `notifications`
  ADD COLUMN `target_type` ENUM('all','class','section','students','guardians','teacher') NOT NULL DEFAULT 'all'
  AFTER `type`,
  ADD COLUMN `related_id` INT(11) NULL AFTER `target_type`;