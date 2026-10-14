-- Optimized Consolidated Schema - School Management System (Non-Financial)
-- Consolidates v5+v6+v7+v8 + performance indexes + integrity fixes
-- ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS=0;

-- Drop fee table if exists (non-financial directive)
DROP TABLE IF EXISTS `fees`;

-- users
CREATE TABLE IF NOT EXISTS `users` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `role` ENUM('admin','teacher','guardian') NOT NULL,
  `username` VARCHAR(50) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `email` VARCHAR(100) DEFAULT NULL,
  `phone` VARCHAR(20) DEFAULT NULL,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  `is_class_teacher` JSON DEFAULT NULL,
  `designation` VARCHAR(100) DEFAULT NULL,
  `sort_order` INT DEFAULT 99,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_username` (`username`),
  KEY `idx_users_role_active` (`role`,`active`),
  KEY `idx_users_sort` (`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- sessions
CREATE TABLE IF NOT EXISTS `sessions` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(20) NOT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 0,
  UNIQUE KEY `uq_session_name` (`name`),
  KEY `idx_session_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- classes
CREATE TABLE IF NOT EXISTS `classes` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(50) NOT NULL,
  `section` VARCHAR(20) NOT NULL COMMENT 'section for 6-8, group for 9-10',
  `group_name` VARCHAR(20) DEFAULT NULL,
  `session_id` INT DEFAULT NULL,
  `teacher_id` INT DEFAULT NULL,
  UNIQUE KEY `uq_class` (`name`,`section`),
  KEY `idx_class_teacher` (`teacher_id`),
  KEY `idx_class_session` (`session_id`),
  CONSTRAINT `fk_classes_teacher` FOREIGN KEY (`teacher_id`) REFERENCES `users`(`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_classes_session` FOREIGN KEY (`session_id`) REFERENCES `sessions`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- subjects
CREATE TABLE IF NOT EXISTS `subjects` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(60) NOT NULL,
  `class_id` INT NOT NULL,
  `teacher_id` INT DEFAULT NULL,
  `full_marks` INT NOT NULL DEFAULT 100,
  `pass_marks` INT DEFAULT NULL,
  `group_name` VARCHAR(20) NOT NULL DEFAULT 'Compulsory',
  `is_optional` TINYINT(1) NOT NULL DEFAULT 0,
  `is_fourth_subject` TINYINT(1) NOT NULL DEFAULT 0,
  `is_elective` TINYINT(1) NOT NULL DEFAULT 0,
  `excluded_from_gpa` TINYINT(1) NOT NULL DEFAULT 0,
  `cq_full` INT DEFAULT NULL,
  `mcq_full` INT DEFAULT NULL,
  `practical_full` INT DEFAULT NULL,
  `written_full` INT DEFAULT NULL COMMENT 'Written part (লিখিত)',
  `ca_full` INT DEFAULT NULL COMMENT 'Continuous Assessment (ধারাবাহিক মূল্যায়ন)',
  `subject_code` VARCHAR(20) DEFAULT NULL,
  `sort_order` INT DEFAULT NULL,
  UNIQUE KEY `uq_subj` (`class_id`,`name`),
  KEY `idx_subject_teacher` (`teacher_id`),
  KEY `idx_subject_class` (`class_id`),
  CONSTRAINT `fk_subjects_class` FOREIGN KEY (`class_id`) REFERENCES `classes`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_subjects_teacher` FOREIGN KEY (`teacher_id`) REFERENCES `users`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- students
CREATE TABLE IF NOT EXISTS `students` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `student_code` VARCHAR(20) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `dob` DATE DEFAULT NULL,
  `roll` INT NOT NULL,
  `class_id` INT NOT NULL,
  `religion` VARCHAR(20) DEFAULT NULL,
  `guardian_id` INT DEFAULT NULL,
  `guardian_name` VARCHAR(100) DEFAULT NULL,
  `guardian_phone` VARCHAR(20) DEFAULT NULL,
  `guardian_email` VARCHAR(100) DEFAULT NULL,
  `address` VARCHAR(255) DEFAULT NULL,
  `photo` VARCHAR(255) DEFAULT NULL,
  `father_name` VARCHAR(100) DEFAULT NULL,
  `mother_name` VARCHAR(100) DEFAULT NULL,
  `birth_cert_no` VARCHAR(50) DEFAULT NULL,
  `gender` VARCHAR(10) DEFAULT NULL,
  `blood_group` VARCHAR(5) DEFAULT NULL,
  `optional_subject` VARCHAR(60) DEFAULT NULL,
  `phone` VARCHAR(20) DEFAULT NULL,
  `email` VARCHAR(100) DEFAULT NULL,
  `section` VARCHAR(20) DEFAULT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'active',
  `session_id` INT DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_student_code` (`student_code`),
  UNIQUE KEY `uq_roll` (`class_id`,`roll`),
  KEY `idx_student_class` (`class_id`),
  KEY `idx_student_guardian` (`guardian_id`),
  KEY `idx_student_status` (`status`),
  KEY `idx_student_name` (`name`),
  CONSTRAINT `fk_students_class` FOREIGN KEY (`class_id`) REFERENCES `classes`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_students_guardian` FOREIGN KEY (`guardian_id`) REFERENCES `users`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- student_subjects (NCTB allocation)
CREATE TABLE IF NOT EXISTS `student_subjects` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `student_id` INT NOT NULL,
  `subject_id` INT NOT NULL,
  `is_mandatory` TINYINT(1) NOT NULL DEFAULT 0,
  `is_fourth_subject` TINYINT(1) NOT NULL DEFAULT 0,
  `is_elective` TINYINT(1) NOT NULL DEFAULT 0,
  `assigned_by` INT DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_student_subject` (`student_id`,`subject_id`),
  KEY `idx_ss_subject` (`subject_id`),
  CONSTRAINT `fk_ss_student` FOREIGN KEY (`student_id`) REFERENCES `students`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ss_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- exam_events
CREATE TABLE IF NOT EXISTS `exam_events` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(100) NOT NULL,
  `session_id` INT DEFAULT NULL,
  `start_date` DATE DEFAULT NULL,
  `exam_kind` VARCHAR(20) NOT NULL DEFAULT 'other',
  `year` INT DEFAULT NULL,
  `promotion_linked` TINYINT(1) NOT NULL DEFAULT 0,
  `is_published` TINYINT(1) NOT NULL DEFAULT 0,
  `published_at` DATETIME DEFAULT NULL,
  `notify_guardians` TINYINT(1) NOT NULL DEFAULT 0,
  `notified_at` DATETIME DEFAULT NULL,
  `created_by` INT DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_event_session` (`session_id`),
  KEY `idx_event_year_kind` (`year`,`exam_kind`),
  KEY `idx_event_published` (`is_published`),
  UNIQUE KEY `uq_event_kind_year` (`exam_kind`,`year`),
  CONSTRAINT `fk_events_session` FOREIGN KEY (`session_id`) REFERENCES `sessions`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- exams
CREATE TABLE IF NOT EXISTS `exams` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(150) NOT NULL,
  `exam_type` VARCHAR(20) NOT NULL DEFAULT 'class_test',
  `class_id` INT NOT NULL,
  `subject_id` INT NOT NULL,
  `event_id` INT DEFAULT NULL,
  `source` ENUM('admin','teacher') NOT NULL DEFAULT 'teacher',
  `status` ENUM('draft','submitted','published') NOT NULL DEFAULT 'draft',
  `entry_open` TINYINT(1) NOT NULL DEFAULT 1,
  `exam_date` DATE DEFAULT NULL,
  `entry_deadline` DATETIME DEFAULT NULL,
  `created_by` INT NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_exam_class` (`class_id`),
  KEY `idx_exam_subject` (`subject_id`),
  KEY `idx_exam_event` (`event_id`),
  KEY `idx_exam_status` (`status`),
  KEY `idx_exam_created_by` (`created_by`),
  CONSTRAINT `fk_exams_class` FOREIGN KEY (`class_id`) REFERENCES `classes`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_exams_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_exams_event` FOREIGN KEY (`event_id`) REFERENCES `exam_events`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- exam_shares
CREATE TABLE IF NOT EXISTS `exam_shares` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `exam_id` INT NOT NULL,
  `teacher_id` INT NOT NULL,
  `created_by` INT DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_share` (`exam_id`,`teacher_id`),
  KEY `idx_share_teacher` (`teacher_id`),
  CONSTRAINT `fk_share_exam` FOREIGN KEY (`exam_id`) REFERENCES `exams`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- marks
CREATE TABLE IF NOT EXISTS `marks` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `student_id` INT NOT NULL,
  `exam_id` INT NOT NULL,
  `marks` DECIMAL(5,2) NOT NULL,
  `total` DECIMAL(5,2) NOT NULL DEFAULT 100,
  `comment` VARCHAR(255) DEFAULT NULL,
  `cq` DECIMAL(5,2) DEFAULT NULL,
  `mcq` DECIMAL(5,2) DEFAULT NULL,
  `practical` DECIMAL(5,2) DEFAULT NULL,
  `written` DECIMAL(5,2) DEFAULT NULL,
  `ca` DECIMAL(5,2) DEFAULT NULL COMMENT 'Continuous Assessment (ধারাবাহিক মূল্যায়ন)',
  `absent` TINYINT(1) NOT NULL DEFAULT 0,
  `recorded_by` INT DEFAULT NULL,
  `recorded_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `edit_until` DATETIME DEFAULT NULL,
  UNIQUE KEY `uq_mark` (`student_id`,`exam_id`),
  KEY `idx_marks_exam` (`exam_id`),
  KEY `idx_marks_student` (`student_id`),
  CONSTRAINT `fk_marks_student` FOREIGN KEY (`student_id`) REFERENCES `students`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_marks_exam` FOREIGN KEY (`exam_id`) REFERENCES `exams`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ct_marks
CREATE TABLE IF NOT EXISTS `ct_marks` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `student_id` INT NOT NULL,
  `subject_id` INT NOT NULL,
  `ct_no` TINYINT NOT NULL DEFAULT 1,
  `marks` DECIMAL(5,2) NOT NULL,
  `full_marks` DECIMAL(5,2) NOT NULL DEFAULT 25,
  `recorded_by` INT DEFAULT NULL,
  `recorded_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `edit_until` DATETIME DEFAULT NULL,
  UNIQUE KEY `uq_ct` (`student_id`,`subject_id`,`ct_no`),
  KEY `idx_ct_subject` (`subject_id`),
  CONSTRAINT `fk_ct_student` FOREIGN KEY (`student_id`) REFERENCES `students`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ct_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- attendance
CREATE TABLE IF NOT EXISTS `attendance` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `student_id` INT NOT NULL,
  `date` DATE NOT NULL,
  `status` ENUM('present','absent','late') NOT NULL DEFAULT 'present',
  `remark` VARCHAR(255) DEFAULT NULL,
  `is_escape` TINYINT(1) NOT NULL DEFAULT 0,
  `escape_detected_at` DATETIME DEFAULT NULL,
  `recorded_by` INT DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_att` (`student_id`,`date`),
  KEY `idx_att_date` (`date`),
  KEY `idx_att_student_date` (`student_id`,`date`),
  KEY `idx_att_status` (`status`),
  CONSTRAINT `fk_att_student` FOREIGN KEY (`student_id`) REFERENCES `students`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- results
CREATE TABLE IF NOT EXISTS `results` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `student_id` INT NOT NULL,
  `exam_id` INT NOT NULL COMMENT 'exam_events.id',
  `total_gpa_without_4th` DECIMAL(4,2) DEFAULT 0,
  `gpa_4th_bonus` DECIMAL(4,2) DEFAULT 0,
  `final_gpa` DECIMAL(4,2) DEFAULT 0,
  `result_status` ENUM('PASSED','FAILED','ABSENT') DEFAULT 'ABSENT',
  `teacher_remarks` TEXT,
  `computed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_result` (`student_id`,`exam_id`),
  KEY `idx_result_exam` (`exam_id`),
  KEY `idx_result_gpa` (`final_gpa`),
  CONSTRAINT `fk_results_student` FOREIGN KEY (`student_id`) REFERENCES `students`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- notifications
CREATE TABLE IF NOT EXISTS `notifications` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `student_id` INT DEFAULT NULL,
  `class_id` INT DEFAULT NULL,
  `title` VARCHAR(150) NOT NULL,
  `body` TEXT NOT NULL,
  `type` ENUM('attendance','result','general','notice','class_test_result','homework','complaint','special','promotion') NOT NULL DEFAULT 'general',
  `target_type` ENUM('all','class','section','students','guardians','teacher') NOT NULL DEFAULT 'all',
  `related_id` INT DEFAULT NULL,
  `is_read` TINYINT(1) NOT NULL DEFAULT 0,
  `created_by` INT DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_notif_student` (`student_id`),
  KEY `idx_notif_class` (`class_id`),
  KEY `idx_notif_type` (`type`),
  KEY `idx_notif_created_at` (`created_at`),
  CONSTRAINT `fk_notif_student` FOREIGN KEY (`student_id`) REFERENCES `students`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_notif_class` FOREIGN KEY (`class_id`) REFERENCES `classes`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- homework
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
  KEY `idx_homework_created` (`created_by`),
  CONSTRAINT `fk_homework_class` FOREIGN KEY (`class_id`) REFERENCES `classes`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_homework_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `homework_attachments` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `homework_id` INT NOT NULL,
  `file_name` VARCHAR(255) NOT NULL,
  `file_path` VARCHAR(255) NOT NULL,
  `mime_type` VARCHAR(100) DEFAULT NULL,
  `file_size` INT DEFAULT NULL,
  `uploaded_by` INT DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_hw_att_hw` (`homework_id`),
  CONSTRAINT `fk_hw_att_hw` FOREIGN KEY (`homework_id`) REFERENCES `homework`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- guardian_links
CREATE TABLE IF NOT EXISTS `guardian_links` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `guardian_id` INT NOT NULL,
  `student_id` INT NOT NULL,
  `role` ENUM('primary','sibling') NOT NULL DEFAULT 'sibling',
  `status` ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  `requester_student_id` INT DEFAULT NULL,
  `decided_by` INT DEFAULT NULL,
  `remark` VARCHAR(255) DEFAULT NULL,
  `requested_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `decided_at` DATETIME DEFAULT NULL,
  UNIQUE KEY `uq_guardian_student` (`guardian_id`,`student_id`),
  KEY `idx_gl_student` (`student_id`),
  KEY `idx_gl_status` (`status`),
  CONSTRAINT `fk_gl_guardian` FOREIGN KEY (`guardian_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_gl_student` FOREIGN KEY (`student_id`) REFERENCES `students`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- class_teacher_requests
CREATE TABLE IF NOT EXISTS `class_teacher_requests` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `class_id` INT NOT NULL,
  `teacher_id` INT NOT NULL,
  `note` TEXT DEFAULT NULL,
  `status` ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  `decided_by` INT DEFAULT NULL,
  `decided_at` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_ct_req` (`class_id`,`teacher_id`),
  KEY `idx_ctr_status` (`status`),
  CONSTRAINT `fk_ctr_class` FOREIGN KEY (`class_id`) REFERENCES `classes`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ctr_teacher` FOREIGN KEY (`teacher_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- mark_edit_requests
CREATE TABLE IF NOT EXISTS `mark_edit_requests` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `mark_id` INT NOT NULL,
  `student_id` INT NOT NULL,
  `exam_id` INT NOT NULL,
  `teacher_id` INT NOT NULL,
  `reason` VARCHAR(255) DEFAULT NULL,
  `status` ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  `decided_by` INT DEFAULT NULL,
  `decided_at` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_mer_status` (`status`),
  KEY `idx_mer_teacher` (`teacher_id`),
  CONSTRAINT `fk_mer_mark` FOREIGN KEY (`mark_id`) REFERENCES `marks`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- promotions
CREATE TABLE IF NOT EXISTS `promotions` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `student_id` INT NOT NULL,
  `event_id` INT NOT NULL,
  `from_class_id` INT NOT NULL,
  `to_class_id` INT DEFAULT NULL,
  `to_class` VARCHAR(50) DEFAULT NULL,
  `decision` ENUM('promoted','retained','readmission') NOT NULL DEFAULT 'promoted',
  `promoted_roll` INT DEFAULT NULL,
  `final_gpa` DECIMAL(4,2) DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_promotion` (`student_id`,`event_id`),
  KEY `idx_promo_event` (`event_id`),
  CONSTRAINT `fk_promo_student` FOREIGN KEY (`student_id`) REFERENCES `students`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `promotion_history` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `student_id` INT NOT NULL,
  `from_class_id` INT NOT NULL,
  `to_class_id` INT DEFAULT NULL,
  `final_gpa` DECIMAL(4,2) DEFAULT 0,
  `decision` ENUM('promoted','retained','readmission') DEFAULT 'promoted',
  `admin_note` VARCHAR(255) DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_ph_student` (`student_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- time_slots & routines
CREATE TABLE IF NOT EXISTS `time_slots` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `label` VARCHAR(50) NOT NULL,
  `start_time` TIME NOT NULL,
  `end_time` TIME NOT NULL,
  `slot_order` INT NOT NULL DEFAULT 0,
  UNIQUE KEY `uq_slot_order` (`slot_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `routines` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `class_id` INT NOT NULL,
  `subject_id` INT NOT NULL,
  `teacher_id` INT NOT NULL,
  `day` TINYINT NOT NULL,
  `time_slot_id` INT NOT NULL,
  `room` VARCHAR(20) DEFAULT NULL,
  UNIQUE KEY `uq_routine` (`class_id`,`day`,`time_slot_id`),
  KEY `idx_routine_teacher` (`teacher_id`),
  KEY `idx_routine_day` (`day`),
  CONSTRAINT `fk_routine_class` FOREIGN KEY (`class_id`) REFERENCES `classes`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_routine_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_routine_slot` FOREIGN KEY (`time_slot_id`) REFERENCES `time_slots`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `routine_entries` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `class_id` INT NOT NULL,
  `day` TINYINT NOT NULL,
  `period` TINYINT NOT NULL,
  `subject_id` INT DEFAULT NULL,
  `teacher_id` INT DEFAULT NULL,
  UNIQUE KEY `uq_rt` (`class_id`,`day`,`period`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- holidays, settings, logs, tokens
CREATE TABLE IF NOT EXISTS `holidays` (
  `date` DATE PRIMARY KEY,
  `title` VARCHAR(150) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `app_settings` (
  `setting_key` VARCHAR(60) PRIMARY KEY,
  `setting_value` TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `activity_log` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT DEFAULT NULL,
  `action` VARCHAR(100) NOT NULL,
  `detail` TEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_log_user` (`user_id`),
  KEY `idx_log_action` (`action`),
  KEY `idx_log_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `device_tokens` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT NOT NULL,
  `role` VARCHAR(20) NOT NULL,
  `fcm_token` TEXT NOT NULL,
  `platform` VARCHAR(20) DEFAULT 'android',
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  `last_seen` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_token` (`fcm_token`(191)),
  KEY `idx_dt_user` (`user_id`),
  KEY `idx_dt_role_active` (`role`,`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- subject_aliases for NCTB religion display
CREATE TABLE IF NOT EXISTS `subject_aliases` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `subject_id` INT NOT NULL,
  `alias_name` VARCHAR(60) NOT NULL,
  KEY `idx_alias_subject` (`subject_id`),
  CONSTRAINT `fk_alias_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS=1;

-- Default settings
INSERT IGNORE INTO `app_settings` (`setting_key`,`setting_value`) VALUES
('school_name','Nazirhat Collegiate High School'),
('school_address','Nazirhat, Chittagong, Bangladesh'),
('school_eiin',''),
('headmaster',''),
('exam_term_name','Annual Examination');

-- Default time slots
INSERT IGNORE INTO `time_slots` (`id`,`label`,`start_time`,`end_time`,`slot_order`) VALUES
(1,'1st Period','09:00:00','09:45:00',1),
(2,'2nd Period','09:45:00','10:30:00',2),
(3,'3rd Period','10:30:00','11:15:00',3),
(4,'4th Period','11:15:00','12:00:00',4),
(5,'Break','12:00:00','12:30:00',5),
(6,'5th Period','12:30:00','13:15:00',6),
(7,'6th Period','13:15:00','14:00:00',7),
(8,'7th Period','14:00:00','14:45:00',8);
