require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { ipKeyGenerator } = require('express-rate-limit');
const pool = require('./db');

const app = express();
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors());
app.use(express.json({ limit: '2mb' }));

// Minimal request log (diagnostics): method + path + status + ms.
app.use((req, res, next) => {
  const t = Date.now();
  res.on('finish', () => {
    if (req.path.startsWith('/api/')) {
      console.log(`[api] ${req.method} ${req.path} -> ${res.statusCode} ${Date.now() - t}ms ip=${req.ip}`);
    }
  });
  next();
});

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  // All tunnelled traffic arrives from 127.0.0.1 — a plain IP bucket would
  // lock out the WHOLE school after 20 logins. Key per account instead.
  // ipKeyGenerator is required by express-rate-limit v8 for IPv6-safe IP keys.
  keyGenerator: (req) => {
    const u = (req.body && (req.body.username || req.body.student_code)) || '';
    return `${ipKeyGenerator(req.ip)}:${String(u).toLowerCase()}`;
  },
  message: { error: 'Too many login attempts. Try again in 15 minutes.' }
});
app.use('/api/auth/login', loginLimiter);
app.use('/api/auth/guardian-login', loginLimiter);

// Root route for Render health checks
app.get('/', (req, res) => {
  res.json({ 
    status: 'ok', 
    message: 'School Management System API is running',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    docs: 'https://school-management-system-5jqj.onrender.com/api/health'
  });
});

app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', db: 'connected' });
  } catch (e) {
    res.status(500).json({ status: 'error', db: e.message });
  }
});

app.use('/api/auth', require('./routes/auth'));
app.use('/api/admin', require('./routes/admin'));
app.use('/api/teacher', require('./routes/teacher'));
app.use('/api/guardian', require('./routes/guardian'));
app.use('/api/results', require('./routes/results'));
app.use('/api/routine', require('./routes/routine'));

// Background class-alert service (see routine_alerts.js). Triggered every minute
// by a Vercel cron, or by a local setInterval under `node server.js`.
const { runRoutineAlertCheck, startAlertService } = require('./routine_alerts');
app.get('/api/cron/routine-alerts', async (req, res) => {
  try {
    const summary = await runRoutineAlertCheck();
    res.json({ ok: true, ...summary });
  } catch (e) {
    console.error('routine-alert cron error:', e.message);
    res.status(500).json({ error: 'alert check failed' });
  }
});

// Supabase sync endpoints
const SupabaseSync = require('./supabase_sync');
const syncSystem = new SupabaseSync();

// Admin-only sync endpoints
app.get('/api/admin/sync/schema', async (req, res) => {
  try {
    await syncSystem.initialize();
    await syncSystem.syncSchemas();
    res.json({ status: 'ok', message: 'Schema sync completed' });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

app.get('/api/admin/sync/backup', async (req, res) => {
  try {
    await syncSystem.initialize();
    const backupPath = await syncSystem.backupSupabaseData();
    res.json({ status: 'ok', backupPath, message: 'Backup completed' });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

app.get('/api/admin/sync/full', async (req, res) => {
  try {
    const result = await syncSystem.runFullSync();
    res.json(result);
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

const crypto = require('crypto');
const APP_VERSIONS = { teacher: '1.4.3', guardian: '1.4.3', admin: '1.4.3' };
const APK_FILES = { teacher: 'TeacherApp.apk', guardian: 'GuardianApp.apk', admin: 'AdminApp.apk' };
// SHA-256 of each APK, computed once at boot (integrity check for in-app
// updates: the app refuses to install a corrupt/truncated download).
const APK_SHA = {};
function shaOf(p) {
  try {
    const h = crypto.createHash('sha256');
    h.update(require('fs').readFileSync(p));
    return h.digest('hex');
  } catch (_) { return null; }
}
app.get('/api/app-version', (req, res) => {
  const which = req.query.app;
  const proto = req.headers['x-forwarded-proto'] || req.protocol;
  const base = `${proto}://${req.get('host')}`;
  const buildOf = (f) => {
    try {
      const st = require('fs').statSync(f);
      return Math.floor(st.mtimeMs / 1000);
    } catch (_) { return 0; }
  };
  const meta = (k) => {
    const fp = require('path').join(apksDir, APK_FILES[k]);
    if (!APK_SHA[k]) APK_SHA[k] = shaOf(fp);
    return { app: k, version: APP_VERSIONS[k], build: buildOf(fp), sha256: APK_SHA[k], apk_url: `${base}/apks/${APK_FILES[k]}` };
  };
  if (which && APP_VERSIONS[which]) {
    return res.json(meta(which));
  }
  const all = {};
  Object.keys(APP_VERSIONS).forEach(k => { all[k] = meta(k); });
  res.json(all);
});
const apksDir = [path.join(__dirname, 'apks'), path.join(__dirname, '..', 'apks')].find(d => fs.existsSync(d)) || path.join(__dirname, 'apks');
app.use('/apks', express.static(apksDir, { fallthrough: false }));

// Public download page: versioned APK links + admin panel entry.
// (Mobile users: open this page in Chrome, tap an app to download.)
app.get('/download', (req, res) => {
  const proto = req.headers['x-forwarded-proto'] || req.protocol;
  const base = `${proto}://${req.get('host')}`;
  const card = (app, title, desc) => `
    <div style="border:1px solid #ddd;border-radius:12px;padding:16px;margin:12px 0;background:#fff">
      <div style="font-size:18px;font-weight:700">${title}
        <span style="font-size:12px;background:#0b6b4f;color:#fff;border-radius:8px;padding:2px 8px;margin-left:6px">v${APP_VERSIONS[app]}</span></div>
      <div style="color:#555;margin:6px 0 12px">${desc}</div>
      <a href="${base}/apks/${APK_FILES[app]}" download
         style="display:inline-block;background:#0b6b4f;color:#fff;padding:12px 24px;border-radius:10px;text-decoration:none;font-weight:700">⬇ ডাউনলোড</a>
    </div>`;
  res.send(`<!DOCTYPE html><html lang="bn"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>School App Download</title></head>
<body style="font-family:sans-serif;max-width:560px;margin:0 auto;padding:16px;background:#f4f7f5">
<h2>🏫 School Apps</h2>
${card('teacher', 'Teacher App', 'শিক্ষকদের জন্য — হাজিরা, মার্কস, রুটিন, রেজাল্ট')}
${card('guardian', 'Guardian App', 'অভিভাবকদের জন্য — সন্তানের হাজিরা, রেজাল্ট, নোটিশ')}
<div style="border:1px solid #ddd;border-radius:12px;padding:16px;margin:12px 0;background:#fff">
<div style="font-size:18px;font-weight:700">Admin Panel</div>
<div style="color:#555;margin:6px 0 12px">অ্যাডমিন ওয়েব প্যানেল (ব্রাউজারেই চলবে)</div>
<a href="${base}/" style="display:inline-block;background:#2e3a8c;color:#fff;padding:12px 24px;border-radius:10px;text-decoration:none;font-weight:700">🖥️ Open Admin Panel</a>
</div>
<p style="color:#888;font-size:12px">Install-এর সময় "Unknown apps → Allow" দিন। App-এর ভেতর Login screen → Server-এ এই সার্ভারের link বসান।</p>
</body></html>`);
});
const uploadsRoot = process.env.VERCEL_UPLOAD_DIR || path.join(__dirname, 'uploads');
app.use('/uploads', express.static(uploadsRoot));

const dist = fs.existsSync(path.join(__dirname, 'dist'))
  ? path.join(__dirname, 'dist')
  : path.join(__dirname, '..', 'website', 'admin-site', 'dist');
if (fs.existsSync(dist)) {
  app.use(express.static(dist));
  app.get(/^\/(?!api).*/, (req, res) => {
    res.sendFile(path.join(dist, 'index.html'));
  });
}

app.use((req, res) => res.status(404).json({ error: 'Not found' }));

if (require.main === module) {
  const PORT = process.env.PORT || 5000;
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`School API running on http://0.0.0.0:${PORT}`);
    startAlertService();
  });
}

module.exports = app;