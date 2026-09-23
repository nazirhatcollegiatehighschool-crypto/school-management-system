-- School Management System v3 — full academic structure
-- (sessions, groups, SSC grading, CT marks, results, holidays, settings)
USE school_db;

INSERT IGNORE INTO sessions (id, name, is_active) VALUES (1, '2026', 1);

ALTER TABLE classes ADD COLUMN group_name VARCHAR(20) DEFAULT NULL;
ALTER TABLE classes ADD COLUMN session_id INT DEFAULT NULL;

ALTER TABLE subjects ADD COLUMN full_marks INT NOT NULL DEFAULT 100;
ALTER TABLE subjects ADD COLUMN group_name VARCHAR(20) NOT NULL DEFAULT 'Compulsory';
ALTER TABLE subjects ADD COLUMN is_optional TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE subjects ADD COLUMN excluded_from_gpa TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE subjects ADD COLUMN cq_full INT DEFAULT NULL;
ALTER TABLE subjects ADD COLUMN mcq_full INT DEFAULT NULL;
ALTER TABLE subjects ADD COLUMN practical_full INT DEFAULT NULL;
ALTER TABLE subjects ADD COLUMN subject_code INT DEFAULT NULL;

ALTER TABLE students ADD COLUMN photo VARCHAR(255) DEFAULT NULL;
ALTER TABLE students ADD COLUMN father_name VARCHAR(100) DEFAULT NULL;
ALTER TABLE students ADD COLUMN mother_name VARCHAR(100) DEFAULT NULL;
ALTER TABLE students ADD COLUMN birth_cert_no VARCHAR(50) DEFAULT NULL;
ALTER TABLE students ADD COLUMN session_id INT DEFAULT NULL;

UPDATE students SET session_id = 1 WHERE session_id IS NULL;
UPDATE classes SET session_id = 1 WHERE session_id IS NULL;

INSERT IGNORE INTO app_settings (setting_key, setting_value) VALUES
('school_name', 'My School & College'),
('school_address', 'Dhaka, Bangladesh'),
('school_eiin', ''),
('headmaster', ''),
('exam_term_name', 'Annual Examination');

CREATE TABLE IF NOT EXISTS subject_teachers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  subject_id INT NOT NULL,
  teacher_id INT NOT NULL,
  UNIQUE KEY uq_st (subject_id, teacher_id),
  FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
  FOREIGN KEY (teacher_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ct_marks (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  subject_id INT NOT NULL,
  ct_no TINYINT NOT NULL DEFAULT 1,
  marks DECIMAL(5,2) NOT NULL,
  full_marks DECIMAL(5,2) NOT NULL DEFAULT 25,
  recorded_by INT DEFAULT NULL,
  recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  edit_until DATETIME DEFAULT NULL,
  UNIQUE KEY uq_ct (student_id, subject_id, ct_no),
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS results (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  exam_id INT NOT NULL,
  total_gpa_without_4th DECIMAL(4,2) DEFAULT 0,
  gpa_4th_bonus DECIMAL(4,2) DEFAULT 0,
  final_gpa DECIMAL(4,2) DEFAULT 0,
  result_status ENUM('PASSED','FAILED','ABSENT') DEFAULT 'ABSENT',
  teacher_remarks TEXT,
  computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_result (student_id, exam_id),
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  FOREIGN KEY (exam_id) REFERENCES exams(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS holidays (
  date DATE PRIMARY KEY,
  title VARCHAR(150) NOT NULL
);

CREATE TABLE IF NOT EXISTS app_settings (
  setting_key VARCHAR(60) PRIMARY KEY,
  setting_value TEXT
);

CREATE TABLE IF NOT EXISTS routine_entries (
  id INT AUTO_INCREMENT PRIMARY KEY,
  class_id INT NOT NULL,
  day TINYINT NOT NULL COMMENT '0=Sun..4=Thu',
  period TINYINT NOT NULL,
  subject_id INT DEFAULT NULL,
  teacher_id INT DEFAULT NULL,
  UNIQUE KEY uq_rt (class_id, day, period),
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE SET NULL,
  FOREIGN KEY (teacher_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS promotion_history (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  from_class_id INT NOT NULL,
  to_class_id INT DEFAULT NULL,
  session_from VARCHAR(20),
  session_to VARCHAR(20),
  final_gpa DECIMAL(4,2) DEFAULT 0,
  decision ENUM('promoted','retained','readmission') DEFAULT 'promoted',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sessions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(20) NOT NULL UNIQUE,
  is_active TINYINT(1) NOT NULL DEFAULT 0
);

INSERT IGNORE INTO sessions (id, name, is_active) VALUES (1, '2026', 1);

INSERT IGNORE INTO app_settings (setting_key, setting_value) VALUES
('school_name', 'My School & College'),
('school_address', 'Dhaka, Bangladesh'),
('school_eiin', ''),
('headmaster', ''),
('exam_term_name', 'Annual Examination');