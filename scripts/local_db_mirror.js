'use strict';
// Supabase (PostgreSQL) -> local MariaDB read-only mirror.
//
// Direction is intentionally one-way: the apps write through the Vercel API to
// Supabase, and this service only *reads* Supabase and replaces the local
// `schooldb` snapshot. It must never be pointed at the local database as a
// write source, otherwise two databases could accept conflicting writes.
const fs = require('node:fs');
const os = require('node:os');
const crypto = require('node:crypto');
const path = require('node:path');
const mysql = require(path.join(__dirname, '..', 'backend', 'node_modules', 'mysql2', 'promise'));
const { Pool } = require(path.join(__dirname, '..', 'backend', 'node_modules', 'pg'));
const dotenv = require(path.join(__dirname, '..', 'backend', 'node_modules', 'dotenv'));
const root = path.resolve(__dirname, '..');
dotenv.config({ path: path.join(root, 'backend', '.env'), quiet: true });
const intervalMs = Math.max(60, Number(process.env.LOCAL_MIRROR_INTERVAL_SECONDS || 300)) * 1000;
const logDir = path.join(root, 'logs');
const logPath = path.join(logDir, 'local_db_mirror.log');
const lockPath = path.join(logDir, 'local_db_mirror.pid');
const oneShot = process.argv.includes('--once');
const checkOnly = process.argv.includes('--check');
const verifyOnly = process.argv.includes('--verify');
const pgUrl = process.env.DATABASE_URL;
if (!pgUrl || !/^postgres(?:ql)?:\/\//i.test(pgUrl)) throw new Error('DATABASE_URL must remain the Supabase PostgreSQL source.');
const pgPool = new Pool({ connectionString: pgUrl, ssl: { rejectUnauthorized: false }, max: 2, connectionTimeoutMillis: 15000 });
const q = v => `\`${String(v).replace(/`/g, '``')}\``;
const p = v => `"${String(v).replace(/"/g, '""')}"`;
function log(message) {
  const line = `[${new Date().toISOString()}] ${message}\n`;
  try {
    fs.mkdirSync(logDir, { recursive: true });
    if (fs.existsSync(logPath) && fs.statSync(logPath).size > 5 * 1024 * 1024) fs.renameSync(logPath, `${logPath}.1`);
  } catch {}
  fs.appendFileSync(logPath, line, 'utf8');
  process.stdout.write(line);
}
function pgType(c, uniqueTextColumns) {
  switch (c.udt_name) {
    case 'int2': return 'SMALLINT';
    case 'int4': return 'INT';
    case 'int8': return 'BIGINT';
    case 'numeric': return `DECIMAL(${Math.min(c.numeric_precision || 12, 65)},${Math.min(c.numeric_scale || 0, 30)})`;
    case 'varchar': return c.character_maximum_length && c.character_maximum_length <= 16383 ? `VARCHAR(${c.character_maximum_length})` : 'LONGTEXT';
    case 'bpchar': return `CHAR(${Math.min(c.character_maximum_length || 1, 255)})`;
    case 'bool': return 'TINYINT(1)';
    case 'date': return 'DATE';
    case 'time': return 'TIME(6)';
    case 'timestamp': case 'timestamptz': return 'DATETIME(3)';
    case 'json': case 'jsonb': return 'JSON';
    case 'bytea': return 'LONGBLOB';
    case 'float4': return 'FLOAT';
    case 'float8': return 'DOUBLE';
    case 'uuid': return 'CHAR(36)';
    case '_text': case '_int2': case '_int4': case '_int8': case '_varchar': return 'JSON';
    case 'text': return uniqueTextColumns.has(`${c.table_name}.${c.column_name}`) ? 'VARCHAR(512)' : 'LONGTEXT';
    default: return 'VARCHAR(255)';
  }
}
function defaultSql(def, autoId) {
  if (autoId) return ' AUTO_INCREMENT';
  if (!def) return '';
  if (/^now\(\)|^CURRENT_TIMESTAMP/i.test(def)) return ' DEFAULT CURRENT_TIMESTAMP(3)';
  if (/^(true|false)$/i.test(def)) return ` DEFAULT ${/^true$/i.test(def) ? '1' : '0'}`;
  if (/^-?\d+(?:\.\d+)?$/.test(def)) return ` DEFAULT ${def}`;
  const str = def.match(/^'((?:[^']|'')*)'::[\w ]+$/);
  if (str) return ` DEFAULT '${str[1].replace(/'/g, "''")}'`;
  return '';
}
function isIntegerType(t) { return ['int2', 'int4', 'int8'].includes(t); }
function valueForMysql(value, column) {
  if (value === null || value === undefined) return null;
  if (Buffer.isBuffer(value)) return value;
  if (value instanceof Date) {
    const pad = n => String(n).padStart(2, '0');
    // `pg` parses DATE as local midnight. Formatting that instant with
    // toISOString() would shift the calendar day backwards in Asia/Dhaka.
    if (column.data_type === 'date') return `${value.getFullYear()}-${pad(value.getMonth()+1)}-${pad(value.getDate())}`;
    const parts = column.data_type === 'timestamp with time zone'
      ? [value.getUTCFullYear(), value.getUTCMonth()+1, value.getUTCDate(), value.getUTCHours(), value.getUTCMinutes(), value.getUTCSeconds()]
      : [value.getFullYear(), value.getMonth()+1, value.getDate(), value.getHours(), value.getMinutes(), value.getSeconds()];
    return `${parts[0]}-${pad(parts[1])}-${pad(parts[2])} ${pad(parts[3])}:${pad(parts[4])}:${pad(parts[5])}.${String(value.getMilliseconds()).padStart(3,'0')}`;
  }
  if (typeof value === 'boolean') return value ? 1 : 0;
  if (Array.isArray(value) || (typeof value === 'object' && value !== null)) return JSON.stringify(value);
  return value;
}
function groupConstraints(rows) {
  const map = new Map();
  for (const row of rows) {
    const key = `${row.table_name}\0${row.constraint_name}`;
    if (!map.has(key)) map.set(key, { table: row.table_name, name: row.constraint_name, type: row.constraint_type, columns: [], refTable: row.constraint_type === 'FOREIGN KEY' ? row.ref_table : null, refColumns: [], updateRule: row.update_rule, deleteRule: row.delete_rule });
    const item = map.get(key);
    item.columns[row.ordinal_position - 1] = row.column_name;
    if (item.type === 'FOREIGN KEY' && row.ref_column) item.refColumns[row.ordinal_position - 1] = row.ref_column;
  }
  return [...map.values()];
}
// Two unique keys over the same column *set* enforce the same rule even if the
// column order differs. Postgres and the legacy local schema disagree about
// that order in several tables, which used to trigger ER_DUP_KEYNAME.
function columnSetKey(columns) { return [...columns].sort().join(','); }
function orderedKey(columns) { return columns.join(','); }
function uniqueSignature(c) { return `${c.table}|${columnSetKey(c.columns)}`; }
function foreignKeySignature(c) { return `${c.table}|${orderedKey(c.columns)}|${c.refTable}|${orderedKey(c.refColumns || [])}`; }
function truncateName(base, digestSeed, prefixLength = 51) {
  if (base.length <= 64) return base;
  const digest = crypto.createHash('sha1').update(digestSeed).digest('hex').slice(0, 10);
  return `${base.slice(0, prefixLength)}_${digest}`.slice(0, 64);
}
function makeAlternateName(kind, c, attempt) {
  const seed = `${c.table}.${c.name}.${c.columns.join(',')}.${attempt}`;
  const digest = crypto.createHash('sha1').update(seed).digest('hex').slice(0, 8);
  const base = `mirror_${kind}_${c.table}_${c.columns.join('_')}`.replace(/[^A-Za-z0-9_]/g, '_');
  return truncateName(`${base}_${digest}`, seed);
}
function makeForeignKeyName(c) {
  const base = `mirror_${c.table}_${c.name}`.replace(/[^A-Za-z0-9_]/g, '_');
  return truncateName(base, `${c.table}.${c.name}`);
}
async function getRemoteSchema() {
  const [{ rows: tables }, { rows: columns }, { rows: keyConstraints }, { rows: foreignKeys }] = await Promise.all([
    pgPool.query("SELECT tablename AS table_name FROM pg_tables WHERE schemaname='public' ORDER BY tablename"),
    pgPool.query("SELECT table_name,column_name,data_type,udt_name,is_nullable,column_default,character_maximum_length,numeric_precision,numeric_scale,ordinal_position FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name,ordinal_position"),
    pgPool.query(`SELECT tc.table_name,tc.constraint_name,tc.constraint_type,kcu.column_name,kcu.ordinal_position,
      NULL::text AS ref_table,NULL::text AS ref_column,NULL::text AS update_rule,NULL::text AS delete_rule
      FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu
      ON kcu.constraint_catalog=tc.constraint_catalog AND kcu.constraint_schema=tc.constraint_schema AND kcu.constraint_name=tc.constraint_name AND kcu.table_name=tc.table_name
      WHERE tc.constraint_schema='public' AND tc.constraint_type IN ('PRIMARY KEY','UNIQUE') ORDER BY tc.table_name,tc.constraint_name,kcu.ordinal_position`),
    pgPool.query(`SELECT src.relname AS table_name,con.conname AS constraint_name,'FOREIGN KEY'::text AS constraint_type,
      srcatt.attname AS column_name,ord.ordinality AS ordinal_position,tgt.relname AS ref_table,tgtatt.attname AS ref_column,
      CASE con.confupdtype WHEN 'c' THEN 'CASCADE' WHEN 'r' THEN 'RESTRICT' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' ELSE 'NO ACTION' END AS update_rule,
      CASE con.confdeltype WHEN 'c' THEN 'CASCADE' WHEN 'r' THEN 'RESTRICT' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' ELSE 'NO ACTION' END AS delete_rule
      FROM pg_constraint con JOIN pg_class src ON src.oid=con.conrelid JOIN pg_namespace srcns ON srcns.oid=src.relnamespace
      JOIN pg_class tgt ON tgt.oid=con.confrelid
      JOIN LATERAL unnest(con.conkey,con.confkey) WITH ORDINALITY AS ord(src_attnum,tgt_attnum,ordinality) ON TRUE
      JOIN pg_attribute srcatt ON srcatt.attrelid=src.oid AND srcatt.attnum=ord.src_attnum
      JOIN pg_attribute tgtatt ON tgtatt.attrelid=tgt.oid AND tgtatt.attnum=ord.tgt_attnum
      WHERE con.contype='f' AND srcns.nspname='public' ORDER BY src.relname,con.conname,ord.ordinality`)
  ]);
  return { tables: tables.map(x => x.table_name), columns, constraints: [...groupConstraints(keyConstraints), ...groupConstraints(foreignKeys)] };
}
async function getLocalSchema() {
  const [tables] = await local.query("SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE'");
  const [columns] = await local.query("SELECT table_name,column_name,data_type,column_type,is_nullable,column_default,extra,character_maximum_length FROM information_schema.columns WHERE table_schema=DATABASE()");
  const [constraints] = await local.query(`SELECT tc.table_name,tc.constraint_name,tc.constraint_type,kcu.column_name,kcu.ordinal_position,
    kcu.referenced_table_name AS ref_table,kcu.referenced_column_name AS ref_column,NULL AS update_rule,NULL AS delete_rule
    FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu
    ON kcu.constraint_schema=tc.constraint_schema AND kcu.constraint_name=tc.constraint_name AND kcu.table_name=tc.table_name
    WHERE tc.constraint_schema=DATABASE() AND tc.constraint_type IN ('PRIMARY KEY','UNIQUE','FOREIGN KEY') ORDER BY tc.table_name,tc.constraint_name,kcu.ordinal_position`);
  return { tables: new Set(tables.map(x => x.table_name)), columns, constraints: groupConstraints(constraints) };
}
async function getLocalIndexes() {
  const [rows] = await local.query(`SELECT table_name,index_name,non_unique,GROUP_CONCAT(column_name ORDER BY seq_in_index) AS columns
    FROM information_schema.statistics WHERE table_schema=DATABASE()
    GROUP BY table_name,index_name,non_unique`);
  return rows.map(r => ({ table: r.table_name, name: r.index_name, unique: Number(r.non_unique) === 0, columns: String(r.columns || '').split(',').filter(Boolean) }));
}
function sourceConstraintSql(c) {
  if (c.type === 'PRIMARY KEY') return `PRIMARY KEY (${c.columns.map(q).join(',')})`;
  if (c.type === 'UNIQUE') return `CONSTRAINT ${q(c.name)} UNIQUE (${c.columns.map(q).join(',')})`;
  return null;
}
async function ensureSchema(remote) {
  const textUnique = new Set(remote.constraints.filter(c => c.type === 'UNIQUE').flatMap(c => c.columns.map(col => `${c.table}.${col}`)));
  let localSchema = await getLocalSchema();
  const byTable = new Map();
  for (const c of remote.columns) { if (!byTable.has(c.table_name)) byTable.set(c.table_name, []); byTable.get(c.table_name).push(c); }
  for (const table of remote.tables) {
    const cols = byTable.get(table) || [];
    const constraints = remote.constraints.filter(c => c.table === table && ['PRIMARY KEY','UNIQUE'].includes(c.type));
    const primary = constraints.find(c => c.type === 'PRIMARY KEY');
    const pkId = primary && primary.columns.length === 1 && primary.columns[0] === 'id' && cols.some(c => c.column_name === 'id' && isIntegerType(c.udt_name));
    if (!localSchema.tables.has(table)) {
      const defs = cols.map(c => {
        const auto = c.column_name === 'id' && pkId;
        return `${q(c.column_name)} ${pgType(c,textUnique)}${defaultSql(c.column_default,auto)}${c.is_nullable === 'NO' ? ' NOT NULL' : ' NULL'}`;
      });
      for (const c of constraints) defs.push(sourceConstraintSql(c));
      await local.query(`CREATE TABLE IF NOT EXISTS ${q(table)} (${defs.join(',')}) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);
      localSchema.tables.add(table);
    }
  }
  localSchema = await getLocalSchema();
  const localCols = new Map(localSchema.columns.map(c => [`${c.table_name}.${c.column_name}`, c]));
  for (const c of remote.columns) {
    const key = `${c.table_name}.${c.column_name}`;
    const current = localCols.get(key);
    const desired = current && current.data_type === 'enum' && c.udt_name === 'text' ? 'VARCHAR(255)' : pgType(c,textUnique);
    if (!current) {
      const auto = c.column_name === 'id' && remote.constraints.some(x => x.table === c.table_name && x.type === 'PRIMARY KEY' && x.columns.length === 1 && x.columns[0] === 'id') && isIntegerType(c.udt_name);
      await local.query(`ALTER TABLE ${q(c.table_name)} ADD COLUMN ${q(c.column_name)} ${desired}${defaultSql(c.column_default,auto)} NULL`);
      continue;
    }
    const isEnum = current.data_type === 'enum';
    const remoteVarcharLonger = c.udt_name === 'varchar' && c.character_maximum_length && current.data_type === 'varchar' && (current.character_maximum_length || 0) < c.character_maximum_length;
    const remoteText = ['text','_text','_int2','_int4','_int8','_varchar'].includes(c.udt_name);
    const currentFits = isEnum ? false :
      (['int2','int4','int8'].includes(c.udt_name) && ['tinyint','smallint','mediumint','int','bigint'].includes(current.data_type)) ||
      (c.udt_name === 'bool' && ['tinyint','bit'].includes(current.data_type)) ||
      (c.udt_name === 'numeric' && ['decimal','float','double'].includes(current.data_type)) ||
      (['timestamp','timestamptz'].includes(c.udt_name) && ['timestamp','datetime'].includes(current.data_type)) ||
      (c.udt_name === 'date' && current.data_type === 'date') ||
      (c.udt_name === 'time' && current.data_type === 'time') ||
      (['json','jsonb'].includes(c.udt_name) && ['json','longtext','text'].includes(current.data_type)) ||
      (c.udt_name === 'bytea' && current.data_type === 'longblob') ||
      (['float4','float8'].includes(c.udt_name) && ['float','double'].includes(current.data_type)) ||
      (c.udt_name === 'varchar' && ['varchar','text','mediumtext','longtext'].includes(current.data_type) && !remoteVarcharLonger) ||
      (remoteText && ['text','mediumtext','longtext','varchar','json'].includes(current.data_type));
    const needsNullable = c.is_nullable === 'YES' && current.is_nullable === 'NO';
    if (isEnum || remoteVarcharLonger || (!currentFits && !needsNullable) || needsNullable) {
      await local.query(`ALTER TABLE ${q(c.table_name)} MODIFY COLUMN ${q(c.column_name)} ${desired}${defaultSql(c.column_default,false)} NULL`);
    }
  }
}
async function enforceRemoteNullability(remote) {
  const localSchema = await getLocalSchema();
  const map = new Map(localSchema.columns.map(c => [`${c.table_name}.${c.column_name}`, c]));
  for (const c of remote.columns) {
    const current = map.get(`${c.table_name}.${c.column_name}`);
    if (!current || c.is_nullable !== 'NO' || current.is_nullable === 'NO') continue;
    const auto = /auto_increment/i.test(current.extra);
    const desired = c.udt_name === 'text' && current.data_type === 'varchar' && current.character_maximum_length === 255 ? 'VARCHAR(255)' : pgType(c,new Set());
    await local.query(`ALTER TABLE ${q(c.table_name)} MODIFY COLUMN ${q(c.column_name)} ${desired}${defaultSql(c.column_default,auto)} NOT NULL`);
  }
}
async function addMissingConstraints(remote) {
  const localSchema = await getLocalSchema();
  const localIndexes = await getLocalIndexes();
  const indexByTable = new Map();
  const uniqueKeys = new Set();
  for (const i of localIndexes) {
    if (!indexByTable.has(i.table)) indexByTable.set(i.table, new Set());
    indexByTable.get(i.table).add(i.name);
    if (i.unique) uniqueKeys.add(`${i.table}|${columnSetKey(i.columns)}`);
  }
  const localPrimary = new Map(localSchema.constraints.filter(c => c.type === 'PRIMARY KEY').map(c => [c.table, c]));
  const localForeignKeys = new Set(localSchema.constraints.filter(c => c.type === 'FOREIGN KEY').map(foreignKeySignature));
  const result = { added: { pk: 0, unique: 0, fk: 0 }, conflicts: [], errors: [] };
  const rule = x => ['CASCADE','SET NULL','SET DEFAULT'].includes(x) ? x : 'RESTRICT';
  for (const c of remote.constraints) {
    try {
      if (c.type === 'PRIMARY KEY') {
        const existing = localPrimary.get(c.table);
        if (existing) {
          if (columnSetKey(existing.columns) !== columnSetKey(c.columns)) {
            result.conflicts.push(`${c.table}.${c.name} (local primary key differs: ${existing.columns.join(',')})`);
          }
          continue;
        }
        await local.query(`ALTER TABLE ${q(c.table)} ADD PRIMARY KEY (${c.columns.map(q).join(',')})`);
        result.added.pk += 1;
        continue;
      }
      if (c.type === 'UNIQUE') {
        if (uniqueKeys.has(uniqueSignature(c))) continue;
        let name = c.name;
        if ((indexByTable.get(c.table) || new Set()).has(name)) name = makeAlternateName('uq', c, 1);
        let attempt = 1;
        for (;;) {
          try {
            await local.query(`ALTER TABLE ${q(c.table)} ADD CONSTRAINT ${q(name)} UNIQUE (${c.columns.map(q).join(',')})`);
            break;
          } catch (error) {
            if (error.code !== 'ER_DUP_KEYNAME' || attempt >= 3) throw error;
            name = makeAlternateName('uq', c, ++attempt);
          }
        }
        if (!indexByTable.has(c.table)) indexByTable.set(c.table, new Set());
        indexByTable.get(c.table).add(name);
        uniqueKeys.add(uniqueSignature(c));
        result.added.unique += 1;
        continue;
      }
      if (localForeignKeys.has(foreignKeySignature(c))) continue;
      let name = makeForeignKeyName(c);
      let attempt = 0;
      for (;;) {
        try {
          await local.query(`ALTER TABLE ${q(c.table)} ADD CONSTRAINT ${q(name)} FOREIGN KEY (${c.columns.map(q).join(',')}) REFERENCES ${q(c.refTable)} (${c.refColumns.map(q).join(',')}) ON UPDATE ${rule(c.updateRule)} ON DELETE ${rule(c.deleteRule)}`);
          break;
        } catch (error) {
          if (!['ER_DUP_KEYNAME', 'ER_FK_DUP_NAME'].includes(error.code) || attempt >= 3) throw error;
          name = makeAlternateName('fk', c, ++attempt);
        }
      }
      localForeignKeys.add(foreignKeySignature(c));
      result.added.fk += 1;
    } catch (error) {
      result.errors.push(`${c.table}.${c.name} [${c.type}] ${error.code || 'ERROR'}`);
    }
  }
  return result;
}
function constraintCoverage(remote, localSchema, localIndexes) {
  const localPrimary = new Map(localSchema.constraints.filter(c => c.type === 'PRIMARY KEY').map(c => [c.table, c]));
  const localForeignKeys = new Set(localSchema.constraints.filter(c => c.type === 'FOREIGN KEY').map(foreignKeySignature));
  const uniqueKeys = new Set(localIndexes.filter(i => i.unique).map(i => `${i.table}|${columnSetKey(i.columns)}`));
  const missing = [];
  for (const c of remote.constraints) {
    if (c.type === 'PRIMARY KEY') {
      const existing = localPrimary.get(c.table);
      if (!existing) missing.push(`${c.table} primary key`);
      else if (columnSetKey(existing.columns) !== columnSetKey(c.columns)) missing.push(`${c.table} primary key differs`);
    } else if (c.type === 'UNIQUE') {
      if (!uniqueKeys.has(uniqueSignature(c))) missing.push(`${c.table} unique(${c.columns.join(',')})`);
    } else if (!localForeignKeys.has(foreignKeySignature(c))) {
      missing.push(`${c.table} foreign key(${c.columns.join(',')}) -> ${c.refTable}`);
    }
  }
  return missing;
}
async function remoteTableCounts(tables, client = pgPool) {
  const counts = new Map();
  for (const table of tables) {
    const { rows } = await client.query(`SELECT COUNT(*)::bigint AS n FROM public.${p(table)}`);
    counts.set(table, Number(rows[0].n));
  }
  return counts;
}
async function localTableCounts(tables) {
  const counts = new Map();
  for (const table of tables) {
    const [rows] = await local.query(`SELECT COUNT(*) AS n FROM ${q(table)}`);
    counts.set(table, Number(rows[0].n));
  }
  return counts;
}
// Stronger than counts: compare an order-independent hash of primary-key values.
// Values never leave this process and are never logged.
async function primaryKeyHash(rows, columns) {
  if (!columns || !columns.length) return null;
  const hash = crypto.createHash('sha256');
  const pad = n => String(n).padStart(2, '0');
  const keys = rows.map(row => columns.map(col => {
    const name = typeof col === 'string' ? col : col.column_name;
    const v = row[name];
    if (v === null || v === undefined) return '\u0001';
    if (v instanceof Date) {
      // DATE values are calendar days in both engines; compare them as such so
      // a timezone offset cannot make identical rows look different.
      if (col && col.data_type === 'date') return `${v.getFullYear()}-${pad(v.getMonth() + 1)}-${pad(v.getDate())}`;
      return v.toISOString();
    }
    if (Buffer.isBuffer(v)) return v.toString('hex');
    if (typeof v === 'object') return JSON.stringify(v);
    return String(v);
  }).join('\u0000')).sort();
  for (const key of keys) hash.update(key).update('\n');
  return hash.digest('hex');
}
async function verifyMirror(remote, options = {}) {
  const localSchema = await getLocalSchema();
  const localIndexes = await getLocalIndexes();
  const localColumnSet = new Set(localSchema.columns.map(c => `${c.table_name}.${c.column_name}`));
  const remoteColumnSet = new Set(remote.columns.map(c => `${c.table_name}.${c.column_name}`));
  const missingTables = remote.tables.filter(t => !localSchema.tables.has(t));
  const missingColumns = remote.columns.filter(c => !localColumnSet.has(`${c.table_name}.${c.column_name}`));
  const extraColumns = localSchema.columns.filter(c => !remoteColumnSet.has(`${c.table_name}.${c.column_name}`) && remote.tables.includes(c.table_name));
  const missingConstraints = constraintCoverage(remote, localSchema, localIndexes);
  const counts = await remoteTableCounts(remote.tables);
  const localCounts = await localTableCounts(remote.tables);
  const countMismatches = [];
  for (const table of remote.tables) {
    if (counts.get(table) !== localCounts.get(table)) countMismatches.push(`${table} remote=${counts.get(table)} local=${localCounts.get(table)}`);
  }
  let deep = null;
  if (options.deep) {
    const mismatches = [];
    const primaryByTable = new Map(remote.constraints.filter(c => c.type === 'PRIMARY KEY').map(c => [c.table, c.columns]));
    const columnTypes = new Map(remote.columns.map(c => [`${c.table_name}.${c.column_name}`, c]));
    for (const table of remote.tables) {
      const pkNames = primaryByTable.get(table);
      if (!pkNames) continue;
      const pk = pkNames.map(name => columnTypes.get(`${table}.${name}`) || name);
      const client = await pgPool.connect();
      try {
        const { rows } = await client.query(`SELECT ${pkNames.map(p).join(',')} FROM public.${p(table)}`);
        const localRows = (await local.query(`SELECT ${pkNames.map(q).join(',')} FROM ${q(table)}`))[0];
        const [a, b] = [await primaryKeyHash(rows, pk), await primaryKeyHash(localRows, pk)];
        if (a !== b) mismatches.push(`${table} primary-key content hash differs`);
      } finally { client.release(); }
    }
    deep = { checkedTables: remote.tables.filter(t => primaryByTable.has(t)).length, mismatches };
  }
  return {
    ok: missingTables.length === 0 && missingColumns.length === 0 && missingConstraints.length === 0 && countMismatches.length === 0 && (!deep || deep.mismatches.length === 0),
    remoteTables: remote.tables.length,
    localTables: localSchema.tables.size,
    totalRows: [...counts.values()].reduce((a, b) => a + b, 0),
    missingTables,
    missingColumns,
    extraColumns,
    missingConstraints,
    countMismatches,
    deep
  };
}
function describeVerification(v) {
  const parts = [
    `Supabase tables=${v.remoteTables}`,
    `local tables=${v.localTables}`,
    `rows=${v.totalRows}`,
    `missing tables=${v.missingTables.length}`,
    `missing columns=${v.missingColumns.length}`,
    `missing constraints=${v.missingConstraints.length}`,
    `row-count mismatches=${v.countMismatches.length}`
  ];
  if (v.deep) parts.push(`deep PK-hash mismatches=${v.deep.mismatches.length}`);
  return parts.join('; ');
}
async function syncOnce() {
  const state = { dataCommitted: false, rowsCopied: 0, repair: null };
  await pgPool.query('SELECT 1');
  await local.query('SELECT 1');
  const remote = await getRemoteSchema();
  const before = await getLocalSchema();
  const remoteColumnSet = new Set(remote.columns.map(c => `${c.table_name}.${c.column_name}`));
  const localColumnSet = new Set(before.columns.map(c => `${c.table_name}.${c.column_name}`));
  const missingTables = remote.tables.filter(t => !before.tables.has(t));
  const missingColumns = remote.columns.filter(c => !localColumnSet.has(`${c.table_name}.${c.column_name}`));
  const enums = before.columns.filter(c => c.data_type === 'enum' && remoteColumnSet.has(`${c.table_name}.${c.column_name}`));
  if (checkOnly) {
    const localIndexes = await getLocalIndexes();
    const missingConstraints = constraintCoverage(remote, before, localIndexes);
    const extraColumns = before.columns.filter(c => !remoteColumnSet.has(`${c.table_name}.${c.column_name}`) && remote.tables.includes(c.table_name));
    log(`CHECK Supabase tables=${remote.tables.length}; local tables=${before.tables.size}; missing tables=${missingTables.length}; missing columns=${missingColumns.length}; extra local columns=${extraColumns.length}; missing constraints=${missingConstraints.length}; legacy enums to widen=${enums.length}`);
    if (missingConstraints.length) log(`CHECK missing constraints: ${missingConstraints.slice(0, 20).join('; ')}${missingConstraints.length > 20 ? ` (+${missingConstraints.length - 20} more)` : ''}`);
    return true;
  }
  if (verifyOnly) {
    const v = await verifyMirror(remote, { deep: process.argv.includes('--deep') });
    log(`VERIFY ${v.ok ? 'OK' : 'FAILED'}: ${describeVerification(v)}`);
    if (!v.ok) {
      if (v.countMismatches.length) log(`VERIFY row-count mismatch tables: ${v.countMismatches.join('; ')}`);
      if (v.missingConstraints.length) log(`VERIFY missing constraints: ${v.missingConstraints.slice(0, 20).join('; ')}${v.missingConstraints.length > 20 ? ` (+${v.missingConstraints.length - 20} more)` : ''}`);
      if (v.missingTables.length) log(`VERIFY missing tables: ${v.missingTables.join(', ')}`);
      if (v.deep && v.deep.mismatches.length) log(`VERIFY deep mismatches: ${v.deep.mismatches.join('; ')}`);
    }
    return v.ok;
  }
  await ensureSchema(remote);
  const columnsByTable = new Map();
  for (const c of remote.columns) { if (!columnsByTable.has(c.table_name)) columnsByTable.set(c.table_name, []); columnsByTable.get(c.table_name).push(c); }
  await local.query('SET FOREIGN_KEY_CHECKS=0');
  let totalRows = 0;
  try {
    await local.beginTransaction();
    for (const table of remote.tables) await local.query(`DELETE FROM ${q(table)}`);
    // Read every table from one repeatable-read snapshot so a concurrent app
    // write cannot leave a half-old/half-new mirror.
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      for (const table of remote.tables) {
        const cols = columnsByTable.get(table) || [];
        const names = cols.map(c => c.column_name);
        const { rows } = await client.query(`SELECT * FROM public.${p(table)}`);
        for (let offset = 0; offset < rows.length; offset += 100) {
          const chunk = rows.slice(offset, offset + 100);
          const placeholders = chunk.map(() => `(${names.map(() => '?').join(',')})`).join(',');
          const values = [];
          for (const row of chunk) for (const c of cols) values.push(valueForMysql(row[c.column_name], c));
          await local.query(`INSERT INTO ${q(table)} (${names.map(q).join(',')}) VALUES ${placeholders}`, values);
        }
        const [countRows] = await local.query(`SELECT COUNT(*) AS n FROM ${q(table)}`);
        if (Number(countRows[0].n) !== rows.length) throw Object.assign(new Error(`row count mismatch in ${table}`), { code: 'ROW_COUNT_MISMATCH' });
        totalRows += rows.length;
      }
      await client.query('COMMIT');
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch {}
      throw error;
    } finally { client.release(); }
    await local.commit();
    state.dataCommitted = true;
    state.rowsCopied = totalRows;
  } catch (error) {
    try { await local.rollback(); } catch {}
    error.state = state;
    throw error;
  } finally {
    try { await local.query('SET FOREIGN_KEY_CHECKS=1'); } catch {}
  }
  const repairErrors = [];
  try {
    state.repair = await addMissingConstraints(remote);
    repairErrors.push(...state.repair.errors);
  } catch (error) {
    repairErrors.push(`constraint phase ${error.code || 'ERROR'}`);
  }
  try {
    await enforceRemoteNullability(remote);
  } catch (error) {
    repairErrors.push(`nullability phase ${error.code || 'ERROR'}`);
  }
  const verification = await verifyMirror(remote);
  if (!verification.ok) {
    const detail = verification.countMismatches.length
      ? `counts: ${verification.countMismatches.slice(0, 8).join('; ')}`
      : verification.missingConstraints.length
        ? `constraints: ${verification.missingConstraints.slice(0, 8).join('; ')}`
        : `schema: missing tables=${verification.missingTables.length} missing columns=${verification.missingColumns.length}`;
    const error = Object.assign(new Error(`post-sync verification failed: ${detail}`), { code: 'POST_SYNC_VERIFY_FAILED' });
    error.state = Object.assign(state, { verification, repairErrors });
    throw error;
  }
  if (repairErrors.length) {
    log(`SYNC PARTIAL: data refreshed and row counts verified (${remote.tables.length} tables, ${totalRows} rows), but some schema repairs were skipped: ${repairErrors.slice(0, 12).join('; ')}${repairErrors.length > 12 ? ` (+${repairErrors.length - 12} more)` : ''}`);
    return false;
  }
  if (state.repair.conflicts.length) {
    log(`SYNC PARTIAL: data refreshed and verified, but local constraints need review: ${state.repair.conflicts.slice(0, 12).join('; ')}`);
    return false;
  }
  log(`SYNC OK: ${remote.tables.length} tables; ${totalRows} rows mirrored from Supabase to local MariaDB; counts and constraints verified.`);
  return true;
}
let local;
let lockFd;
let cycleBusy = false;
async function cycle() {
  if (cycleBusy) return false;
  cycleBusy = true;
  try {
    if (!local) local = await mysql.createConnection({
      host: process.env.LOCAL_MYSQL_HOST || '127.0.0.1',
      port: Number(process.env.LOCAL_MYSQL_PORT || 3306),
      user: process.env.LOCAL_MYSQL_USER || 'root',
      password: process.env.LOCAL_MYSQL_PASSWORD || undefined,
      database: 'schooldb',
      charset: 'utf8mb4',
      timezone: 'Z'
    });
    return await syncOnce();
  } catch (e) {
    const state = e.state || {};
    const repair = state.repairErrors && state.repairErrors.length ? `; schema repair pending: ${state.repairErrors.slice(0, 8).join('; ')}` : '';
    if (state.dataCommitted) {
      log(`SYNC PARTIAL (data committed): ${state.rowsCopied} rows refreshed but the mirror is not fully verified (${e.code || 'error'})${repair}.`);
    } else {
      log(`SYNC failed (${e.code || 'error'}); no local data was committed.${repair}`);
    }
    if (local) { try { await local.end(); } catch {} local = null; }
    return false;
  } finally { cycleBusy = false; }
}
function acquireLock() {
  fs.mkdirSync(logDir, { recursive: true });
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      lockFd = fs.openSync(lockPath, 'wx');
      fs.writeFileSync(lockFd, String(process.pid));
      return true;
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      let pid = 0;
      try { pid = Number(fs.readFileSync(lockPath, 'utf8').trim()); } catch {}
      if (pid && pid !== process.pid) {
        try { process.kill(pid, 0); return false; } catch {}
      }
      try { fs.unlinkSync(lockPath); } catch {}
    }
  }
  return false;
}
async function shutdown() {
  if (local) { try { await local.end(); } catch {} }
  try { await pgPool.end(); } catch {}
  if (lockFd !== undefined) { try { fs.closeSync(lockFd); fs.unlinkSync(lockPath); } catch {} }
}
(async () => {
  if (!oneShot && !checkOnly && !verifyOnly && !acquireLock()) { process.exit(0); return; }
  const ok = await cycle();
  if (oneShot || checkOnly || verifyOnly) { await shutdown(); process.exit(ok ? 0 : 1); return; }
  log(`Mirror service started on ${os.hostname()} (interval ${Math.round(intervalMs / 1000)}s; Supabase -> local schooldb only).`);
  const timer = setInterval(cycle, intervalMs);
  process.on('SIGINT', async () => { clearInterval(timer); await shutdown(); process.exit(0); });
  process.on('SIGTERM', async () => { clearInterval(timer); await shutdown(); process.exit(0); });
})().catch(async e => { log(`Mirror stopped (${e.code || 'error'}).`); await shutdown(); process.exit(1); });
