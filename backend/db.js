require('dotenv').config();

// ------------------------------------------------------------------
// Dual-driver DB layer: PostgreSQL (Supabase/prod) or local MySQL/MariaDB.
// Set DATABASE_URL=mysql://user:pass@host:port/dbname for local mode.
// Route code stays in mysql2 style (`?` placeholders, [rows] destructure,
// insertId/affectedRows) in BOTH modes.
//  - pg mode: existing MySQL->PG translation (unchanged).
//  - mysql mode: direct mysql2 pool + PG-ism normalization (ILIKE->LIKE,
//    ON CONFLICT->ON DUPLICATE KEY, IS [NOT] DISTINCT FROM<=>>, $n->?).
// ------------------------------------------------------------------

const isMysql = /^mysql:\/\//i.test(process.env.DATABASE_URL || '');

function pgToMysql(sql) {
  // $n placeholders (routine_alerts) -> ? in numeric order
  sql = sql.replace(/\$(\d+)/g, '?');
  // ILIKE -> LIKE (utf8mb4_unicode_ci comparisons are case-insensitive)
  sql = sql.replace(/\bILIKE\b/gi, 'LIKE');
  // IS [NOT] DISTINCT FROM -> <=> / NOT <=>
  sql = sql.replace(/(\S+)\s+IS\s+NOT\s+DISTINCT\s+FROM\s+(\S+)/gi, '$1 <=> $2');
  sql = sql.replace(/(\S+)\s+IS\s+DISTINCT\s+FROM\s+(\S+)/gi, 'NOT ($1 <=> $2)');
  // ON CONFLICT (..) DO NOTHING -> INSERT IGNORE
  if (/\bDO\s+NOTHING\b/i.test(sql)) {
    sql = sql.replace(/^\s*insert\s+into/i, 'INSERT IGNORE INTO');
    sql = sql.replace(/\s*ON\s+CONFLICT\b.*?DO\s+NOTHING/i, '');
  }
  // ON CONFLICT (..) DO UPDATE SET a=EXCLUDED.a -> ON DUPLICATE KEY UPDATE a=VALUES(a)
  sql = sql.replace(/\bON\s+CONFLICT\s*\([^)]*\)\s*DO\s+UPDATE\s+SET\b/gi, 'ON DUPLICATE KEY UPDATE');
  sql = sql.replace(/(\w+)\s*=\s*EXCLUDED\.(\w+)/g, '$1=VALUES($2)');
  return sql;
}

let pool;
if (isMysql) {
  const mysql = require('mysql2/promise');
  const u = new URL(process.env.DATABASE_URL);
  const myPool = mysql.createPool({
    host: u.hostname,
    port: Number(u.port) || 3306,
    user: decodeURIComponent(u.username),
    password: decodeURIComponent(u.password || ''),
    database: decodeURIComponent(u.pathname || '').replace(/^\//, '') || undefined,
    waitForConnections: true,
    connectionLimit: (process.env.DB_POOL_MAX && parseInt(process.env.DB_POOL_MAX)) || 10,
    charset: 'utf8mb4',
    timezone: 'Z',
    dateStrings: false,
  });
  // mysql2 returns BIGINT/DECIMAL as string; normalize plain integer strings
  // to numbers for the shapes apps expect (matches pg int8 parser).
  // Leading-zero strings (phones, codes) are NEVER converted.
  const normRows = (rows) => {
    if (Array.isArray(rows)) {
      for (const r of rows) {
        for (const k of Object.keys(r)) {
          const v = r[k];
          if (typeof v === 'string' && /^-?(0|[1-9]\d{0,14})$/.test(v) && !/^0\d/.test(v)) r[k] = parseInt(v, 10);
        }
      }
    }
    return rows;
  };
  pool = {
    async query(sql, params) {
      let rows, fields;
      try {
        [rows, fields] = await myPool.query(pgToMysql(sql), params || []);
      } catch (e) { throw asPgError(e); }
      if (/^\s*insert\s+/i.test(sql)) {
        return [{ fieldCount: 0, affectedRows: rows.affectedRows || 0, insertId: rows.insertId || 0, info: '' }, null];
      }
      if (/^\s*(update|delete)\b/i.test(sql)) {
        return [{ affectedRows: rows.affectedRows || 0, changedRows: rows.changedRows || 0, fieldCount: 0, info: '' }, null];
      }
      return [normRows(rows), fields || null];
    },
    async getConnection() {
      const conn = await myPool.getConnection();
      const run = async (sql, params) => {
        let rows, fields;
        try {
          [rows, fields] = await conn.query(pgToMysql(sql), params || []);
        } catch (e) { throw asPgError(e); }
        if (/^\s*insert\s+/i.test(sql)) {
          return [{ fieldCount: 0, affectedRows: rows.affectedRows || 0, insertId: rows.insertId || 0, info: '' }, null];
        }
        if (/^\s*(update|delete)\b/i.test(sql)) {
          return [{ affectedRows: rows.affectedRows || 0, changedRows: rows.changedRows || 0, fieldCount: 0, info: '' }, null];
        }
        return [normRows(rows), fields || null];
      };
      return {
        query: run,
        beginTransaction: () => conn.beginTransaction(),
        commit: () => conn.commit(),
        rollback: () => conn.rollback(),
        release: () => conn.release(),
      };
    },
    end: () => myPool.end(),
  };
  pool._mysql = myPool;
  pool._transform = pgToMysql;
  pool._mode = 'mysql';
  module.exports = pool;
  return;
}

// Map MySQL driver errors onto the PG codes the route layer already
// handles, so `e.code === '23505'` (unique violation) works in both modes.
// Original code preserved on err.mysqlCode.
function asPgError(e) {
  if (e && (e.code === 'ER_DUP_ENTRY' || e.errno === 1062)) {
    e.mysqlCode = e.code;
    e.code = '23505';
  }
  return e;
}
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

pool = {
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