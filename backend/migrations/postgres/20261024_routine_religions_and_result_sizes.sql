-- PostgreSQL/Supabase counterpart to ../mysql/20261024_routine_religions.sql.
-- Apply only after a restorable backup has been verified and on staging first.
CREATE TABLE IF NOT EXISTS routine_religions (
  routine_id INTEGER NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  religion VARCHAR(20) NOT NULL,
  PRIMARY KEY (routine_id, religion)
);

ALTER TABLE results
  ADD COLUMN IF NOT EXISTS section_size INTEGER NULL;

ALTER TABLE results
  ADD COLUMN IF NOT EXISTS combined_size INTEGER NULL;
