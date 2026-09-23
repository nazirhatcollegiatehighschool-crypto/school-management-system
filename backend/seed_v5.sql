USE school_db;

-- Users (passwords: 123456)
INSERT INTO users (id, role, username, password_hash, name, email, phone) VALUES
(1, 'admin', 'admin', '$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.', 'School Admin', 'admin@school.com', '01700000000'),
(2, 'teacher', 'rahim', '$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.', 'Rahim Uddin', 'rahim@school.com', '01711111111'),
(3, 'teacher', 'karim', '$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.', 'Karim Ahmed', 'karim@school.com', '01722222222'),
(4, 'teacher', 'salma', '$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.', 'Salma Begum', 'salma@school.com', '01733333333');

-- Classes: 6-8 sections A/B/C, 9-10 groups
INSERT INTO classes (id, name, section, group_name, session_id, teacher_id) VALUES
(1,'Class 6','A',NULL,1,2),(2,'Class 6','B',NULL,1,3),(3,'Class 6','C',NULL,1,NULL),
(4,'Class 7','A',NULL,1,3),(5,'Class 7','B',NULL,1,2),(6,'Class 7','C',NULL,1,NULL),
(7,'Class 8','A',NULL,1,2),(8,'Class 8','B',NULL,1,3),(9,'Class 8','C',NULL,1,NULL),
(10,'Class 9','Science','Science',1,4),(11,'Class 9','Commerce','Commerce',1,4),(12,'Class 9','Arts','Arts',1,NULL),
(13,'Class 10','Science','Science',1,4),(14,'Class 10','Commerce','Commerce',1,NULL),(15,'Class 10','Arts','Arts',1,NULL);

-- Subjects for 6-8 (per section): junior curriculum
INSERT INTO subjects (name, class_id, teacher_id, full_marks, cq_full, mcq_full, subject_code)
SELECT s.name, c.id,
  CASE WHEN s.name LIKE 'Bangla%' THEN 2 WHEN s.name LIKE 'English%' OR s.name IN ('Mathematics','General Science') THEN 3 ELSE NULL END,
  IF(s.name='ICT', 50, 100), 70, 30, s.code
FROM classes c
JOIN (SELECT 'Bangla 1st' name,101 code UNION ALL SELECT 'Bangla 2nd',102 UNION ALL SELECT 'English 1st',107
      UNION ALL SELECT 'Mathematics',109 UNION ALL SELECT 'General Science',127 UNION ALL SELECT 'Bangladesh & Global Studies',110
      UNION ALL SELECT 'Religion',111 UNION ALL SELECT 'ICT',174) s
WHERE c.name IN ('Class 6','Class 7','Class 8');

-- Class 9-10 Compulsory
INSERT INTO subjects (name, class_id, teacher_id, full_marks, cq_full, mcq_full, subject_code)
SELECT s.name, c.id, NULL, 100, 70, 30, s.code
FROM classes c
JOIN (SELECT 'Bangla 1st' name,101 code UNION ALL SELECT 'Bangla 2nd',102 UNION ALL SELECT 'English 1st',107
      UNION ALL SELECT 'Mathematics',109 UNION ALL SELECT 'Religion',111 UNION ALL SELECT 'ICT',174) s
WHERE c.name IN ('Class 9','Class 10');

-- Science group subjects
INSERT INTO subjects (name, class_id, full_marks, group_name, is_optional, cq_full, mcq_full, practical_full, subject_code)
SELECT s.name, c.id, 100, 'Science', s.opt, s.cq, s.m, s.p, s.code
FROM classes c
JOIN (SELECT 'Physics' name,0 opt,50 cq,25 m,25 p,136 code UNION ALL SELECT 'Chemistry',0,50,25,25,137
      UNION ALL SELECT 'Biology',1,50,25,25,138 UNION ALL SELECT 'Higher Mathematics',1,70,30,NULL,139) s
WHERE c.name IN ('Class 9','Class 10') AND c.group_name='Science';

-- Commerce group subjects
INSERT INTO subjects (name, class_id, full_marks, group_name, is_optional, cq_full, mcq_full, subject_code)
SELECT s.name, c.id, 100, 'Commerce', s.opt, 70, 30, s.code
FROM classes c
JOIN (SELECT 'Accounting' name,0 opt,142 code UNION ALL SELECT 'Business Entrepreneurship',0,143
      UNION ALL SELECT 'Finance & Banking',1,144) s
WHERE c.name IN ('Class 9','Class 10') AND c.group_name='Commerce';

-- Arts group subjects
INSERT INTO subjects (name, class_id, full_marks, group_name, is_optional, cq_full, mcq_full, subject_code)
SELECT s.name, c.id, 100, 'Arts', s.opt, 70, 30, s.code
FROM classes c
JOIN (SELECT 'Civics & Citizenship' name,0 opt,140 code UNION ALL SELECT 'Geography & Environment',0,110
      UNION ALL SELECT 'History of Bangladesh',1,153) s
WHERE c.name IN ('Class 9','Class 10') AND c.group_name='Arts';

-- Guardians
INSERT INTO users (id, role, username, password_hash, name, phone) VALUES
(5,'guardian','g_1','$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.','Salim Khan','01755555555'),
(6,'guardian','g_2','$2a$10$hZeamDAqOYvIa0/vynTNK.F1imVyivOdcaf8PpLRj/WVNmVXOVx0.','Jamal Hossain','01766666666');

-- Sample students
INSERT INTO students (student_code, name, dob, roll, class_id, guardian_id, guardian_name, guardian_phone, father_name, mother_name) VALUES
('48291056','Arif Rahman','2013-05-12',1,1,5,'Salim Khan','01755555555','Salim Khan','Nasima Khan'),
('57382914','Sadia Akter','2013-08-21',2,1,6,'Jamal Hossain','01766666666','Jamal Hossain','Rahima Akter'),
('69483712','Tanim Islam','2013-11-03',3,1,5,'Salim Khan','01755555555','Salim Khan','Ruma Islam'),
('18394627','Nusrat Jahan','2012-02-14',1,4,6,'Jamal Hossain','01766666666','Jamal Hossain','Shirin Akter'),
('92017384','Fahim Chowdhury','2012-07-30',2,4,5,'Salim Khan','01755555555','Salim Khan','Mita Chowdhury'),
('30481927','Rakib Hasan','2010-03-15',1,10,5,'Salim Khan','01755555555','Nasir Uddin','Ayesha Begum'),
('75839201','Tasnim Rahman','2010-07-22',2,10,6,'Jamal Hossain','01766666666','Kamal Rahman','Rehana Rahman');

-- Teacher assignments: rahim -> class 6A subjects, karim -> class 7A, salma -> class 9 Science
UPDATE subjects SET teacher_id=2 WHERE class_id=1;
UPDATE subjects SET teacher_id=3 WHERE class_id=4;
UPDATE subjects SET teacher_id=4 WHERE class_id=10;

INSERT INTO activity_log (user_id, action, detail) VALUES (1, 'seed_v5', 'Clean academic structure created');