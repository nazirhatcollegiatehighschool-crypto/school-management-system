/**
 * Promotion engine v4 — schema alignment migration.
 *
 * Problem found during the audit of the recovered session:
 *  - `student_promotion_status` has NO `eligible` column, but
 *    `POST /admin/promotion/bulk-approve` filters on `sps.eligible`.
 *    In PostgreSQL that reference is an undefined column, so every
 *    approve request fell through to the "skip" branch: eligible
 *    students could never be approved.
 *  - `promotion/calculate` never wrote `target_class_id`, so
 *    `POST /admin/promotion/execute` grouped by a NULL class id and
 *    could not move anybody to the next class.
 *
 * This migration is additive and idempotent:
 *  1. adds the missing `eligible` boolean column (default false)
 *  2. backfills it from the existing `status` column
 *  3. adds a CHECK-free index for the bulk-approve lookup
 *
 * It never drops or rewrites existing promotion history.
 */
require('dotenv').config({ path: __dirname + '/.env' });
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DB_SSL === 'false' ? false : { rejectUnauthorized: false },
});

async function main() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1. Add `eligible` if missing.
    const { rows: col } = await client.query(
      `SELECT column_name FROM information_schema.columns
        WHERE table_schema='public' AND table_name='student_promotion_status'
          AND column_name='eligible'`
    );
    if (col.length === 0) {
      await client.query(
        `ALTER TABLE student_promotion_status
            ADD COLUMN eligible BOOLEAN NOT NULL DEFAULT FALSE`
      );
      console.log('+ column student_promotion_status.eligible added');
    } else {
      console.log('= column student_promotion_status.eligible already exists');
    }

    // 2. Backfill from the authoritative `status` column.
    const { rowCount: backfilled } = await client.query(
      `UPDATE student_promotion_status
          SET eligible = (status IN ('eligible','conditional','approved','promoted'))
        WHERE eligible IS DISTINCT FROM (status IN ('eligible','conditional','approved','promoted'))`
    );
    console.log(`~ backfilled eligible for ${backfilled} row(s)`);

    // 3. Index that supports the bulk-approve existence check.
    await client.query(
      `CREATE INDEX IF NOT EXISTS idx_student_promo_status_eligible
         ON student_promotion_status(target_session_id, eligible)`
    );
    console.log('= index idx_student_promo_status_eligible ready');

    await client.query('COMMIT');
    console.log('migration OK');
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('migration FAILED:', e.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
