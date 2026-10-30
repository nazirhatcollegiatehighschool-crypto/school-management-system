const pool = require('../db');
const H = require('../attendance_v2');
const { queuePush } = require('../fcm');

function dhakaEndEpoch(date, time) {
  const parts = String(date || '').slice(0, 10).split('-').map(Number);
  const clock = String(time || '').slice(0, 5).split(':').map(Number);
  if (parts.length !== 3 || clock.length !== 2 || parts.some(Number.isNaN) || clock.some(Number.isNaN) ||
      parts[0] < 1900 || parts[1] < 1 || parts[1] > 12 || parts[2] < 1 ||
      parts[2] > new Date(Date.UTC(parts[0], parts[1], 0)).getUTCDate() ||
      clock[0] < 0 || clock[0] > 23 || clock[1] < 0 || clock[1] > 59) return null;
  // Bangladesh has a fixed UTC+6 offset and does not observe daylight saving.
  return Date.UTC(parts[0], parts[1] - 1, parts[2], clock[0] - 6, clock[1]);
}

async function requestExpiry(date, session) {
  const { slots, afternoon } = await H.sessionWindows();
  const last = session === 'p5' ? afternoon : slots[slots.length - 1];
  if (!last) return null;
  return dhakaEndEpoch(date, last.end_time);
}

function isExpired(request, now = Date.now()) {
  return request.status === 'expired' || (request.status === 'pending' && Number(request.expires_at_epoch) <= now);
}

async function notifyTeacher(userId, title, body, requestId, kind = 'attendance_access_request') {
  const [[teacher]] = await pool.query("SELECT id FROM users WHERE id=? AND role='teacher'", [userId]);
  if (!teacher) return;
  await pool.query(
    `INSERT INTO notifications (class_id,title,body,type,target_type,target_user_id,related_id)
     VALUES ((SELECT class_id FROM attendance_access_requests WHERE id=?),?,?, 'attendance','teacher',?,?)`,
    [requestId, title, body, userId, requestId]);
  const [tokens] = await pool.query('SELECT fcm_token FROM device_tokens WHERE user_id=? AND active=1', [userId]);
  queuePush(tokens.map(row => row.fcm_token), title, body, {
    type: 'attendance', kind, request_id: requestId, related_id: requestId,
  });
}

async function expirePendingRequests(now = Date.now()) {
  const [expired] = await pool.query(
    `SELECT id, requested_by, class_teacher_id FROM attendance_access_requests
     WHERE status='pending' AND expires_at_epoch<=? ORDER BY id LIMIT 500`, [now]);
  let count = 0;
  for (const request of expired) {
    const [changed] = await pool.query(
      `UPDATE attendance_access_requests SET status='expired', decided_at=NOW()
       WHERE id=? AND status='pending' AND expires_at_epoch<=?`, [request.id, now]);
    if (!changed.affectedRows) continue;
    count++;
    const [recipients] = await pool.query('SELECT id FROM users WHERE id IN (?,?) AND role=\'teacher\'',
      [request.requested_by, request.class_teacher_id]);
    for (const recipient of recipients) {
      await notifyTeacher(recipient.id, 'হাজিরার অনুরোধের সময় শেষ', 'নির্ধারিত হাজিরার সময় শেষ হওয়ায় অনুরোধটি মেয়াদোত্তীর্ণ হয়েছে।', request.id,
        'attendance_access_expired');
    }
  }
  return count;
}

module.exports = { dhakaEndEpoch, requestExpiry, isExpired, notifyTeacher, expirePendingRequests };
