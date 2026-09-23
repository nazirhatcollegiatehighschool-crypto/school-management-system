-- School Management System v2 schema
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
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE classes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  section VARCHAR(10) NOT NULL,
  teacher_id INT DEFAULT NULL,
  UNIQUE KEY uq_class (name, section),
  FOREIGN KEY (teacher_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE subjects (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  class_id INT NOT NULL,
  teacher_id INT DEFAULT NULL,
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
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_roll (class_id, roll),
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  FOREIGN KEY (guardian_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE exams (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  exam_type ENUM('class_test','midterm','final') NOT NULL DEFAULT 'class_test',
  class_id INT NOT NULL,
  subject_id INT NOT NULL,
  source ENUM('admin','teacher') NOT NULL DEFAULT 'teacher',
  created_by INT NOT NULL,
  exam_date DATE DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE marks (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  exam_id INT NOT NULL,
  marks DECIMAL(5,2) NOT NULL,
  total DECIMAL(5,2) NOT NULL DEFAULT 100,
  recorded_by INT DEFAULT NULL,
  recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  edit_until DATETIME DEFAULT NULL,
  UNIQUE KEY uq_mark (student_id, exam_id),
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  FOREIGN KEY (exam_id) REFERENCES exams(id) ON DELETE CASCADE,
  FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE SET NULL
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
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE notifications (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT DEFAULT NULL,
  class_id INT DEFAULT NULL,
  title VARCHAR(150) NOT NULL,
  body TEXT NOT NULL,
  type ENUM('attendance','result','general','notice','class_test_result','homework','complaint','special') NOT NULL DEFAULT 'general',
  target_type ENUM('all','class','section','students','guardians','teacher') NOT NULL DEFAULT 'all',
  related_id INT DEFAULT NULL,
  is_read TINYINT(1) NOT NULL DEFAULT 0,
  created_by INT DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE homework (
  id INT AUTO_INCREMENT PRIMARY KEY,
  class_id INT NOT NULL,
  subject_id INT DEFAULT NULL,
  title VARCHAR(150) NOT NULL,
  description TEXT DEFAULT NULL,
  due_date DATE DEFAULT NULL,
  created_by INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE activity_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT DEFAULT NULL,
  action VARCHAR(100) NOT NULL,
  detail TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- Seed data (all passwords: 123456)
INSERT INTO users (id, role, username, password_hash, name, email, phone) VALUES
(1, 'admin', 'admin', '$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.', 'School Admin', 'admin@school.com', '01700000000'),
(2, 'teacher', 'rahim', '$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.', 'Rahim Uddin', 'rahim@school.com', '01711111111'),
(3, 'teacher', 'karim', '$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.', 'Karim Ahmed', 'karim@school.com', '01722222222'),
(4, 'guardian', 'salim', '$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.', 'Salim Khan', 'salim@school.com', '01733333333'),
(5, 'guardian', 'jamal', '$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.', 'Jamal Hossain', 'jamal@school.com', '01744444444');

INSERT INTO classes (id, name, section, teacher_id) VALUES
(1, 'Class 6', 'A', 2),
(2, 'Class 6', 'B', 3),
(3, 'Class 7', 'A', 2),
(4, 'Class 8', 'A', 3);

INSERT INTO subjects (id, name, class_id, teacher_id) VALUES
(1, 'Bangla', 1, 2), (2, 'English', 1, 2), (3, 'Math', 1, 2),
(4, 'Bangla', 2, 3), (5, 'English', 2, 3), (6, 'Math', 2, 3),
(7, 'Bangla', 3, 2), (8, 'English', 3, 2), (9, 'Math', 3, 3),
(10, 'Bangla', 4, 3), (11, 'English', 4, 3), (12, 'Math', 4, 3);

INSERT INTO students (id, student_code, name, dob, roll, class_id, guardian_id, guardian_name, guardian_phone, guardian_email, address) VALUES
(1, 'S-2026-001', 'Arif Rahman', '2013-05-12', 1, 1, 4, 'Salim Khan', '01733333333', 'salim@school.com', 'Dhaka'),
(2, 'S-2026-002', 'Sadia Akter', '2013-08-21', 2, 1, 5, 'Jamal Hossain', '01744444444', 'jamal@school.com', 'Dhaka'),
(3, 'S-2026-003', 'Tanim Islam', '2013-11-03', 3, 1, 4, 'Salim Khan', '01733333333', 'salim@school.com', 'Dhaka'),
(4, 'S-2026-004', 'Nusrat Jahan', '2012-02-14', 1, 3, 5, 'Jamal Hossain', '01744444444', 'jamal@school.com', 'Dhaka'),
(5, 'S-2026-005', 'Fahim Chowdhury', '2012-07-30', 2, 3, 4, 'Salim Khan', '01733333333', 'salim@school.com', 'Dhaka'),
(6, 'S-2026-006', 'Mim Khatun', '2011-01-19', 1, 4, 5, 'Jamal Hossain', '01744444444', 'jamal@school.com', 'Dhaka');

INSERT INTO attendance (student_id, date, status, remark, recorded_by) VALUES
(1, '2026-08-20', 'present', NULL, 2),
(2, '2026-08-20', 'present', NULL, 2),
(3, '2026-08-20', 'absent', 'Sick', 2),
(4, '2026-08-20', 'present', NULL, 2),
(5, '2026-08-20', 'late', NULL, 2),
(6, '2026-08-20', 'present', NULL, 3);

INSERT INTO exams (id, name, exam_type, class_id, subject_id, source, created_by, exam_date) VALUES
(1, 'Midterm 2026 - Bangla', 'midterm', 1, 1, 'admin', 1, '2026-08-10'),
(2, 'Midterm 2026 - English', 'midterm', 1, 2, 'admin', 1, '2026-08-12'),
(3, 'Class Test 1 - Math', 'class_test', 1, 3, 'teacher', 2, '2026-08-18');

INSERT INTO marks (student_id, exam_id, marks, total, recorded_by, recorded_at, edit_until) VALUES
(1, 1, 78, 100, 2, '2026-08-12 10:00:00', '2026-08-12 10:10:00'),
(2, 1, 65, 100, 2, '2026-08-12 10:00:00', '2026-08-12 10:10:00'),
(3, 1, 55, 100, 2, '2026-08-12 10:00:00', '2026-08-12 10:10:00'),
(1, 2, 85, 100, 2, '2026-08-12 11:00:00', '2026-08-12 11:10:00'),
(2, 2, 71, 100, 2, '2026-08-12 11:00:00', '2026-08-12 11:10:00'),
(3, 2, 60, 100, 2, '2026-08-12 11:00:00', '2026-08-12 11:10:00');

INSERT INTO notifications (student_id, title, body, type, created_by) VALUES
(1, 'Midterm result published', 'Arif got 78 in Bangla, 85 in English (Midterm 2026).', 'result', 2),
(2, 'Midterm result published', 'Sadia got 65 in Bangla, 71 in English (Midterm 2026).', 'result', 2),
(3, 'Midterm result published', 'Tanim got 55 in Bangla, 60 in English (Midterm 2026).', 'result', 2),
(1, 'Attendance alert', 'Arif was absent on 2026-08-21.', 'attendance', 2),
(4, 'Attendance alert', 'Nusrat was absent on 2026-08-21.', 'attendance', 2);

INSERT INTO activity_log (user_id, action, detail) VALUES
(1, 'seed', 'Initial data created');