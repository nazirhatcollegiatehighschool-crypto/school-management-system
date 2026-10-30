-- P5 attendance outcomes such as early_departure_with_leave exceed VARCHAR(20).
-- Widening is additive and preserves existing attendance values.
ALTER TABLE public.attendance
  ALTER COLUMN status TYPE VARCHAR(40)
  USING status::text;
