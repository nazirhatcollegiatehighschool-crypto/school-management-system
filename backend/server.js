require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const pool = require('./db');

const app = express();
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors());
app.use(express.json({ limit: '2mb' }));

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many login attempts. Try again in 15 minutes.' }
});
app.use('/api/auth/login', loginLimiter);
app.use('/api/auth/guardian-login', loginLimiter);

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

const APP_VERSIONS = { teacher: '1.2.0', guardian: '1.2.0', admin: '1.2.0' };
const APK_FILES = { teacher: 'TeacherApp.apk', guardian: 'GuardianApp.apk', admin: 'AdminApp.apk' };
app.get('/api/app-version', (req, res) => {
  const which = req.query.app;
  const proto = req.headers['x-forwarded-proto'] || req.protocol;
  const base = `${proto}://${req.get('host')}`;
  if (which && APP_VERSIONS[which]) {
    return res.json({ app: which, version: APP_VERSIONS[which], apk_url: `${base}/apks/${APK_FILES[which]}` });
  }
  const all = {};
  Object.keys(APP_VERSIONS).forEach(k => { all[k] = { version: APP_VERSIONS[k], apk_url: `${base}/apks/${APK_FILES[k]}` }; });
  res.json(all);
});
const apksDir = [path.join(__dirname, 'apks'), path.join(__dirname, '..', 'apks')].find(d => fs.existsSync(d)) || path.join(__dirname, 'apks');
app.use('/apks', express.static(apksDir, { fallthrough: false }));
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