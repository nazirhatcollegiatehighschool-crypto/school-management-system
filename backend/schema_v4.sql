USE school_db;

CREATE TABLE IF NOT EXISTS device_tokens (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  role VARCHAR(20) NOT NULL,
  fcm_token TEXT NOT NULL,
  platform VARCHAR(20) DEFAULT 'android',
  active TINYINT(1) NOT NULL DEFAULT 1,
  last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_token (fcm_token(191)),
  KEY idx_user (user_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

ALTER TABLE exams ADD COLUMN status ENUM('draft','published') NOT NULL DEFAULT 'draft';
ALTER TABLE marks ADD COLUMN comment VARCHAR(255) DEFAULT NULL;

UPDATE exams SET status='published' WHERE source='admin';