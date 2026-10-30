-- Early-departure counters are written by attendance_v2.rebuildSummary().
ALTER TABLE attendance_summary
  ADD COLUMN IF NOT EXISTS early_departure_with_leave INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS early_departure_no_leave INT NOT NULL DEFAULT 0;
