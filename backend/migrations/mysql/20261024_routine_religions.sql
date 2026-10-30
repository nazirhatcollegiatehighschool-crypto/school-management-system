-- MySQL/MariaDB counterpart. Existing routine rows are preserved and remain
-- unscoped until a religion subject routine is edited.
CREATE TABLE IF NOT EXISTS routine_religions (
  routine_id INT NOT NULL,
  religion VARCHAR(20) NOT NULL,
  PRIMARY KEY (routine_id, religion),
  CONSTRAINT routine_religions_routine_fk
    FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @school_add_section_size = IF(
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='results' AND column_name='section_size'),
  'SELECT 1', 'ALTER TABLE results ADD COLUMN section_size INT NULL'
);
PREPARE school_stmt FROM @school_add_section_size;
EXECUTE school_stmt;
DEALLOCATE PREPARE school_stmt;

SET @school_add_combined_size = IF(
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='results' AND column_name='combined_size'),
  'SELECT 1', 'ALTER TABLE results ADD COLUMN combined_size INT NULL'
);
PREPARE school_stmt FROM @school_add_combined_size;
EXECUTE school_stmt;
DEALLOCATE PREPARE school_stmt;
