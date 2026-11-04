require('dotenv').config();
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
const { Pool } = require('pg');

function loadEnvFile(fileName) {
  const filePath = path.join(__dirname, '..', fileName);
  if (!fs.existsSync(filePath)) return;
  const parsed = require('dotenv').parse(fs.readFileSync(filePath));
  for (const [key, value] of Object.entries(parsed)) {
    if (process.env[key] == null || key === 'DATABASE_URL') process.env[key] = value;
  }
}

function mysqlValue(value) {
  if (value == null) return null;
  if (typeof value === 'bigint') return String(value);
  if (Array.isArray(value) || (typeof value === 'object' && !(value instanceof Date) && !Buffer.isBuffer(value))) {
    return JSON.stringify(value);
  }
  return value;
}

async function run() {
  const cloudValues = fs.existsSync(path.join(__dirname, '..', '.env.supabase'))
    ? require('dotenv').parse(fs.readFileSync(path.join(__dirname, '..', '.env.supabase')))
    : {};
  const localValues = fs.existsSync(path.join(__dirname, '..', '.env.localdb'))
    ? require('dotenv').parse(fs.readFileSync(path.join(__dirname, '..', '.env.localdb')))
    : {};
  const rootValues = fs.existsSync(path.join(__dirname, '..', '.env'))
    ? require('dotenv').parse(fs.readFileSync(path.join(__dirname, '..', '.env')))
    : {};

  const candidates = [
    cloudValues.DATABASE_URL,
    rootValues.DATABASE_URL,
    cloudValues.DIRECT_URL,
    rootValues.DIRECT_URL,
    process.env.BACKUP_DATABASE_URL,
    process.env.DATABASE_URL,
  ].filter(Boolean).filter((value, index, list) => list.indexOf(value) === index);
  const localUrl = localValues.DATABASE_URL || process.env.MYSQL_SYNC_URL;
  if (!candidates.length) throw new Error('Supabase DATABASE_URL is not configured');
  if (!localUrl) throw new Error('Local DATABASE_URL is not configured');

  let cloud = null;
  let selectedCloudUrl = null;
  let cloudError = null;
  for (const candidate of candidates) {
    const pool = new Pool({
      connectionString: candidate,
      ssl: candidate.includes('sslmode=disable') ? false : { rejectUnauthorized: false },
      connectionTimeoutMillis: 15000,
      query_timeout: 30000,
    });
    try {
      await pool.query('SELECT 1');
      cloud = pool;
      selectedCloudUrl = candidate;
      break;
    } catch (error) {
      cloudError = error;
      await pool.end();
    }
  }
  if (!cloud) throw cloudError || new Error('Supabase connection failed');
  const u = new URL(localUrl);
  const localPool = mysql.createPool({
    host: u.hostname,
    port: Number(u.port) || 3306,
    user: decodeURIComponent(u.username),
    password: decodeURIComponent(u.password || ''),
    database: decodeURIComponent(u.pathname).replace(/^\//, ''),
    waitForConnections: true,
    connectionLimit: 4,
    timezone: 'Z',
  });

  let tableCount = 0;
  let rowCount = 0;
  try {
    const tableResult = await cloud.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema='public' AND table_type='BASE TABLE'
      ORDER BY table_name
    `);

    await localPool.query('SET FOREIGN_KEY_CHECKS=0');
    for (const { table_name: table } of tableResult.rows) {
      const [tables] = await localPool.query('SHOW TABLES');
      const tableKey = tables.length ? Object.keys(tables[0])[0] : null;
      const exists = tableKey && tables.some(r => r[tableKey] === table);
      if (!exists) continue;

      const [columns] = await localPool.query(`SHOW COLUMNS FROM \`${table.replace(/`/g, '')}\``);
      const localColumns = new Set(columns.map(c => c.Field));
      const cloudColumnsResult = await cloud.query(`
        SELECT column_name FROM information_schema.columns
        WHERE table_schema='public' AND table_name=$1
        ORDER BY ordinal_position
      `, [table]);
      const common = cloudColumnsResult.rows.map(r => r.column_name).filter(c => localColumns.has(c));
      if (!common.length) continue;

      const pkResult = await cloud.query(`
        SELECT k.column_name
        FROM information_schema.table_constraints t
        JOIN information_schema.key_column_usage k
          ON k.constraint_name=t.constraint_name AND k.table_schema=t.table_schema AND k.table_name=t.table_name
        WHERE t.table_schema='public' AND t.table_name=$1 AND t.constraint_type='PRIMARY KEY'
        ORDER BY k.ordinal_position
      `, [table]);
      let pk = pkResult.rows.length === 1 ? pkResult.rows[0].column_name : (common.includes('id') ? 'id' : null);
      if (!pk || !common.includes(pk)) continue;

      const { rows } = await cloud.query(
        `SELECT ${common.map(c => '"' + c.replace(/"/g, '""') + '"').join(',')} FROM "${table.replace(/"/g, '""')}"`
      );

      // Replace the table snapshot instead of upserting row-by-row. This
      // prevents stale local unique keys from colliding with cloud data.
      await localPool.query(`DELETE FROM \`${table.replace(/`/g, '')}\``);
      for (const row of rows) {
          const values = common.map(c => mysqlValue(row[c]));
          const placeholders = values.map(() => '?').join(',');
          const sql = `INSERT INTO \`${table.replace(/`/g, '')}\` (${common.map(c => `\`${c.replace(/`/g, '')}\``).join(',')}) VALUES (${placeholders})`;
          try {
            await localPool.query(sql, values);
          } catch (error) {
            throw new Error(`${table}: ${error.message}; SQL ${sql}`);
          }
          rowCount++;
      }

      const cloudIds = new Set(rows.map(r => String(r[pk])));
      const [localIds] = await localPool.query(`SELECT \`${pk.replace(/`/g, '')}\` AS pk FROM \`${table.replace(/`/g, '')}\``);
      const extras = localIds.map(r => r.pk).filter(id => !cloudIds.has(String(id)));
      for (let i = 0; i < extras.length; i += 500) {
        const batch = extras.slice(i, i + 500);
        await localPool.query(
          `DELETE FROM \`${table.replace(/`/g, '')}\` WHERE \`${pk.replace(/`/g, '')}\` IN (${batch.map(() => '?').join(',')})`,
          batch
        );
      }
      try {
        await localPool.query(`ALTER TABLE \`${table.replace(/`/g, '')}\` AUTO_INCREMENT=1`);
      } catch (_) {}
      tableCount++;
    }
    await localPool.query('SET FOREIGN_KEY_CHECKS=1');
    console.log(JSON.stringify({ ok: true, tables: tableCount, rows: rowCount, timestamp: new Date().toISOString() }));
  } finally {
    await cloud.end();
    await localPool.end();
  }
}

if (require.main === module) {
  run().then(() => process.exit(0)).catch(err => {
    console.error(JSON.stringify({ ok: false, error: err.message, timestamp: new Date().toISOString() }));
    process.exit(1);
  });
}

module.exports = { run };
