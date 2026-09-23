require('dotenv').config();
const { Pool } = require('pg');

(async () => {
  const client = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.DB_SSL === 'false' ? false : { rejectUnauthorized: false } });
  const conn = await client.connect();
  try {
    await conn.query(`ALTER TABLE students ADD COLUMN IF NOT EXISTS section VARCHAR(20) DEFAULT NULL`);
    await conn.query(`ALTER TABLE promotion_history ADD COLUMN IF NOT EXISTS admin_note VARCHAR(255) DEFAULT NULL`);
    await conn.query(`ALTER TABLE students ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'active'`);
    const r = await conn.query(
      `SELECT column_name FROM information_schema.columns
        WHERE table_name IN ('students','promotion_history')
          AND column_name IN ('section','admin_note','status') ORDER BY table_name, column_name`
    );
    console.log('phase_d columns present:', r.rows.map(c => c.column_name).join(', ') || 'NONE');
    await conn.query(
      `CREATE TABLE IF NOT EXISTS promotion_runs (
        id SERIAL PRIMARY KEY,
        run_type VARCHAR(50) NOT NULL,
        run_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )`
    );
    await conn.query(`INSERT INTO promotion_runs (run_type) VALUES ('phase_d_schema')`);
    console.log('phase_d_schema_migration_recorded');
  } finally {
    conn.release();
    await client.end();
  }
})().catch(e => { console.error(e); process.exit(1); });
