-- School Management System v5 — proper academic structure
-- Classes 6-8: sections A/B/C | Classes 9-10: Science/Commerce/Arts groups
DROP DATABASE IF EXISTS school_db;
CREATE DATABASE school_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE school_db;

CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  role ENUM('admin','teacher','guardian') NOT NULL,
  username VARCHAR(50) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(100) DEFAULT NULL,
  phone VARCHAR(20) DEFAULT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sessions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(20) NOT NULL UNIQUE,
  is_active TINYINT(1) NOT NULL DEFAULT 0
);

CREATE TABLE classes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  section VARCHAR(20) NOT NULL COMMENT 'section for 6-8, group for 9-10',
  group_name VARCHAR(20) DEFAULT NULL,
  session_id INT DEFAULT NULL,
  teacher_id INT DEFAULT NULL,
  UNIQUE KEY uq_class (name, section),
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE SET NULL,
  FOREIGN KEY (teacher_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE subjects (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(60) NOT NULL,
  class_id INT NOT NULL,
  teacher_id INT DEFAULT NULL,
  full_marks INT NOT NULL DEFAULT 100,
  group_name VARCHAR(20) NOT NULL DEFAULT 'Compulsory',
  is_optional TINYINT(1) NOT NULL DEFAULT 0,
  excluded_from_gpa TINYINT(1) NOT NULL DEFAULT 0,
  cq_full INT DEFAULT NULL,
  mcq_full INT DEFAULT NULL,
  practical_full INT DEFAULT NULL,
  subject_code INT DEFAULT NULL,
  UNIQUE KEY uq_subj (class_id, name),
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  FOREIGN KEY (teacher_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE students (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_code VARCHAR(20) NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL,
  dob DATE DEFAULT NULL,
  roll INT NOT NULL,
  class_id INT NOT NULL,
  guardian_id INT DEFAULT NULL,
  guardian_name VARCHAR(100) DEFAULT NULL,
  guardian_phone VARCHAR(20) DEFAULT NULL,
  guardian_email VARCHAR(100) DEFAULT NULL,
  address VARCHAR(255) DEFAULT NULL,
  photo VARCHAR(255) DEFAULT NULL,
  father_name VARCHAR(100) DEFAULT NULL,
  mother_name VARCHAR(100) DEFAULT NULL,
  birth_cert_no VARCHAR(50) DEFAULT NULL,
  session_id INT DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_roll (class_id, roll),
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  FOREIGN KEY (guardian_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE exam_events (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  session_id INT DEFAULT NULL,
  start_date DATE DEFAULT NULL,
  created_by INT DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE SET NULL
);

CREATE TABLE exams (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(150) NOT NULL,
  exam_type ENUM('class_test','midterm','final') NOT NULL DEFAULT 'class_test',
  class_id INT NOT NULL,
  subject_id INT NOT NULL,
  event_id INT DEFAULT NULL,
  source ENUM('admin','teacher') NOT NULL DEFAULT 'teacher',
  status ENUM('draft','published') NOT NULL DEFAULT 'draft',
  created_by INT NOT NULL,
  exam_date DATE DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
  FOREIGN KEY (event_id) REFERENCES exam_events(id) ON DELETE SET NULL,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE marks (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  exam_id INT NOT NULL,
  marks DECIMAL(5,2) NOT NULL,
  total DECIMAL(5,2) NOT NULL DEFAULT 100,
  comment VARCHAR(255) DEFAULT NULL,
  cq DECIMAL(5,2) DEFAULT NULL,
  mcq DECIMAL(5,2) DEFAULT NULL,
  practical DECIMAL(5,2) DEFAULT NULL,
  written DECIMAL(5,2) DEFAULT NULL,
  absent TINYINT(1) NOT NULL DEFAULT 0,
  recorded_by INT DEFAULT NULL,
  recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  edit_until DATETIME DEFAULT NULL,
  UNIQUE KEY uq_mark (student_id, exam_id),
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  FOREIGN KEY (exam_id) REFERENCES exams(id) ON DELETE CASCADE,
  FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE ct_marks (
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

CREATE TABLE attendance (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  date DATE NOT NULL,
  status ENUM('present','absent','late') NOT NULL DEFAULT 'present',
  remark VARCHAR(255) DEFAULT NULL,
  recorded_by INT DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_att (student_id, date),
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
);

CREATE TABLE results (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  exam_id INT NOT NULL COMMENT 'exam_events.id',
  total_gpa_without_4th DECIMAL(4,2) DEFAULT 0,
  gpa_4th_bonus DECIMAL(4,2) DEFAULT 0,
  final_gpa DECIMAL(4,2) DEFAULT 0,
  result_status ENUM('PASSED','FAILED','ABSENT') DEFAULT 'ABSENT',
  teacher_remarks TEXT,
  computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_result (student_id, exam_id),
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
);

CREATE TABLE notifications (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT DEFAULT NULL,
  class_id INT DEFAULT NULL,
  title VARCHAR(150) NOT NULL,
  body TEXT NOT NULL,
  type ENUM('attendance','result','general','notice','class_test_result') NOT NULL DEFAULT 'general',
  is_read TINYINT(1) NOT NULL DEFAULT 0,
  created_by INT DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
);

CREATE TABLE holidays (
  date DATE PRIMARY KEY,
  title VARCHAR(150) NOT NULL
);

CREATE TABLE app_settings (
  setting_key VARCHAR(60) PRIMARY KEY,
  setting_value TEXT
);

CREATE TABLE routine_entries (
  id INT AUTO_INCREMENT PRIMARY KEY,
  class_id INT NOT NULL,
  day TINYINT NOT NULL,
  period TINYINT NOT NULL,
  subject_id INT DEFAULT NULL,
  teacher_id INT DEFAULT NULL,
  UNIQUE KEY uq_rt (class_id, day, period),
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
);

CREATE TABLE promotion_history (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  from_class_id INT NOT NULL,
  to_class_id INT DEFAULT NULL,
  final_gpa DECIMAL(4,2) DEFAULT 0,
  decision ENUM('promoted','retained','readmission') DEFAULT 'promoted',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE activity_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT DEFAULT NULL,
  action VARCHAR(100) NOT NULL,
  detail TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE device_tokens (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  role VARCHAR(20) NOT NULL,
  fcm_token TEXT NOT NULL,
  platform VARCHAR(20) DEFAULT 'android',
  active TINYINT(1) NOT NULL DEFAULT 1,
  last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_token (fcm_token(191)),
  KEY idx_user (user_id)
);

INSERT INTO sessions (id, name, is_active) VALUES (1, '2026', 1);
INSERT INTO exam_events (id, name, session_id, created_by) VALUES (1, 'First Terminal Examination 2026', 1, 1), (2, 'Annual Examination 2026', 1, 1);

INSERT INTO app_settings VALUES
('school_name', 'My School & College'),
('school_address', 'Dhaka, Bangladesh'),
('school_eiin', ''),
('headmaster', ''),
('exam_term_name', 'Annual Examination');