-- Store the Admin's per-event, per-class subject-specific grace choices.
CREATE TABLE IF NOT EXISTS event_promotion_grace (
  event_id INTEGER NOT NULL REFERENCES exam_events(id) ON DELETE CASCADE,
  class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  granted_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, class_id, subject_id)
);

CREATE INDEX IF NOT EXISTS ix_event_promotion_grace_class
  ON event_promotion_grace (class_id, event_id);
