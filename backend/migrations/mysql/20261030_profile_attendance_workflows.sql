-- Consolidated add-only schema for the profile, uniform-report, notification and
-- attendance-access workflows (MariaDB 10.4+). Safe to rerun. Supersedes the
-- 20261029_* preparation files. No table or row is dropped.
ALTER TABLE students
  ADD COLUMN IF NOT EXISTS guardian_profile_locked_at DATETIME NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS class10_start_year SMALLINT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS is_irregular TINYINT(1) NOT NULL DEFAULT 0;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS teacher_dob DATE NULL,
  ADD COLUMN IF NOT EXISTS teacher_address VARCHAR(255) NULL,
  ADD COLUMN IF NOT EXISTS teacher_blood_group VARCHAR(5) NULL,
  ADD COLUMN IF NOT EXISTS teacher_index_number VARCHAR(40) NULL,
  ADD COLUMN IF NOT EXISTS teacher_pns_number VARCHAR(40) NULL,
  ADD COLUMN IF NOT EXISTS teacher_degree VARCHAR(150) NULL,
  ADD COLUMN IF NOT EXISTS teacher_joining_date DATE NULL;

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS target_user_id INT DEFAULT NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_target_user ON notifications(target_user_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_dedup ON notifications(dedup_key);

ALTER TABLE attendance_delegation ADD COLUMN IF NOT EXISTS expires_at_epoch BIGINT DEFAULT NULL;
ALTER TABLE attendance_summary
  ADD COLUMN IF NOT EXISTS early_departure_with_leave INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS early_departure_no_leave INT NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_attendance_delegation_scope ON attendance_delegation(class_id, date, session, granted_to);

CREATE TABLE IF NOT EXISTS attendance_access_requests (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  class_id INT NOT NULL,
  class_teacher_id INT NOT NULL,
  requested_by INT NOT NULL,
  attendance_date DATE NOT NULL,
  session VARCHAR(20) NOT NULL,
  routine_slot_id INT DEFAULT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  expires_at_epoch BIGINT NOT NULL,
  decided_by INT DEFAULT NULL,
  decided_at TIMESTAMP NULL DEFAULT NULL,
  delegation_id INT DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_att_access_inbox (class_teacher_id, status, expires_at_epoch),
  KEY idx_att_access_requester (requested_by, created_at),
  KEY idx_att_access_scope (class_id, attendance_date, session),
  CONSTRAINT fk_att_access_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  CONSTRAINT fk_att_access_class_teacher FOREIGN KEY (class_teacher_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_att_access_requester FOREIGN KEY (requested_by) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_att_access_decider FOREIGN KEY (decided_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS student_profile_edit_requests (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  guardian_id INT NOT NULL,
  class_id INT NOT NULL,
  class_teacher_id INT DEFAULT NULL,
  reason VARCHAR(1000) NOT NULL,
  proposed_changes JSON DEFAULT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  reviewed_by INT DEFAULT NULL,
  reviewer_role VARCHAR(20) DEFAULT NULL,
  admin_note VARCHAR(1000) DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at TIMESTAMP NULL DEFAULT NULL,
  KEY idx_student_profile_request_student (student_id, status, created_at),
  KEY idx_student_profile_request_teacher (class_teacher_id, status, created_at),
  CONSTRAINT fk_profile_request_student FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  CONSTRAINT fk_profile_request_guardian FOREIGN KEY (guardian_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_profile_request_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  CONSTRAINT fk_profile_request_class_teacher FOREIGN KEY (class_teacher_id) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_profile_request_reviewer FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS student_uniform_reports (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  class_id INT NOT NULL,
  teacher_id INT NOT NULL,
  report_date DATE NOT NULL,
  uniform_brought TINYINT(1) NOT NULL,
  note VARCHAR(500) DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_student_uniform_report (student_id, report_date),
  KEY idx_student_uniform_reports_class_date (class_id, report_date),
  CONSTRAINT fk_uniform_student FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  CONSTRAINT fk_uniform_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  CONSTRAINT fk_uniform_teacher FOREIGN KEY (teacher_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS teacher_notification_reads (
  notification_id INT NOT NULL,
  user_id INT NOT NULL,
  read_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (notification_id, user_id),
  CONSTRAINT fk_teacher_notification_read_notification FOREIGN KEY (notification_id) REFERENCES notifications(id) ON DELETE CASCADE,
  CONSTRAINT fk_teacher_notification_read_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Existing profiles that already contain every required field stay locked;
-- incomplete admissions remain open for the guardian's one-time completion.
UPDATE students SET guardian_profile_locked_at=NOW()
WHERE guardian_profile_locked_at IS NULL
  AND TRIM(COALESCE(name,''))<>''
  AND TRIM(COALESCE(religion,''))<>''
  AND TRIM(COALESCE(guardian_name,''))<>''
  AND TRIM(COALESCE(guardian_phone,''))<>''
  AND TRIM(COALESCE(father_name,''))<>''
  AND TRIM(COALESCE(mother_name,''))<>''
  AND TRIM(COALESCE(address,''))<>''
  AND TRIM(COALESCE(gender,''))<>'';

UPDATE students s
JOIN classes c ON c.id=s.class_id
LEFT JOIN sessions se ON se.id=s.session_id
SET s.class10_start_year=COALESCE(s.class10_start_year, CAST(REGEXP_SUBSTR(se.name,'[0-9]{4}') AS UNSIGNED))
WHERE c.name REGEXP '(^|[^0-9])10([^0-9]|$)';

UPDATE students SET is_irregular=1, status='active' WHERE status='irregular';

UPDATE students SET gender='Female'
WHERE LOWER(TRIM(gender)) IN ('female','femal','femail','females');
