-- Preserve who deactivated a student and the academic session for the admin archive.
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS deactivated_by INTEGER,
  ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deactivated_session_id INTEGER,
  ADD COLUMN IF NOT EXISTS deactivated_session_name VARCHAR(100);
