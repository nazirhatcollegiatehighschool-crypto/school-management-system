-- Early-departure counters are written by attendance_v2.rebuildSummary().
ALTER TABLE public.attendance_summary
  ADD COLUMN IF NOT EXISTS early_departure_with_leave INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS early_departure_no_leave INTEGER NOT NULL DEFAULT 0;
