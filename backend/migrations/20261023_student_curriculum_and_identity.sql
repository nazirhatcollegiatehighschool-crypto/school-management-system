-- PostgreSQL/Supabase migration for the student curriculum and identity flow.
-- Idempotent so it can be applied before or after app instances warm up.
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS birth_cert_placeholder BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS compulsory_subject VARCHAR(120),
  ADD COLUMN IF NOT EXISTS receives_scholarship BOOLEAN NOT NULL DEFAULT FALSE;

-- Keep missing government IDs blank; never synthesize number-shaped IDs.
-- The explicit flag lets screens label legacy placeholder records as such.
UPDATE public.students
   SET birth_cert_placeholder = TRUE
 WHERE birth_cert_no IS NULL OR BTRIM(birth_cert_no) = '';

UPDATE public.students SET religion='Hinduism'
 WHERE LOWER(BTRIM(religion))='hindu';
UPDATE public.students SET religion='Christianity'
 WHERE LOWER(BTRIM(religion))='christian';
UPDATE public.students SET religion='Buddhism'
 WHERE LOWER(BTRIM(religion)) IN ('buddhist','buddha');
