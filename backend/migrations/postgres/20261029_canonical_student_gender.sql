-- Standardize legacy free-text gender spellings without changing unknown values.
-- Safe to rerun; backend reads and new writes also normalize these values.
UPDATE public.students
SET gender = 'Female'
WHERE LOWER(TRIM(gender)) IN ('female', 'femal', 'femail', 'females');
