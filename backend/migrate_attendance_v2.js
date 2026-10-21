/**
 * migrate_attendance_v2.js — idempotent schema for the v2 attendance module.
 *
 * Extends the existing `attendance` table (dual-session FSM) and adds the
 * tables the agreed feature needs: day status/holiday, per-session locks,
 * reopen requests, delegations, audit trail, settings and monthly summaries.
 *
 *   node migrate_attendance_v2.js
 *
 * Safe to run repeatedly (ADD COLUMN IF NOT EXISTS / CREATE ... IF NOT EXISTS).
 */
const pool = require('./db');

const stmts = [
  // ---- attendance: additive columns (session/final_state may already exist) ----
  `ALTER TABLE attendance ADD COLUMN IF NOT EXISTS session varchar(20) DEFAULT 'morning'`,
  `ALTER TABLE attendance ADD COLUMN IF NOT EXISTS final_state varchar(40)`,
  `ALTER TABLE attendance ADD COLUMN IF NOT EXISTS is_escape smallint DEFAULT 0`,
  `ALTER TABLE attendance ADD COLUMN IF NOT EXISTS escape_detected_at timestamptz`,
  `ALTER TABLE attendance ADD COLUMN IF NOT EXISTS override_reason varchar(255)`,
  `ALTER TABLE attendance ADD COLUMN IF NOT EXISTS idem_key varchar(80)`,
  `ALTER TABLE attendance ADD COLUMN IF NOT EXISTS recorded_at timestamptz DEFAULT now()`,
  // status must accept 'leave' too — widen enum->varchar if needed
  `ALTER TABLE attendance ALTER COLUMN status TYPE varchar(20) USING status::text`,
  `CREATE UNIQUE INDEX IF NOT EXISTS uq_att_sds ON attendance(student_id, date, session)`,
  `CREATE UNIQUE INDEX IF NOT EXISTS uq_att_idem ON attendance(idem_key) WHERE idem_key IS NOT NULL`,

  // ---- per class/day status: holiday + occasion + forced-open (off-day) ----
  `CREATE TABLE IF NOT EXISTS attendance_day (
     id serial PRIMARY KEY,
     class_id integer NOT NULL,
     date date NOT NULL,
     is_holiday smallint NOT NULL DEFAULT 0,
     occasion varchar(160),
     open_override smallint NOT NULL DEFAULT 0,
     set_by integer,
     set_at timestamptz DEFAULT now(),
     UNIQUE(class_id, date))`,

  // ---- per session lock/reopen window ----
  `CREATE TABLE IF NOT EXISTS attendance_lock (
     id serial PRIMARY KEY,
     class_id integer NOT NULL,
     date date NOT NULL,
     session varchar(20) NOT NULL,
     locked smallint NOT NULL DEFAULT 0,
     reopen_until timestamptz,
     note varchar(255),
     updated_by integer,
     updated_at timestamptz DEFAULT now(),
     UNIQUE(class_id, date, session))`,

  // ---- teacher reopen requests (admin approves) ----
  `CREATE TABLE IF NOT EXISTS attendance_reopen (
     id serial PRIMARY KEY,
     class_id integer NOT NULL,
     date date NOT NULL,
     session varchar(20) NOT NULL,
     requested_by integer NOT NULL,
     reason varchar(255),
     status varchar(20) NOT NULL DEFAULT 'pending',
     decided_by integer,
     decided_at timestamptz,
     decision_note varchar(255),
     created_at timestamptz DEFAULT now())`,

  // ---- class teacher delegates one day/session to another teacher ----
  `CREATE TABLE IF NOT EXISTS attendance_delegation (
     id serial PRIMARY KEY,
     class_id integer NOT NULL,
     date date NOT NULL,
     session varchar(20) NOT NULL,
     granted_by integer NOT NULL,
     granted_to integer NOT NULL,
     used smallint NOT NULL DEFAULT 0,
     revoked smallint NOT NULL DEFAULT 0,
     created_at timestamptz DEFAULT now(),
     used_at timestamptz)`,

  // ---- audit trail (edits, opens, unlocks, delegation) ----
  `CREATE TABLE IF NOT EXISTS attendance_audit (
     id serial PRIMARY KEY,
     class_id integer,
     date date,
     session varchar(20),
     action varchar(40) NOT NULL,
     detail text,
     actor_id integer,
     created_at timestamptz DEFAULT now())`,

  // ---- settings (threshold %, reminder time) ----
  `CREATE TABLE IF NOT EXISTS attendance_setting (
     key varchar(60) PRIMARY KEY,
     value varchar(255))`,
  `INSERT INTO attendance_setting(key,value) VALUES ('threshold_percent','75') ON CONFLICT (key) DO NOTHING`,
  `INSERT INTO attendance_setting(key,value) VALUES ('reminder_time','10:30') ON CONFLICT (key) DO NOTHING`,

  // ---- per-student monthly summary for fast % reads ----
  `CREATE TABLE IF NOT EXISTS attendance_summary (
     id serial PRIMARY KEY,
     student_id integer NOT NULL,
     year integer NOT NULL,
     month integer NOT NULL,
     present_days integer DEFAULT 0,
     late_days integer DEFAULT 0,
     leave_days integer DEFAULT 0,
     absent_days integer DEFAULT 0,
     school_days integer DEFAULT 0,
     percent numeric(5,2) DEFAULT 0,
     updated_at timestamptz DEFAULT now(),
     UNIQUE(student_id, year, month))`,
];

async function main() {
  let ok = 0, skipped = 0;
  for (const sql of stmts) {
    try {
      await pool.query(sql);
      ok++;
    } catch (e) {
      skipped++;
      console.log('SKIP:', String(e.message).slice(0, 120), '||', sql.slice(0, 70).replace(/\s+/g, ' '));
    }
  }
  // Drop any legacy UNIQUE(student_id, date) constraint that would block a
  // second session row (best-effort — constraint name varies).
  try {
    const [cons] = await pool.query(
      `SELECT conname FROM pg_constraint
       WHERE conrelid = 'attendance'::regclass AND contype = 'u'`);
    for (const c of cons) {
      const name = c.conname;
      const [cols] = await pool.query(
        `SELECT a.attname FROM pg_constraint c
         JOIN unnest(c.conkey) k ON true
         JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k
         WHERE c.conname = ?`, [name]);
      const names = cols.map(x => x.attname).sort().join(',');
      if (names === 'date,student_id') {
        await pool.query(`ALTER TABLE attendance DROP CONSTRAINT "${name}"`);
        console.log('Dropped legacy unique constraint', name);
      }
    }
  } catch (e) { console.log('constraint scan skipped:', e.message); }

  console.log(`\nMigration done: ${ok} applied, ${skipped} skipped.`);
  await pool.end();
}
main().catch(e => { console.error(e); process.exit(1); });
