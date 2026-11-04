-- Preserve who deactivated a student and the academic session for the admin archive.
ALTER TABLE students
  ADD COLUMN IF NOT EXISTS deactivated_by INT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS deactivated_at DATETIME DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS deactivated_session_id INT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS deactivated_session_name VARCHAR(100) DEFAULT NULL;
