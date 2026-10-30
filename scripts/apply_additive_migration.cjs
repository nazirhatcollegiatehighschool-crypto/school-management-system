'use strict';
// Apply one reviewed, add-only migration to the configured database.
// PostgreSQL runs in a single transaction and verifies row counts before commit.
// MySQL/MariaDB DDL auto-commits, so the migration files are written to be
// idempotent and safe to rerun.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const dotenv = require(path.join(root, 'backend', 'node_modules', 'dotenv'));
dotenv.config({ path: path.join(root, 'backend', '.env'), quiet: true });
const scriptName = process.argv[2] || '20261030_profile_attendance_workflows.sql';
const isMysql = /^mysql:\/\//i.test(process.env.DATABASE_URL || '');
if (!process.env.DATABASE_URL || (!isMysql && !/^postgres(?:ql)?:\/\//i.test(process.env.DATABASE_URL))) {
  throw new Error('DATABASE_URL must be a PostgreSQL or MySQL URL.');
}
const migrationPath = path.join(root, 'backend', 'migrations', isMysql ? 'mysql' : 'postgres', scriptName);
const sql = fs.readFileSync(migrationPath, 'utf8');
const forbidden = [
  { re: /\bDROP\s+TABLE\b/i, label: 'DROP TABLE' },
  { re: /\bTRUNCATE\b/i, label: 'TRUNCATE' },
  { re: /\bDELETE\s+FROM\b/i, label: 'DELETE FROM' },
  { re: /\bALTER\s+TABLE\b[\s\S]*?\bDROP\s+COLUMN\b/i, label: 'DROP COLUMN' },
];
for (const rule of forbidden) if (rule.re.test(sql)) throw new Error(`Refusing migration: ${rule.label} is not add-only.`);

const REQUIRED = {
  tables: ['attendance_access_requests', 'student_profile_edit_requests', 'student_uniform_reports', 'teacher_notification_reads'],
  columns: [
    ['students', 'guardian_profile_locked_at'], ['students', 'class10_start_year'], ['students', 'is_irregular'],
    ['users', 'teacher_dob'], ['users', 'teacher_degree'], ['notifications', 'target_user_id'],
    ['attendance_delegation', 'expires_at_epoch'],
  ],
};

async function postgresRun() {
  const { Client } = require(path.join(root, 'backend', 'node_modules', 'pg'));
  const client = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 15000 });
  await client.connect();
  try {
    const before = await client.query("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename");
    const names = before.rows.map(r => r.tablename);
    const counts = {};
    for (const t of names) {
      const r = await client.query(`SELECT COUNT(*)::bigint AS n FROM public."${t.replace(/"/g, '""')}"`);
      counts[t] = Number(r.rows[0].n);
    }
    await client.query('BEGIN');
    await client.query("SET LOCAL lock_timeout = '20s'");
    await client.query(sql);
    const checks = {};
    for (const t of REQUIRED.tables) {
      const r = await client.query("SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=$1", [t]);
      checks[`table:${t}`] = r.rowCount === 1;
    }
    for (const [t, c] of REQUIRED.columns) {
      const r = await client.query("SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=$1 AND column_name=$2", [t, c]);
      checks[`column:${t}.${c}`] = r.rowCount === 1;
    }
    const missing = Object.entries(checks).filter(([, ok]) => !ok).map(([k]) => k);
    if (missing.length) throw new Error(`Required objects missing after migration: ${missing.join(', ')}`);
    const rowDiffs = [];
    for (const t of names) {
      const r = await client.query(`SELECT COUNT(*)::bigint AS n FROM public."${t.replace(/"/g, '""')}"`);
      if (Number(r.rows[0].n) !== counts[t]) rowDiffs.push(`${t}: ${counts[t]} -> ${Number(r.rows[0].n)}`);
    }
    if (rowDiffs.length) throw new Error(`Row counts changed; rolling back: ${rowDiffs.join('; ')}`);
    const after = await client.query("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename");
    await client.query('COMMIT');
    return { dialect: 'postgres', statements: sql.split(';').filter(s => s.trim()).length, existingTables: names.length, newTables: after.rows.map(r => r.tablename).filter(t => !names.includes(t)), rowsPreserved: names.length, checks: Object.keys(checks).length };
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch {}
    throw error;
  } finally { await client.end(); }
}

async function mysqlRun() {
  const mysql = require(path.join(root, 'backend', 'node_modules', 'mysql2', 'promise'));
  const url = new URL(process.env.DATABASE_URL);
  const conn = await mysql.createConnection({
    host: url.hostname, port: Number(url.port || 3306), user: decodeURIComponent(url.username),
    password: decodeURIComponent(url.password), database: decodeURIComponent(url.pathname.replace(/^\//, '')),
    charset: 'utf8mb4', multipleStatements: true,
  });
  try {
    const [before] = await conn.query("SELECT table_name AS t FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE'");
    const names = before.map(r => r.t);
    const counts = {};
    for (const t of names) { const [r] = await conn.query(`SELECT COUNT(*) AS n FROM \`${t}\``); counts[t] = Number(r[0].n); }
    await conn.query(sql);
    const missing = [];
    for (const t of REQUIRED.tables) {
      const [r] = await conn.query("SELECT 1 FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name=?", [t]);
      if (!r.length) missing.push(`table:${t}`);
    }
    for (const [t, c] of REQUIRED.columns) {
      const [r] = await conn.query("SELECT 1 FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name=? AND column_name=?", [t, c]);
      if (!r.length) missing.push(`column:${t}.${c}`);
    }
    if (missing.length) throw new Error(`Required objects missing after migration: ${missing.join(', ')}`);
    const rowDiffs = [];
    for (const t of names) { const [r] = await conn.query(`SELECT COUNT(*) AS n FROM \`${t}\``); if (Number(r[0].n) !== counts[t]) rowDiffs.push(`${t}: ${counts[t]} -> ${Number(r[0].n)}`); }
    if (rowDiffs.length) throw new Error(`Row counts changed: ${rowDiffs.join('; ')}`);
    return { dialect: 'mysql', statements: sql.split(';').filter(s => s.trim()).length, existingTables: names.length, rowsPreserved: names.length, checks: REQUIRED.tables.length + REQUIRED.columns.length };
  } finally { await conn.end(); }
}

(async () => {
  const started = Date.now();
  const result = isMysql ? await mysqlRun() : await postgresRun();
  console.log(JSON.stringify({ migration: scriptName, ...result, elapsedMs: Date.now() - started }, null, 2));
})().catch(error => {
  console.error(`Migration failed: ${error.message}`);
  process.exit(1);
});
