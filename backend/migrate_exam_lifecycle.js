// Exam-lifecycle migration (idempotent): event kind/year/publish columns,
// mark edit-request workflow table, one-canonical-event-per-year guard.
// Run: node migrate_exam_lifecycle.js   (uses backend .env DATABASE_URL)
require('dotenv').config();
const pool = require('./db');

const STMTS = [
  `ALTER TABLE exam_events ADD COLUMN IF NOT EXISTS exam_kind TEXT DEFAULT 'other'`,
  `ALTER TABLE exam_events ADD COLUMN IF NOT EXISTS year INT NULL`,
  `ALTER TABLE exam_events ADD COLUMN IF NOT EXISTS is_published INT NOT NULL DEFAULT 0`,
  `ALTER TABLE exam_events ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ NULL`,
  `ALTER TABLE exam_events ADD COLUMN IF NOT EXISTS promotion_linked INT NOT NULL DEFAULT 0`,
  `ALTER TABLE exam_events ADD COLUMN IF NOT EXISTS notify_guardians INT NOT NULL DEFAULT 0`,
  `ALTER TABLE exam_events ADD COLUMN IF NOT EXISTS notified_at TIMESTAMPTZ NULL`,
  `CREATE TABLE IF NOT EXISTS mark_edit_requests (
    id SERIAL PRIMARY KEY,
    mark_id INT NOT NULL REFERENCES marks(id) ON DELETE CASCADE,
    student_id INT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    exam_id INT NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
    teacher_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason TEXT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    decided_at TIMESTAMPTZ NULL,
    decided_by INT NULL REFERENCES users(id) ON DELETE SET NULL
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS uq_editreq_pending
   ON mark_edit_requests (mark_id) WHERE status = 'pending'`,
  `DROP INDEX IF EXISTS uq_event_kind_year`,
  `CREATE UNIQUE INDEX IF NOT EXISTS uq_event_kind_year
   ON exam_events (exam_kind, year)
   WHERE exam_kind IN ('half_yearly','annual','pretest','test','special_model_test') AND year IS NOT NULL`,
];

(async () => {
  for (const s of STMTS) {
    try {
      await pool.query(s);
      console.log('OK  ', s.slice(0, 90));
    } catch (e) {
      console.log('FAIL', s.slice(0, 90), '::', e.message);
      process.exitCode = 1;
    }
  }
  const [cols] = await pool.query(
    `SELECT column_name FROM information_schema.columns WHERE table_name='exam_events' ORDER BY ordinal_position`);
  console.log('exam_events cols:', cols.map(c => c.column_name).join(','));
  process.exit(process.exitCode || 0);
})().catch(e => { console.error('MIG ERR', e.message); process.exit(1); });
