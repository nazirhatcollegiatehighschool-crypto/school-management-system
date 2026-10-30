-- ON CONFLICT (dedup_key) in the notification code requires a real unique
-- index. Existing rows use NULL keys, so this is safe and non-destructive.
CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_dedup
  ON public.notifications(dedup_key);
