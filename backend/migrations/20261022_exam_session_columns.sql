-- Required by POST /api/admin/sessions and the canonical exam shell workflow.
-- Safe to run repeatedly on Supabase PostgreSQL.
ALTER TABLE public.exam_events
  ADD COLUMN IF NOT EXISTS exam_kind TEXT DEFAULT 'other';

ALTER TABLE public.exam_events
  ADD COLUMN IF NOT EXISTS year INTEGER NULL;

ALTER TABLE public.exam_events
  ADD COLUMN IF NOT EXISTS promotion_linked INTEGER NOT NULL DEFAULT 0;

-- Mark old rows consistently before the application relies on these values.
UPDATE public.exam_events
SET exam_kind = 'other'
WHERE exam_kind IS NULL;

UPDATE public.exam_events
SET promotion_linked = 0
WHERE promotion_linked IS NULL;
