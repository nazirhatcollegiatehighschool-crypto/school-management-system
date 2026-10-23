-- Special Model Test is also one canonical exam per academic year.
DROP INDEX IF EXISTS public.uq_event_kind_year;
CREATE UNIQUE INDEX uq_event_kind_year
  ON public.exam_events (exam_kind, year)
  WHERE exam_kind IN ('half_yearly','annual','pretest','test','special_model_test')
    AND year IS NOT NULL;
