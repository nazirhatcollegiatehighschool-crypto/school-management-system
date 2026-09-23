require('dotenv').config();
const { Pool, types } = require('pg');

// MySQL returns BIGINT (COUNT/SUM) as a JS number; pg returns int8 as string.
// Override so JSON output matches the MySQL-era shapes the apps expect.
types.setTypeParser(20, val => (val === null ? null : parseInt(val, 10))); // int8 -> number

// ------------------------------------------------------------------
// MySQL -> PostgreSQL compatibility layer.
// Exposes a mysql2/promise-like `pool` so the existing route code
// (pool.query, [rows] destructuring, `?` placeholders, conn.query,
// beginTransaction/commit/rollback, insertId) keeps working unchanged.
// ------------------------------------------------------------------

const pgPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DB_SSL === 'false' ? false : { rejectUnauthorized: false },
  max: (process.env.DB_POOL_MAX && parseInt(process.env.DB_POOL_MAX)) || 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 15000,
  application_name: 'school-backend'
});

// MySQL `?` placeholders -> PostgreSQL `$n`
function transformSql(sql) {
  // 1. strip MySQL backticks (identifiers are all lowercase, safe unquoted)
  sql = sql.replace(/`/g, '');
  // 2. rewrite MySQL date/time SQL functions to PG
  sql = sql.replace(/DATE_ADD\(NOW\(\),\s*INTERVAL\s+(\d+)\s+(MINUTE|HOUR|DAY|SECOND)\)/gi,
    (m, num, unit) => `(NOW() + make_interval(secs => ${num} * CASE '${unit}' WHEN 'SECOND' THEN 1 WHEN 'MINUTE' THEN 60 WHEN 'HOUR' THEN 3600 WHEN 'DAY' THEN 86400 ELSE 0 END))`);
  sql = sql.replace(/CURDATE\(\)/gi, 'CURRENT_DATE');
  // 2b. mysql2 array-expansion: `IN (?)` / `NOT IN (?)` become ANY/ALL-predicates.
  //     `\u0007` acts as a numbered placeholder in the pass below.
  sql = sql.replace(/\bNOT\s+IN\s*\(\s*\?\s*\)/gi, '<> ALL(\u0007)');
  sql = sql.replace(/\bIN\s*\(\s*\?\s*\)/gi, '= ANY(\u0007)');
  // 3. convert `?` positional params (outside quotes) to $1..$n
  //    `? IS NULL` / `? IS NOT NULL` get `CAST($n AS text)` so PG can infer
  //    a parameter type (a bare $n only used in IS NULL is 'could not determine')
  let n = 0;
  let out = '';
  let inStr = false;
  for (let i = 0; i < sql.length; i++) {
    const ch = sql[i];
    if (ch === "'") {
      // handle escaped '' (SQL standard doubling) and \' (MySQL style)
      if (i + 1 < sql.length && sql[i + 1] === "'") { out += "''"; i++; continue; }
      if (i > 0 && sql[i - 1] === '\\') { out += ch; continue; }
      inStr = !inStr;
      out += ch;
    } else if ((ch === '?' || ch === '\u0007') && !inStr) {
      n++;
      // lookahead: `? IS NULL` / `? IS NOT NULL`
      const rest = sql.slice(i + 1);
      if (/^\s+IS\s+(NOT\s+)?NULL/i.test(rest)) {
        out += 'CAST($' + n + ' AS text)';
      } else {
        out += '$' + n;
      }
    } else {
      out += ch;
    }
  }
  return out;
}

const isInsertRE = /^\s*insert\s+into/i;
const hasReturningRE = /\breturning\b/i;

async function exec(client, sql, params) {
  const text = transformSql(sql);
  const isInsert = isInsertRE.test(text);
  const willReturn = hasReturningRE.test(text);
  const selectedText = isInsert && !willReturn ? text + ' RETURNING *' : text;
  const result = await client.query({ text: selectedText, values: params || [] });
  // mysql2 shape: SELECT -> [rows, fields]; DML -> [ResultSetHeader, fields]
  if (isInsert) {
    return [{
      fieldCount: 0,
      affectedRows: result.rowCount,
      insertId: result.rows && result.rows[0] ? result.rows[0].id : 0,
      info: ''
    }, null];
  }
  if (/^\s*(update|delete)\b/i.test(text)) {
    return [{ affectedRows: result.rowCount, changedRows: result.rowCount, fieldCount: 0, info: '' }, null];
  }
  return [result.rows, result.fields || null];
}

const pool = {
  async query(sql, params) { return exec(pgPool, sql, params); },
  async getConnection() {
    const client = await pgPool.connect();
    const conn = {
      query: (sql, params) => exec(client, sql, params),
      beginTransaction: () => client.query('BEGIN'),
      commit: () => client.query('COMMIT'),
      rollback: () => client.query('ROLLBACK'),
      release: () => client.release()
    };
    return conn;
  },
  end: () => pgPool.end()
};
pool._pg = pgPool;
pool._transform = transformSql;

module.exports = pool;