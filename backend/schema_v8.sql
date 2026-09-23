-- schema_v8.sql
-- Guardian sibling linking with ADMIN APPROVAL.
-- A guardian account is linked to a student ONLY via an approved link.
-- Until admin approval, the sibling's data is invisible to the guardian.

CREATE TABLE IF NOT EXISTS `guardian_links` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `guardian_id` INT NOT NULL,          -- users.id (guardian account)
  `student_id` INT NOT NULL,           -- students.id
  `role` ENUM('primary','sibling') NOT NULL DEFAULT 'sibling',
  `status` ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  `requester_student_id` INT DEFAULT NULL, -- student who initiated the request (primary)
  `decided_by` INT DEFAULT NULL,
  `remark` VARCHAR(255) DEFAULT NULL,
  `requested_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `decided_at` DATETIME DEFAULT NULL,
  UNIQUE KEY `uq_guardian_student` (`guardian_id`, `student_id`),
  KEY `idx_gl_student` (`student_id`),
  KEY `idx_gl_status` (`status`),
  CONSTRAINT `fk_gl_guardian` FOREIGN KEY (`guardian_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_gl_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_gl_req` FOREIGN KEY (`requester_student_id`) REFERENCES `students` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_gl_decided` FOREIGN KEY (`decided_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
);

ALTER TABLE students ADD COLUMN section VARCHAR(20) DEFAULT NULL;
ALTER TABLE promotion_history ADD COLUMN admin_note VARCHAR(255) DEFAULT NULL;
ALTER TABLE students ADD COLUMN status VARCHAR(20) DEFAULT 'active';
