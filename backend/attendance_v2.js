/**
 * attendance_v2.js — shared helpers for the v2 attendance module.
 *
 * Windows are DERIVED FROM THE ROUTINE time-slots (not hardcoded):
 *   morning  = the 1st teaching slot of the day (class-teacher present-call)
 *   afternoon = the 5th teaching slot (the "5th period" afternoon verify)
 * Bangladesh weekend = Friday + Saturday.
 * Percent = present (LATE counts present) / (school days - leave days).
 */
const pool = require('./db');
const { ymd } = require('./dates');

function dhakaDate(d = new Date()) {
  return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
}

// 0=Sun .. 6=Sat. Routine `day` uses the same 0..4 (Sun..Thu).
function dow(dateStr) {
  return new Date(dateStr + 'T12:00:00Z').getUTCDay();
}
function isWeekend(dateStr) {
  const d = dow(dateStr);
  return d === 5 || d === 6; // Friday, Saturday
}

function nowDhakaMinutes(d = new Date()) {
  const s = d.toLocaleTimeString('en-GB', {
    timeZone: 'Asia/Dhaka', hour12: false, hour: '2-digit', minute: '2-digit',
  });
  const [h, m] = s.split(':').map(Number);
  return h * 60 + m;
}
function hmToMin(hm) {
  const [h, m] = String(hm || '0:0').split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}
function hhmm(s) { return String(s || '').slice(0, 5); }

async function getSlots() {
  const [rows] = await pool.query(
    `SELECT id, slot_order, label, start_time, end_time
     FROM time_slots WHERE COALESCE(is_break,false)=false ORDER BY slot_order`);
  return rows;
}

/**
 * { morning:slot|null, afternoon:slot|null } from the routine time-slots.
 * "5th period" = the class that STARTS AT/after 14:00 (2:00 PM) — the first
 * teaching slot after the midday break (CLASS_5 @ 14:00 in this routine).
 * NOTE: slot_order is NOT the period number (slot_order=1 is ASSEMBLY, a break),
 * so we must match on start_time, never on slot_order.
 */
async function sessionWindows() {
  const slots = await getSlots();
  const morning = slots[0] || null;
  const afternoon =
    slots.find((s) => hmToMin(hhmm(s.start_time)) >= 14 * 60) || null;
  return { slots, morning, afternoon };
}

/** Is `now` inside the given slot's routine time window? */
function inWindow(slot, now = new Date()) {
  if (!slot) return false;
  const cur = nowDhakaMinutes(now);
  return cur >= hmToMin(hhmm(slot.start_time)) && cur <= hmToMin(hhmm(slot.end_time));
}

function percent(present, schoolDays, leave) {
  const denom = (Number(schoolDays) || 0) - (Number(leave) || 0);
  if (denom <= 0) return 0;
  return Math.round((Number(present) / denom) * 10000) / 100;
}

/** Count days where status counts as "present for attendance %" */
function isPresentForPercent(status) {
  return status === 'present' || status === 'late' || status === 'early_departure_with_leave' || status === 'early_departure_no_leave';
}

async function getSetting(key, def) {
  try {
    const [[row]] = await pool.query('SELECT value FROM attendance_setting WHERE key=?', [key]);
    return row ? row.value : def;
  } catch { return def; }
}

async function getTeacherTokens(userIds) {
  const ids = [...new Set((userIds || []).filter(Boolean))];
  if (!ids.length) return [];
  try {
    const [rows] = await pool.query(
      `SELECT DISTINCT fcm_token FROM device_tokens WHERE active=1 AND user_id IN (?)`, [ids]);
    return rows.map(r => r.fcm_token).filter(Boolean);
  } catch { return []; }
}
async function getAdminTokens() {
  try {
    const [rows] = await pool.query(
      `SELECT DISTINCT dt.fcm_token FROM device_tokens dt
       JOIN users u ON u.id = dt.user_id WHERE dt.active=1 AND u.role='admin'`);
    return rows.map(r => r.fcm_token).filter(Boolean);
  } catch { return []; }
}

// Routine day = 0..4 (Sun..Thu). 5th-period teacher(s) for a class on a date.
// "5th period" = the slot starting at/after 14:00 (2:00 PM), NOT slot_order=5.
async function fifthPeriodTeachers(classId, dateStr) {
  const d = dow(dateStr);
  if (d > 4) return [];
  try {
    const { afternoon } = await sessionWindows();
    if (!afternoon) return [];
    const [rows] = await pool.query(
      `SELECT DISTINCT r.teacher_id, ts.slot_order, ts.start_time, ts.end_time
       FROM routines r
       JOIN time_slots ts ON ts.id = r.time_slot_id
       LEFT JOIN routine_sections rs ON rs.routine_id = r.id
       LEFT JOIN routine_groups rg ON rg.routine_id = r.id
       WHERE r.day = ? AND r.time_slot_id = ?
         AND (rs.class_id = ? OR rg.class_id = ?)`,
      [d, afternoon.id, classId, classId]);
    return rows;
  } catch { return []; }
}

/** Does this class even have a 5th-period lesson on this date?
 *  True if a P5 routine exists that day, or a P5 row was already recorded.
 *  Used so morning-only classes aren't permanently scored 'absent'. */
async function p5Applicable(classId, dateStr) {
  if (!classId) return true;
  try {
    const t = await fifthPeriodTeachers(classId, dateStr);
    if (t.length) return true;
    const [[r]] = await pool.query(
      `SELECT 1 AS x FROM attendance a JOIN students s ON s.id=a.student_id
       WHERE s.class_id=? AND a.date=? AND a.session='p5' LIMIT 1`,
      [classId, dateStr]);
    return !!r;
  } catch { return true; }
}

/** Daily final state from the two session statuses. Late counts as present.
 *  p5Known=false → class has no 5th period that day, so morning alone decides.
 *  p5Known=true  → both sessions must be recorded (morning leave is decisive)
 *                  before the day is final; otherwise null = still pending.
 *  
 *  New statuses:
 *  - early_departure_with_leave  → present for attendance % (excused early departure)
 *  - early_departure_no_leave    → present for attendance % (unexcused early departure, NOT absent)
 *  Both are stored in student record and appear on report card. */
function dayFinal(m, p, p5Known = true) {
  if (m === null && p === null) return null;
  if (!p5Known) {
    if (m === null) return null;
    if (m === 'leave') return 'leave';
    if (m === 'early_departure_with_leave' || m === 'early_departure_no_leave') return 'present';
    if (m === 'present' || m === 'late') return 'present';
    if (m === 'absent') return 'absent';
    return m;
  }
  // Morning leave or early departure covers the whole day
  if (m === 'leave' || m === 'early_departure_with_leave') return 'leave';
  if (m === 'early_departure_no_leave') return 'present';
  if (p === 'leave' || p === 'early_departure_with_leave') return 'leave';
  if (p === 'early_departure_no_leave') return 'present';
  if (m === null || p === null) return null;
  const mp = m === 'present' || m === 'late';
  const pp = p === 'present' || p === 'late' || p === 'early_departure_no_leave';
  return (mp && pp) ? 'present' : 'absent';
}

/** Recompute + store the monthly summary for one student. */
async function rebuildSummary(studentId, year, month) {
  const from = `${year}-${String(month).padStart(2, '0')}-01`;
  const [rows] = await pool.query(
    `SELECT date, session, status FROM attendance
     WHERE student_id=? AND date >= ?::date AND date < (?::date + INTERVAL '1 month')`,
    [studentId, from, from]);
  let classId = null;
  try {
    const [[st]] = await pool.query(`SELECT class_id FROM students WHERE id=?`, [studentId]);
    classId = st ? st.class_id : null;
  } catch { /* fall back to "p5 applicable" */ }
  const p5Cache = new Map();
  const known = async (d) => {
    if (!p5Cache.has(d)) p5Cache.set(d, classId ? await p5Applicable(classId, d) : true);
    return p5Cache.get(d);
  };
  const byDay = new Map();
  for (const r of rows) {
    const d = ymd(r.date);
    if (!byDay.has(d)) byDay.set(d, {});
    byDay.get(d)[r.session] = r.status;
  }
  let present = 0, late = 0, leave = 0, earlyWithLeave = 0, earlyNoLeave = 0, absent = 0, school = 0;
  for (const [d, s] of byDay) {
    const f = dayFinal(s.morning || null, s.p5 || null, await known(d));
    if (f === null) continue;
    school++;
    if (f === 'leave') leave++;
    else if (f === 'present') {
      const m = s.morning, p = s.p5;
      if (m === 'early_departure_with_leave' || p === 'early_departure_with_leave') earlyWithLeave++;
      else if (m === 'early_departure_no_leave' || p === 'early_departure_no_leave') earlyNoLeave++;
      else if (m === 'late' || p === 'late') late++;
      else present++;
    } else absent++;
  }
  const pct = percent(present + late + earlyWithLeave + earlyNoLeave, school, leave);
await pool.query(
     `INSERT INTO attendance_summary (student_id,year,month,present_days,late_days,leave_days,absent_days,school_days,percent,early_departure_with_leave,early_departure_no_leave,updated_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?, now())
      ON CONFLICT (student_id,year,month) DO UPDATE SET
        present_days=EXCLUDED.present_days, late_days=EXCLUDED.late_days, leave_days=EXCLUDED.leave_days,
        absent_days=EXCLUDED.absent_days, school_days=EXCLUDED.school_days, percent=EXCLUDED.percent,
        early_departure_with_leave=EXCLUDED.early_departure_with_leave,
        early_departure_no_leave=EXCLUDED.early_departure_no_leave, updated_at=now()`,
    [studentId, year, month, present, late, leave, absent, school, pct, earlyWithLeave, earlyNoLeave]);
  return { present_days: present, late_days: late, leave_days: leave, early_departure_with_leave: earlyWithLeave, early_departure_no_leave: earlyNoLeave, absent_days: absent, school_days: school, percent: pct };
}

/** Cron: remind CT + 5th-period teacher once for any session not yet taken.
 *  Runs every minute via cron. Two notification points:
 *  1. 30 minutes AFTER window START -> notify CT + admin to-do if not submitted
 *  2. After window END -> final reminder if still not submitted */
async function runReminders() {
  const today = dhakaDate();
  if (isWeekend(today)) return 0;
  const now = new Date();
  const cur = nowDhakaMinutes(now);
  const rTime = hmToMin(await getSetting('reminder_time', '10:30'));
  const { queuePush } = require('./fcm');
  const windows = await sessionWindows();
  const [classes] = await pool.query(
    `SELECT c.id, c.name, c.section, c.teacher_id FROM classes c ORDER BY c.id`);
  let sent = 0;
  for (const c of classes) {
    const [[day]] = await pool.query(`SELECT * FROM attendance_day WHERE class_id=? AND date=?`, [c.id, today]);
    if (day && day.is_holiday && !day.open_override) continue;
    for (const sess of ['morning', 'p5']) {
      const slot = sess === 'p5' ? windows.afternoon : windows.morning;
      if (!slot) continue;
      const slotStart = hmToMin(hhmm(slot.start_time));
      const slotEnd = hmToMin(hhmm(slot.end_time));
      const thirtyAfterStart = slotStart + 30;

      // Check if already taken
      const [[taken]] = await pool.query(
        `SELECT COUNT(*) AS n FROM attendance WHERE date=? AND session=? AND student_id IN (SELECT id FROM students WHERE class_id=?)`,
        [today, sess, c.id]);
      if (Number(taken.n) > 0) continue;

      // ---- Point 1: 30 min after window start -> notify CT + admin to-do
      if (cur >= thirtyAfterStart && cur < thirtyAfterStart + 5) { // fire once in the 30-min mark window
        const [[already30]] = await pool.query(
          `SELECT id FROM attendance_audit WHERE class_id=? AND date=? AND session=? AND action='reminder_30min' LIMIT 1`,
          [c.id, today, sess]);
        if (!already30) {
          await pool.query(
            `INSERT INTO attendance_audit (class_id,date,session,action,detail) VALUES (?,?,?,?,?)`,
            [c.id, today, sess, 'reminder_30min', '30 min after window start, not submitted']);
          // Notify class teacher
          const ctTokens = await getTeacherTokens([c.teacher_id].filter(Boolean));
          if (ctTokens.length) {
            await queuePush(ctTokens, '⏰ হাজিরা বাকি (৩০ মিনিট বিতিক্রম)',
              `${c.name}${c.section ? ' ' + c.section : ''} — ${sess === 'p5' ? '৫ম পিরিয়ড' : 'সকাল'}ের হাজিরা ৩০ মিনিট ধরে নেওয়া হয়নি।`,
              { type: 'attendance', kind: 'reminder_30min', session: sess });
          }
          // Notify admin (to-do)
          const adminTokens = await getAdminTokens();
          if (adminTokens.length) {
            await queuePush(adminTokens, '📋 Admin To-Do: হাজিরা বাকি',
              `${c.name}${c.section ? ' ' + c.section : ''} — ${sess === 'p5' ? '৫ম পিরিয়ড' : 'সকাল'}ের হাজিরা ৩০ মিনিট ধরে নেওয়া হয়নি। Класс teacher-কে ফোন দিন।`,
              { type: 'attendance', kind: 'admin_todo', session: sess, class_id: c.id });
          }
          sent++;
        }
      }

      // ---- Point 2: After window END -> final reminder
      if (cur < slotEnd) continue;
      if (sess === 'morning' && cur < rTime) continue;
      const [[already]] = await pool.query(
        `SELECT id FROM attendance_audit WHERE class_id=? AND date=? AND session=? AND action='reminder' LIMIT 1`,
        [c.id, today, sess]);
      if (already) continue;
      await pool.query(
        `INSERT INTO attendance_audit (class_id,date,session,action,detail) VALUES (?,?,?,?,?)`,
        [c.id, today, sess, 'reminder', 'auto']);
      // recipients: CT + 5th-period teachers
      const p5 = (await fifthPeriodTeachers(c.id, today)).map(r => r.teacher_id);
      const ids = [c.teacher_id, ...p5].filter(Boolean);
      const tokens = await getTeacherTokens(ids);
      if (tokens.length) {
        await queuePush(tokens, '⏰ হাজিরা বাকি',
          `${c.name}${c.section ? ' ' + c.section : ''} — ${sess === 'p5' ? '৫ম পিরিয়ড' : 'সকাল'}ের হাজিরা এখনো নেওয়া হয়নি।`,
          { type: 'attendance', kind: 'reminder', session: sess });
      }
      sent++;
    }
  }
  return sent;
}

/** Cron: rebuild this month's summaries for all active students. */
async function runRollup() {
  const today = dhakaDate();
  const y = Number(today.slice(0, 4));
  const m = Number(today.slice(5, 7));
  const [students] = await pool.query(`SELECT id FROM students WHERE (status IS NULL OR status='active')`);
  for (const s of students) {
    try { await rebuildSummary(s.id, y, m); } catch (e) { /* skip */ }
  }
  return students.length;
}

module.exports = {
  dhakaDate, dow, isWeekend, nowDhakaMinutes, hmToMin, hhmm,
  getSlots, sessionWindows, inWindow, percent, getSetting,
  getTeacherTokens, getAdminTokens, fifthPeriodTeachers, p5Applicable,
  dayFinal, rebuildSummary, runReminders, runRollup,
};
