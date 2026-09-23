/*
 * Background "Upcoming Class" alert service.
 * ===========================================
 * Fires an FCM push for every teacher routine period that is DUE right now:
 *   - 'reminder'  : exactly when the period is 5 minutes away  -> single beep ("Bep")
 *   - 'start'     : exactly when the period begins            -> double beep ("Bep-Bep")
 *
 * Rules:
 *   - Weekdays only (Sun..Thu = routine.day 0..4). Fri/Sat are off.
 *   - Break slots (Assembly / Tiffin) are skipped.
 *   - Idempotent: routine_notification_log has UNIQUE(routine_id, event_date, event),
 *     so a request can never double-push for the same period/day.
 *   - Bangladesh timezone (UTC+6, no DST).
 *
 * The trigger runs every minute via a Vercel cron hitting /api/cron/routine-alerts,
 * and also as a local setInterval when started by `node server.js`.
 */

const pool = require('./db');
const { sendPushToTokens } = require('./fcm');

const TZ_OFF = 6 * 60 * 60 * 1000; // Asia/Dhaka UTC+6, no DST
const REMINDER_BEFORE_MS = 5 * 60 * 1000;

function bangladeshNow() {
  const shifted = Date.now() + TZ_OFF; // value whose UTC view == BD wall clock
  const d = new Date(shifted);
  return {
    epoch: Date.now(),
    shifted,
    day: d.getUTCDay(),                // 0=Sun .. 6=Sat
    dateStr: d.toISOString().slice(0, 10),
    dayStartShifted: Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())
  };
}

function timeOnlyToMs(hm) {
  const [h, m] = String(hm || '00:00:00').split(':').map(Number);
  return (h * 60 + (m || 0)) * 60 * 1000;
}

function fmtTime(hm) {
  return String(hm || '').slice(0, 5);
}

async function runRoutineAlertCheck() {
  const t = bangladeshNow();
  // Fri(5)/Sat(6) are off days — no periods run.
  if (t.day === 5 || t.day === 6) return { checked: 0, sent: 0, skipped: 'weekend', at: t.dateStr };

  const todayStartShifted = t.dayStartShifted;
  const nowShifted = t.shifted;

  const [routines] = await pool.query(
    `SELECT r.id, r.teacher_id, r.room, ts.label AS slot_label, ts.start_time, ts.end_time,
            s.name AS subject_name, u.name AS teacher_name,
            (SELECT string_agg(DISTINCT c.name || CASE WHEN rs.section IS NOT NULL THEN ' (' || rs.section || ')' ELSE '' END, ', ')
               FROM routine_sections rs JOIN classes c ON rs.class_id = c.id WHERE rs.routine_id = r.id) AS sections_label,
            (SELECT string_agg(DISTINCT c.name || ' (' || rg.group_name || ')', ', ')
               FROM routine_groups rg JOIN classes c ON rg.class_id = c.id WHERE rg.routine_id = r.id) AS groups_label
     FROM routines r
     JOIN time_slots ts ON r.time_slot_id = ts.id
     JOIN subjects s ON r.subject_id = s.id
     JOIN users u ON r.teacher_id = u.id
     WHERE r.day = $1 AND ts.is_break = FALSE`,
    [t.day]
  );

  let checked = 0, sent = 0, logErr = 0;
  for (const r of routines) {
    const startShifted = todayStartShifted + timeOnlyToMs(r.start_time);
    const endShifted = todayStartShifted + timeOnlyToMs(r.end_time);
    let event = null;
    if (nowShifted >= startShifted - REMINDER_BEFORE_MS && nowShifted < startShifted) event = 'reminder';
    else if (nowShifted >= startShifted && nowShifted < endShifted) event = 'start';
    if (!event) continue;
    checked++;

    const [ins] = await pool.query(
      `INSERT INTO routine_notification_log (routine_id, event_date, event)
       VALUES ($1,$2,$3) ON CONFLICT (routine_id, event_date, event) DO NOTHING`,
      [r.id, t.dateStr, event]
    );
    if (!ins.rowCount) { continue; } // already alerted for this event today

    const classLabel = (r.groups_label || r.sections_label || '');
    const title = event === 'reminder'
      ? `⏰ Class in 5 minutes`
      : `🔴 Class started now`;
    const body = event === 'reminder'
      ? `${r.subject_name} — ${classLabel} · ${r.slot_label} ${fmtTime(r.start_time)}${r.room ? ' • Room ' + r.room : ''}`
      : `${r.subject_name} — ${classLabel} · ${r.slot_label} started${r.room ? ' • Room ' + r.room : ''}`;
    const data = {
      type: 'class_alert',
      event,
      tone: event === 'reminder' ? 'single' : 'double',
      routine_id: String(r.id),
      subject: r.subject_name,
      class_label: classLabel || '-',
      slot_label: r.slot_label || '',
      start_time: fmtTime(r.start_time),
      room: r.room || ''
    };

    const [tokens] = await pool.query(
      `SELECT dt.fcm_token FROM device_tokens dt
       JOIN users u ON dt.user_id = u.id
       WHERE u.role='teacher' AND u.id = $1 AND dt.active = 1`,
      [r.teacher_id]
    );
    if (tokens.length) {
      const res = await sendPushToTokens(tokens.map(x => x.fcm_token), title, body, data);
      sent += res.sent || 0;
    }
  }
  return { checked, sent, logErr, at: t.dateStr };
}

let intervalHandle = null;
function startAlertService() {
  if (intervalHandle) return intervalHandle;
  // run soon after boot, then every 30s (cheap, deduped) when running as a long-lived process
  runRoutineAlertCheck().catch(e => console.error('routine-alert boot:', e.message));
  intervalHandle = setInterval(() => {
    runRoutineAlertCheck().catch(e => console.error('routine-alert tick:', e.message));
  }, 30 * 1000);
  return intervalHandle;
}

module.exports = { runRoutineAlertCheck, startAlertService };