const fs = require('fs');
const path = require('path');
const pool = require('./db');

async function run() {
  const sqlPath = path.join(__dirname, 'schema_optimized.sql');
  let sql = fs.readFileSync(sqlPath, 'utf8');
  // Strip line comments but keep CREATE/INSERT statements
  sql = sql.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');
  const statements = sql.split(';').map(s => s.trim()).filter(s => s && s.toUpperCase().indexOf('SET FOREIGN_KEY_CHECKS') === -1);
  console.log(`Applying ${statements.length} statements...`);
  let ok = 0, fail = 0;
  for (const stmt of statements) {
    try {
      await pool.query(stmt);
      ok++;
      console.log(`  [${ok}/${statements.length}] OK: ${stmt.slice(0, 80).replace(/\s+/g, ' ')}`);
    } catch (e) {
      if (e.code === 'ER_DUP_ENTRY' || e.code === '23505' || /already exists|Duplicate/i.test(e.message)) { ok++; console.log(`  [${ok}/${statements.length}] SKIP (exists): ${stmt.slice(0, 60).replace(/\s+/g, ' ')}`); continue; }
      fail++;
      console.error(`  FAIL: ${e.message.slice(0, 300)}\n  SQL: ${stmt.slice(0, 300)}`);
    }
  }
  console.log(`Done: ${ok} ok, ${fail} failed`);
  await pool.end();
  process.exit(fail ? 1 : 0);
}
run().catch(e => { console.error(e); process.exit(1); });
