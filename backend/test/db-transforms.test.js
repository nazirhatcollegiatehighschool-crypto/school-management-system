const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const pool = require('../db');

test('PostgreSQL translates MySQL INSERT IGNORE into conflict-safe insert', () => {
  const sql = pool._transform(
    'INSERT IGNORE INTO exam_event_classes (event_id,class_id) VALUES (?,?)'
  );
  assert.equal(
    sql,
    'INSERT INTO exam_event_classes (event_id,class_id) VALUES ($1,$2) ON CONFLICT DO NOTHING'
  );
});

test('PostgreSQL translates MySQL DATE_SUB for supported interval units', () => {
  const sql = pool._transform(
    'SELECT created_at > DATE_SUB(NOW(), INTERVAL 1 DAY) AS recent FROM homework WHERE id=?'
  );
  assert.match(sql, /created_at > \(NOW\(\) - make_interval\(secs => 1 \* CASE 'DAY'/);
  assert.match(sql, /WHERE id=\$1$/);
  assert.doesNotMatch(sql, /DATE_SUB/i);
});

test('MySQL translates PostgreSQL date casts and month-window intervals', () => {
  const sql = pool._transformMysql(
    "SELECT * FROM attendance WHERE date >= ?::date AND date < (?::date + INTERVAL '1 month')"
  );
  assert.equal(
    sql,
    'SELECT * FROM attendance WHERE date >= CAST(? AS DATE) AND date < DATE_ADD(CAST(? AS DATE), INTERVAL 1 MONTH)'
  );
});

test('MySQL translates EXCLUDED values inside conditional upserts', () => {
  const sql = pool._transformMysql(
    `INSERT INTO student_daily_reports (homework_status,uniform_brought) VALUES (?,?)
     ON CONFLICT (student_id,report_date) DO UPDATE SET
       homework_status=EXCLUDED.homework_status,
       uniform_brought=CASE WHEN ? THEN EXCLUDED.uniform_brought ELSE student_daily_reports.uniform_brought END`
  );
  assert.match(sql, /ON DUPLICATE KEY UPDATE/);
  assert.match(sql, /homework_status=VALUES\(homework_status\)/);
  assert.match(sql, /CASE WHEN \? THEN VALUES\(uniform_brought\)/);
  assert.doesNotMatch(sql, /EXCLUDED\./i);
});

test('ordinary PostgreSQL conflict clauses and quoted question marks are preserved', () => {
  const sql = pool._transform(
    "INSERT INTO app_settings (setting_key,setting_value) VALUES (?, '?') ON CONFLICT (setting_key) DO NOTHING"
  );
  assert.equal(
    sql,
    "INSERT INTO app_settings (setting_key,setting_value) VALUES ($1, '?') ON CONFLICT (setting_key) DO NOTHING"
  );
});

test('production authentication fails closed when JWT_SECRET is missing', () => {
  const script = `
    process.env.NODE_ENV = 'production';
    process.env.JWT_SECRET = '';
    const assert = require('node:assert/strict');
    const { requireJwtConfiguration, signToken } = require('./middleware/auth');
    let status;
    const res = { status(code) { status = code; return this; }, json() { return this; } };
    requireJwtConfiguration({}, res, () => { throw new Error('unexpected next'); });
    assert.equal(status, 503);
    assert.throws(() => signToken({ id: 1 }), { code: 'JWT_SECRET_MISSING' });
  `;
  const result = spawnSync(process.execPath, ['-e', script], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, NODE_ENV: 'production', JWT_SECRET: '' },
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
});
