CREATE TABLE IF NOT EXISTS public.guardian_sessions (
  guardian_id INTEGER PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  session_id VARCHAR(64),
  last_login_at TIMESTAMPTZ,
  last_seen_at TIMESTAMPTZ,
  logout_at TIMESTAMPTZ,
  last_logout_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_guardian_sessions_last_seen
  ON public.guardian_sessions (last_seen_at DESC);
