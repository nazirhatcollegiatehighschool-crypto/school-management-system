-- schema_v7.sql
-- 1) PURGE non-financial directive: drop fees table (system is NON-FINANCIAL)
DROP TABLE IF EXISTS `fees`;

-- 2) Extend notifications.type to support homework / complaint / special direct notices
ALTER TABLE `notifications`
  MODIFY `type` ENUM('attendance','result','general','notice','class_test_result','homework','complaint','special') NOT NULL DEFAULT 'general';

-- 3) Homework module (teachers assign to their class/subject; guardians view only own child's)
CREATE TABLE IF NOT EXISTS `homework` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `class_id` INT NOT NULL,
  `subject_id` INT DEFAULT NULL,
  `title` VARCHAR(150) NOT NULL,
  `description` TEXT DEFAULT NULL,
  `due_date` DATE DEFAULT NULL,
  `created_by` INT NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_homework_class` (`class_id`),
  KEY `idx_homework_subject` (`subject_id`),
  CONSTRAINT `fk_homework_class` FOREIGN KEY (`class_id`) REFERENCES `classes` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_homework_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_homework_creator` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE CASCADE
);