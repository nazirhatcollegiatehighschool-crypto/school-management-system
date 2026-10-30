ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS teacher_dob DATE,
  ADD COLUMN IF NOT EXISTS teacher_address VARCHAR(255),
  ADD COLUMN IF NOT EXISTS teacher_blood_group VARCHAR(5),
  ADD COLUMN IF NOT EXISTS teacher_index_number VARCHAR(40),
  ADD COLUMN IF NOT EXISTS teacher_pns_number VARCHAR(40),
  ADD COLUMN IF NOT EXISTS teacher_degree VARCHAR(150),
  ADD COLUMN IF NOT EXISTS teacher_joining_date DATE;
