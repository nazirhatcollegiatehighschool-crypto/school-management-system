'use strict';
// Verify/decrypt/restore an encrypted Supabase backup produced by
// scripts/backup_supabase_secure.cjs. Never restores into the live project
// database: the target must be a clearly named isolated database.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const dotenv = require(path.join(root, 'backend', 'node_modules', 'dotenv'));
dotenv.config({ path: path.join(root, 'backend', '.env'), quiet: true });
const toolDir = path.join(root, '.tmp', 'pg_stage_recovery_20261025', 'postgres', 'pgsql', 'bin');
const bin = name => {
  const local = path.join(toolDir, name);
  return fs.existsSync(local) ? local : name;
};
function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next && !next.startsWith('--')) { out[key] = next; i += 1; } else out[key] = true;
    } else out._.push(a);
  }
  return out;
}
const args = parseArgs(process.argv.slice(2));
const mode = args.verify ? 'verify' : args.restore ? 'restore' : args['decrypt-to'] ? 'decrypt' : null;
if (!mode) {
  console.error('Usage: node scripts/restore_supabase_secure.cjs (--verify | --restore <target-url> --confirm-target <db-name> | --decrypt-to <file>) [--archive <file>]');
  process.exit(2);
}
function resolveArchive() {
  if (args.archive) return path.resolve(String(args.archive));
  const dir = path.join(root, 'runtime', 'secure_backups');
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.dump.sbk')).map(f => path.join(dir, f));
  if (!files.length) throw new Error('No .dump.sbk archive found.');
  return files.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
}
// File-descriptor stdio is deliberate: the Windows sandbox denies named pipes,
// and redirecting to files also keeps database output out of chat/logs.
function runToFile(exe, argv, logPath, options = {}) {
  const fd = fs.openSync(logPath, 'w');
  try {
    const result = spawnSync(exe, argv, {
      windowsHide: true,
      stdio: ['ignore', fd, fd],
      ...options
    });
    return result;
  } finally { fs.closeSync(fd); }
}
function failIf(result, label) {
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`${label} failed (exit ${result.status}).`);
}
function decryptArchive(archivePath) {
  if (!archivePath.endsWith('.dump.sbk')) throw new Error('Archive name must end in .dump.sbk.');
  const keyPath = archivePath.replace(/\.dump\.sbk$/, '.key.dpapi');
  const manifestPath = archivePath.replace(/\.dump\.sbk$/, '.manifest.json');
  if (!fs.existsSync(keyPath) || !fs.existsSync(manifestPath)) throw new Error('Matching key/manifest file is missing.');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const archive = fs.readFileSync(archivePath);
  if (manifest.archive_bytes !== archive.length) throw new Error('Archive size does not match its manifest.');
  const hash = crypto.createHash('sha256').update(archive).digest('hex').toUpperCase();
  if (hash !== String(manifest.archive_sha256 || '').toUpperCase()) throw new Error('Archive SHA-256 does not match its manifest.');
  const magic = Buffer.from('SSBK0001');
  if (!archive.subarray(0, 8).equals(magic)) throw new Error('Encrypted archive header mismatch.');
  const workRoot = path.join(root, '.tmp');
  fs.mkdirSync(workRoot, { recursive: true });
  const keyOut = path.join(workRoot, `school-key-${process.pid}-${Date.now()}.bin`);
  try {
    const unprotect = runToFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', path.join(__dirname, 'dpapi_unprotect.ps1'), '-InPath', keyPath, '-OutPath', keyOut],
      path.join(workRoot, `school-dpapi-${process.pid}.log`));
    failIf(unprotect, 'DPAPI key unprotect');
    const key = fs.readFileSync(keyOut);
    if (key.length !== 32) throw new Error('Protected key did not decode to 32 bytes.');
    const iv = archive.subarray(8, 20);
    const tag = archive.subarray(20, 36);
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);
    const plain = Buffer.concat([decipher.update(archive.subarray(36)), decipher.final()]);
    return { manifest, plain, archivePath };
  } finally { try { fs.unlinkSync(keyOut); } catch {} }
}
function listArchive(dumpPath, workDir) {
  const outPath = path.join(workDir, 'archive-list.txt');
  const result = runToFile(bin('pg_restore.exe'), ['--list', dumpPath], outPath);
  failIf(result, 'PostgreSQL archive check');
  const text = fs.readFileSync(outPath, 'utf8');
  return { tableDataEntries: (text.match(/\bTABLE DATA\b/g) || []).length };
}
function targetParts(urlString) {
  const u = new URL(urlString);
  return {
    host: u.hostname,
    port: u.port || '5432',
    user: decodeURIComponent(u.username),
    password: decodeURIComponent(u.password),
    database: decodeURIComponent(u.pathname.replace(/^\//, ''))
  };
}
try {
  const archivePath = resolveArchive();
  const { manifest, plain } = decryptArchive(archivePath);
  if (plain.length < 1024) throw new Error('Decrypted archive is unexpectedly small.');
  const workRoot = path.join(root, '.tmp');
  fs.mkdirSync(workRoot, { recursive: true });
  const workDir = fs.mkdtempSync(path.join(workRoot, 'secure-restore-'));
  try {
    if (mode === 'decrypt') {
      const target = path.resolve(String(args['decrypt-to']));
      const allowedDir = path.join(root, 'runtime', 'secure_backups');
      if (!target.startsWith(allowedDir + path.sep)) throw new Error('Decrypted dumps may only be written inside runtime/secure_backups.');
      fs.writeFileSync(target, plain, { flag: 'wx', mode: 0o600 });
      console.log(JSON.stringify({ decrypted: path.relative(root, target), bytes: plain.length, warning: 'Contains private school data. Delete after use.' }));
    } else if (mode === 'verify') {
      const dumpPath = path.join(workDir, 'restore-verify.dump');
      fs.writeFileSync(dumpPath, plain);
      const listed = listArchive(dumpPath, workDir);
      if (listed.tableDataEntries !== manifest.table_data_entries) throw new Error(`Archive entry count ${listed.tableDataEntries} differs from manifest ${manifest.table_data_entries}.`);
      console.log(JSON.stringify({ archive: path.relative(root, archivePath), verified: true, tableDataEntries: listed.tableDataEntries, archiveBytes: plain.length, manifestCreatedUtc: manifest.created_utc }));
    } else {
      const target = targetParts(String(args.restore));
      const source = process.env.DATABASE_URL ? targetParts(process.env.DATABASE_URL) : null;
      if (source && source.host === target.host && source.database === target.database) throw new Error('Refusing to restore over the live source database.');
      if (String(args['confirm-target'] || '') !== target.database) throw new Error('Pass --confirm-target with the exact target database name.');
      if (!/^(restore|staging|test)_/.test(target.database) && !args['allow-non-test-target']) throw new Error('Target database must start with restore_, staging_ or test_ (or pass --allow-non-test-target deliberately).');
      const dumpPath = path.join(workDir, 'restore.dump');
      fs.writeFileSync(dumpPath, plain);
      const env = { ...process.env, PGPASSWORD: target.password, PGSSLMODE: process.env.PGSSLMODE || 'prefer' };
      const restore = runToFile(bin('pg_restore.exe'), ['--no-owner', '--no-privileges', '--exit-on-error',
        '--host', target.host, '--port', target.port, '--username', target.user, '--dbname', target.database, dumpPath],
        path.join(workDir, 'restore.log'), { env });
      failIf(restore, 'PostgreSQL restore');
      const countPath = path.join(workDir, 'restore-count.txt');
      const count = runToFile(bin('psql.exe'), ['--no-psqlrc', '--tuples-only', '--no-align',
        '--host', target.host, '--port', target.port, '--username', target.user, '--dbname', target.database,
        '--command', "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'"],
        countPath, { env });
      failIf(count, 'PostgreSQL restore check');
      console.log(JSON.stringify({ restored: true, targetDatabase: target.database, publicTables: Number(fs.readFileSync(countPath, 'utf8').trim()), tableDataEntries: manifest.table_data_entries }));
    }
  } finally {
    try { fs.rmSync(workDir, { recursive: true, force: true }); } catch {}
  }
} catch (error) {
  console.error(`Restore tool failed: ${error.message}`);
  process.exitCode = 1;
}
