-- Religion scope selected when a teacher schedules a religion subject.
-- Existing routines remain unscoped until edited; no student records change.
CREATE TABLE IF NOT EXISTS routine_religions (
  routine_id INTEGER NOT NULL,
  religion VARCHAR(20) NOT NULL,
  PRIMARY KEY (routine_id, religion),
  CONSTRAINT routine_religions_routine_fk
    FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE
);

ALTER TABLE public.results
  ADD COLUMN IF NOT EXISTS section_size INTEGER,
  ADD COLUMN IF NOT EXISTS combined_size INTEGER;
