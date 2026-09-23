/* FCM push notification service — graceful degradation.
   If firebase-service-account.json is missing, pushes are skipped but
   notification records are still saved in DB (in-app history works). */
const fs = require('fs');
const path = require('path');

let messaging = null;
try {
  const keyPath = path.join(__dirname, 'firebase-service-account.json');
  const envConfig = process.env.FIREBASE_CONFIG || process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON;
  let config = null;
  if (envConfig && String(envConfig).trim().startsWith('{')) {
    config = JSON.parse(envConfig);
  } else if (envConfig) {
    config = JSON.parse(Buffer.from(envConfig, 'base64').toString('utf-8'));
  } else if (fs.existsSync(keyPath)) {
    config = require(keyPath);
  }
  if (config) {
    const { initializeApp, getApps, cert } = require('firebase-admin/app');
    const { getMessaging } = require('firebase-admin/messaging');
    if (getApps().length === 0) {
      initializeApp({ credential: cert(config) });
    }
    messaging = getMessaging();
  }
} catch (e) {
  console.error('FCM init failed:', e.message);
}

// FCM allows up to 500 tokens per sendEachForMulticast call.
// For high concurrency (hundreds/thousands of guardians) we chunk the
// token list and issue one multicast per 500 so every guardian is reached.
const PUSH_BATCH_SIZE = 500;

async function sendPushToTokens(tokens, title, body, data = {}) {
  if (!messaging) return { sent: 0, reason: 'fcm-not-configured' };
  const valid = [...new Set((tokens || []).filter(t => t && String(t).length > 10))];
  if (valid.length === 0) return { sent: 0, reason: 'no-tokens' };
  const payload = Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)]));
  let sent = 0, failed = 0;
  for (let i = 0; i < valid.length; i += PUSH_BATCH_SIZE) {
    const message = {
      notification: { title, body },
      data: payload,
      android: { priority: 'high' },
      tokens: valid.slice(i, i + PUSH_BATCH_SIZE)
    };
    try {
      const res = await messaging.sendEachForMulticast(message);
      sent += res.successCount || 0;
      failed += res.failureCount || 0;
    } catch (e) {
      console.error('FCM send error:', e.message);
      failed += Math.min(PUSH_BATCH_SIZE, valid.length - i);
    }
  }
  return { sent, failed };
}

// Fire-and-forget helper: returns immediately with how many tokens were
// queued; the actual multicast runs in the background so the HTTP handler
// never blocks on FCM and can reply 200 right after DB writes.
function queuePush(tokens, title, body, data = {}) {
  const count = (tokens || []).filter(t => t && String(t).length > 10).length;
  setImmediate(() => {
    sendPushToTokens(tokens, title, body, data).catch(e =>
      console.error('Background FCM push error:', e.message));
  });
  return { sent: 0, failed: 0, queued: count };
}

async function getGuardianTokens(studentIds) {
  const pool = require('./db');
  if (!studentIds.length) return [];
  const [rows] = await pool.query(
    `SELECT DISTINCT dt.fcm_token FROM device_tokens dt
     JOIN students s ON (s.guardian_id = dt.user_id
        OR s.id IN (SELECT student_id FROM guardian_links WHERE guardian_id = dt.user_id AND status='approved'))
     WHERE dt.active=1 AND s.id IN (?)`,
    [studentIds]
  );
  return rows.map(r => r.fcm_token);
}

async function getAllGuardianTokens(classId = null) {
  const pool = require('./db');
  let query = `SELECT DISTINCT dt.fcm_token FROM device_tokens dt
     JOIN students s ON s.guardian_id = dt.user_id WHERE dt.active=1`;
  const params = [];
  if (classId) { query += ' AND s.class_id=?'; params.push(classId); }
  const [rows] = await pool.query(query, params);
  return rows.map(r => r.fcm_token);
}

module.exports = { sendPushToTokens, queuePush, getGuardianTokens, getAllGuardianTokens };