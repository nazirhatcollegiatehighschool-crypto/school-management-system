'use strict';
// Export the live Supabase PostgreSQL database, encrypt it with AES-256-GCM,
// protect the one-time key with Windows DPAPI (CurrentUser), and verify the
// encrypted archive can be decrypted and listed again before reporting success.
// Output defaults to runtime/secure_backups/ which is ignored by Git and Vercel.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const dotenv = require(path.join(root, 'backend', 'node_modules', 'dotenv'));
dotenv.config({ path: path.join(root, 'backend', '.env'), quiet: true });
const rawUrl = process.env.DATABASE_URL;
if (!rawUrl || !/^postgres(?:ql)?:\/\//i.test(rawUrl)) throw new Error('DATABASE_URL must point to the active PostgreSQL database.');
const db = new URL(rawUrl);
const toolDir = path.join(root, '.tmp', 'pg_stage_recovery_20261025', 'postgres', 'pgsql', 'bin');
const pgDump = path.join(toolDir, 'pg_dump.exe');
const pgRestore = path.join(toolDir, 'pg_restore.exe');
if (!fs.existsSync(pgDump) || !fs.existsSync(pgRestore)) throw new Error('PostgreSQL backup utilities are missing.');
const outDir = path.join(root, 'runtime', 'secure_backups');
fs.mkdirSync(outDir, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const workRoot = path.join(root, '.tmp');
fs.mkdirSync(workRoot, { recursive: true });
const workDir = fs.mkdtempSync(path.join(workRoot, 'supabase-backup-'));
const plainDump = path.join(workDir, 'supabase.dump');
const archivePath = path.join(outDir, `supabase-live-${stamp}.dump.sbk`);
const keyPath = path.join(outDir, `supabase-live-${stamp}.key.dpapi`);
const manifestPath = path.join(outDir, `supabase-live-${stamp}.manifest.json`);
const env = { ...process.env, PGPASSWORD: decodeURIComponent(db.password), PGSSLMODE: 'require' };
function runToFile(exe, argv, logPath, options = {}) {
  const fd = fs.openSync(logPath, 'w');
  try {
    return spawnSync(exe, argv, { windowsHide: true, stdio: ['ignore', fd, fd], ...options });
  } finally { fs.closeSync(fd); }
}
function failIf(result, label) {
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`${label} failed (exit ${result.status}).`);
}
function projectRef() {
  try {
    const supabase = process.env.SUPABASE_URL ? new URL(process.env.SUPABASE_URL) : null;
    if (supabase && supabase.hostname.endsWith('.supabase.co')) return supabase.hostname.split('.')[0];
  } catch {}
  const user = decodeURIComponent(db.username);
  return user.includes('.') ? user.split('.').pop() : 'unknown';
}
try {
  const dump = runToFile(pgDump, ['--format=custom', '--no-owner', '--no-privileges', '--file', plainDump,
    '--host', db.hostname, '--port', db.port || '5432', '--username', decodeURIComponent(db.username),
    '--dbname', decodeURIComponent(db.pathname.slice(1)), '--no-password'], path.join(workDir, 'dump.log'), { env });
  failIf(dump, 'Supabase export');
  const plain = fs.readFileSync(plainDump);
  if (plain.length < 1024) throw new Error('Supabase export is unexpectedly small.');
  const listPath = path.join(workDir, 'archive-list.txt');
  const list = runToFile(pgRestore, ['--list', plainDump], listPath);
  failIf(list, 'PostgreSQL archive check');
  const tableDataEntries = (fs.readFileSync(listPath, 'utf8').match(/\bTABLE DATA\b/g) || []).length;
  if (tableDataEntries < 1) throw new Error('Archive contains no table-data entries.');
  const key = crypto.randomBytes(32);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(plain), cipher.final()]);
  const tag = cipher.getAuthTag();
  const magic = Buffer.from('SSBK0001');
  const archive = Buffer.concat([magic, iv, tag, encrypted]);
  fs.writeFileSync(archivePath, archive, { flag: 'wx' });
  const keyInput = path.join(workDir, 'key.b64');
  fs.writeFileSync(keyInput, key.toString('base64'), { mode: 0o600 });
  const protectedKey = runToFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', path.join(__dirname, 'dpapi_protect.ps1'), '-InPath', keyInput, '-OutPath', keyPath],
    path.join(workDir, 'dpapi.log'));
  failIf(protectedKey, 'Windows key protection');
  const encryptedHash = crypto.createHash('sha256').update(archive).digest('hex').toUpperCase();
  const parsed = fs.readFileSync(archivePath);
  if (!parsed.subarray(0, 8).equals(magic)) throw new Error('Encrypted archive header mismatch.');
  const keyOut = path.join(workDir, 'key.plain');
  const unprotect = runToFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', path.join(__dirname, 'dpapi_unprotect.ps1'), '-InPath', keyPath, '-OutPath', keyOut],
    path.join(workDir, 'dpapi-verify.log'));
  failIf(unprotect, 'Windows key verification');
  const restoredKey = fs.readFileSync(keyOut);
  if (restoredKey.length !== 32) throw new Error('Protected key did not round-trip to 32 bytes.');
  const decipher = crypto.createDecipheriv('aes-256-gcm', restoredKey, parsed.subarray(8, 20));
  decipher.setAuthTag(parsed.subarray(20, 36));
  const decrypted = Buffer.concat([decipher.update(parsed.subarray(36)), decipher.final()]);
  if (!crypto.timingSafeEqual(crypto.createHash('sha256').update(plain).digest(), crypto.createHash('sha256').update(decrypted).digest())) throw new Error('Encrypted archive verification failed.');
  const verifyDump = path.join(workDir, 'verify.dump');
  fs.writeFileSync(verifyDump, decrypted);
  const verifyListPath = path.join(workDir, 'verify-list.txt');
  const verifyList = runToFile(pgRestore, ['--list', verifyDump], verifyListPath);
  failIf(verifyList, 'Decrypted PostgreSQL archive check');
  const verifiedTableData = (fs.readFileSync(verifyListPath, 'utf8').match(/\bTABLE DATA\b/g) || []).length;
  if (verifiedTableData !== tableDataEntries) throw new Error('Decrypted archive entry count differs.');
  const manifest = {
    project_ref: projectRef(),
    created_utc: new Date().toISOString(),
    format: 'PostgreSQL custom archive, AES-256-GCM encrypted',
    archive_bytes: archive.length,
    archive_sha256: encryptedHash,
    archived_bytes: plain.length,
    table_data_entries: verifiedTableData,
    key_protection: 'Windows DPAPI CurrentUser',
    decrypted_archive_listed: true
  };
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx' });
  const retention = Math.max(3, Number(process.env.SUPABASE_BACKUP_RETENTION || 14));
  const sets = fs.readdirSync(outDir).filter(f => f.endsWith('.dump.sbk'))
    .map(f => ({ f, t: fs.statSync(path.join(outDir, f)).mtimeMs }))
    .sort((a, b) => b.t - a.t);
  for (const old of sets.slice(retention)) {
    const base = path.join(outDir, old.f.replace(/\.dump\.sbk$/, ''));
    for (const suffix of ['.dump.sbk', '.key.dpapi', '.manifest.json']) {
      try { fs.unlinkSync(base + suffix); } catch {}
    }
  }
  console.log(JSON.stringify({ archive: path.relative(root, archivePath), bytes: archive.length,
    encryptedSha256: encryptedHash, tableDataEntries: verifiedTableData,
    decryptedArchiveListed: true, protectedKeyWritten: true }));
} catch (error) {
  for (const file of [archivePath, keyPath, manifestPath]) { try { fs.unlinkSync(file); } catch {} }
  try {
    const dumpLog = path.join(workDir, 'dump.log');
    if (fs.existsSync(dumpLog)) console.error(`pg_dump log: ${fs.readFileSync(dumpLog, 'utf8').slice(-800)}`);
  } catch {}
  console.error(`Backup failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  try { fs.rmSync(workDir, { recursive: true, force: true }); } catch {}
}
