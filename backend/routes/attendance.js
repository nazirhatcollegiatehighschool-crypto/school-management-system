/**
 * routes/attendance.js — v2 attendance module.
 *
 * Roles:
 *   teacher  — take attendance for classes where they are the class teacher
 *              (morning), the 5th-period teacher (afternoon), or hold a
 *              one-day delegation. Request reopens; mark holidays; open off-days.
 *   admin    — live board, reopen approvals/unlock, reports, audit, settings,
 *              delegations, direct edits, export.
 *   guardian — own child's record + %, who took it, notes.
 *
 * Sessions: morning (1st routine slot) and afternoon (5th routine slot).
 * Statuses: present | absent | late | leave   (LATE counts as present in %;
 *           LEAVE is excluded from the denominator).
 */
const router = require('express').Router();
const pool = require('../db');
const { auth } = require('../middleware/auth');
const { queuePush, getGuardianTokens } = require('../fcm');
const { ymd } = require('../dates');
const H = require('../attendance_v2');
const AttendanceAccess = require('../lib/attendance_access');

const STATUSES = ['present', 'absent', 'late', 'leave', 'early_departure_with_leave', 'early_departure_no_leave'];

// ---------------------------------------------------------------- helpers
async function getClass(classId) {
  const [[c]] = await pool.query(
    `SELECT id, name, section, group_name, teacher_id FROM classes WHERE id=?`, [classId]);
  return c || null;
}
async function getDay(classId, date) {
  const [[d]] = await pool.query(
    `SELECT * FROM attendance_day WHERE class_id=? AND date=?`, [classId, date]);
  return d || null;
}
async function getLock(classId, date, session) {
  const [[l]] = await pool.query(
    `SELECT * FROM attendance_lock WHERE class_id=? AND date=? AND session=?`, [classId, date, session]);
  return l || null;
}
async function delegationFor(classId, date, session, userId) {
  const [[d]] = await pool.query(
    `SELECT * FROM attendance_delegation
     WHERE class_id=? AND date=? AND session=? AND granted_to=? AND revoked=0 AND used=0
       AND (expires_at_epoch IS NULL OR expires_at_epoch>?)
     ORDER BY id DESC LIMIT 1`, [classId, date, session, userId, Date.now()]);
  return d || null;
}
async function fifthTeacherIds(classId, date) {
  const rows = await H.fifthPeriodTeachers(classId, date);
  return rows.map(r => r.teacher_id);
}

/** Effective open/closed state of a class+session at `now`. */
async function openState(classId, date, session, now = new Date()) {
  const [day, lock, windows, globalHoliday] = await Promise.all([
    getDay(classId, date), getLock(classId, date, session), H.sessionWindows(), H.getGlobalHoliday(date),
  ]);
  const slot = session === 'p5' ? windows.afternoon : windows.morning;
  const reopened = !!(lock && lock.reopen_until && new Date(lock.reopen_until) > now);
  if (lock && lock.locked && !reopened) {
    return { open: false, reason: 'locked', locked: true, slot, holiday: !!(day && day.is_holiday) || globalHoliday.holiday, occasion: day && day.occasion || globalHoliday.title };
  }
  if (!slot) {
    return { open: false, reason: session === 'p5' ? 'no_p5' : 'no_slot', slot };
  }
  const weekend = H.isWeekend(date);
  const holiday = !!(day && day.is_holiday) || globalHoliday.holiday;
  const occasion = day && day.occasion || globalHoliday.title;
  const override = !!(day && day.open_override);
  if (reopened) return { open: true, reason: 'reopened', slot, reopen_until: lock.reopen_until };
  if (weekend && !override) return { open: false, reason: 'weekend', slot, weekend: true };
  if (holiday && !override) return { open: false, reason: 'holiday', slot, holiday: true, occasion };
  if (override) return { open: true, reason: 'opened', slot };
  // No time limit before submission: on a valid school day the session stays
  // open from the start of the day until the teacher submits (which locks it).
  // Routine windows are only used for reminders/to-do, never to block entry.
  return { open: true, reason: 'window', slot };
}


async function canTake(classId, date, session, user) {
  if (user.role === 'admin') return { ok: true, how: 'admin' };
  const c = await getClass(classId);
  if (!c) return { ok: false, reason: 'class not found' };
  const deleg = await delegationFor(classId, date, session, user.id);
  if (deleg) return { ok: true, how: 'delegate', delegation: deleg };
  if (session === 'morning') {
    if (c.teacher_id === user.id) return { ok: true, how: 'ct' };
  } else {
    // afternoon = 5th-period call. Only the teacher who has the 5th period
    // in this class (per routine) may take it — NOT the class teacher unless
    // they also happen to teach the 5th period here.
    const ids = await fifthTeacherIds(classId, date);
    if (ids.includes(user.id)) return { ok: true, how: 'p5' };
  }
  return { ok: false, reason: session === 'p5'
    ? '৫ম পিরিয়ডের শিক্ষক বা শ্রেণি শিক্ষক ছাড়া দুপুরের হাজিরা নেওয়া যাবে না।'
    : 'শুধু শ্রেণি শিক্ষক এই হাজিরা নিতে পারবেন।' };
}

async function canView(classId, date, user, session = 'morning') {
  if (user.role === 'admin') return true;
  const c = await getClass(classId);
  if (!c) return false;
  const ids = await fifthTeacherIds(classId, date);
  const isP5 = ids.includes(user.id);
  if (session === 'p5') {
    // The 5th-period teacher records departures; the class teacher may review
    // the completed same-day departure roster from their attendance screen.
    return isP5 || Number(c.teacher_id) === Number(user.id);
  }
  // morning: class teacher or 5th-period teacher (to see their own class)
  return c.teacher_id === user.id || isP5;
}

function validAttendanceDate(date) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(date || '')) && String(date) === H.dhakaDate();
}

router.get('/access/options', auth(['teacher']), async (req, res) => {
  try {
    const [classes] = await pool.query(
      `SELECT c.id, c.name, c.section, c.group_name, c.teacher_id, u.name AS class_teacher_name
       FROM classes c LEFT JOIN users u ON u.id=c.teacher_id ORDER BY c.name,c.section`);
    const [teachers] = await pool.query(
      "SELECT id,name,phone FROM users WHERE role='teacher' AND active=1 AND id<>? ORDER BY name", [req.user.id]);
    res.json({ classes, teachers, date: H.dhakaDate() });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/access-requests', auth(['teacher']), async (req, res) => {
  const classId = Number(req.body?.class_id);
  const date = String(req.body?.date || '');
  const session = req.body?.session === 'p5' ? 'p5' : req.body?.session === 'morning' ? 'morning' : null;
  if (!classId || !validAttendanceDate(date) || !session) {
    return res.status(400).json({ error: 'আজকের class এবং daily বা ৫ম পিরিয়ড বেছে নিন।' });
  }
  try {
    const [[cls]] = await pool.query('SELECT id,name,section,teacher_id FROM classes WHERE id=?', [classId]);
    if (!cls) return res.status(404).json({ error: 'Class not found' });
    if (!cls.teacher_id || Number(cls.teacher_id) === Number(req.user.id)) {
      return res.status(400).json({ error: 'এই class-এর আলাদা class teacher নেই বা আপনি নিজেই class teacher।' });
    }
    const [[assigned]] = await pool.query("SELECT id FROM users WHERE id=? AND role='teacher' AND active=1", [cls.teacher_id]);
    if (!assigned) return res.status(409).json({ error: 'এই class-এর class teacher বর্তমানে সক্রিয় নন।' });
    const expiresAt = await AttendanceAccess.requestExpiry(date, session);
    if (!expiresAt || expiresAt <= Date.now()) return res.status(409).json({ error: 'এই হাজিরার সময়সীমা শেষ।' });
    const [[open]] = await pool.query(
      `SELECT id,expires_at_epoch FROM attendance_access_requests
       WHERE class_id=? AND attendance_date=? AND session=? AND requested_by=? AND status='pending'
       ORDER BY id DESC LIMIT 1`, [classId, date, session, req.user.id]);
    if (open && Number(open.expires_at_epoch) > Date.now()) {
      return res.status(409).json({ error: 'এই class ও period-এর একটি request এখনও pending আছে।', request_id: open.id });
    }
    if (open) await pool.query("UPDATE attendance_access_requests SET status='expired',decided_at=NOW() WHERE id=? AND status='pending'", [open.id]);
    const [inserted] = await pool.query(
      `INSERT INTO attendance_access_requests
       (class_id,class_teacher_id,requested_by,attendance_date,session,status,expires_at_epoch)
       VALUES (?,?,?,?,?,'pending',?)`,
      [classId, cls.teacher_id, req.user.id, date, session, expiresAt]);
    const id = inserted.insertId;
    const title = 'হাজিরার access অনুরোধ';
    const body = `${req.user.name} ${cls.name} ${cls.section || ''} — ${session === 'p5' ? '৫ম পিরিয়ড' : 'দৈনিক'} হাজিরা নেওয়ার অনুমতি চেয়েছেন।`;
    await pool.query(
      `INSERT INTO notifications (class_id,title,body,type,target_type,target_user_id,related_id,created_by)
       VALUES (?,?,?,'attendance','teacher',?,?,?)`, [classId, title, body, cls.teacher_id, id, req.user.id]);
    const tokens = await H.getTeacherTokens([cls.teacher_id]);
    queuePush(tokens, title, body, { type: 'attendance', kind: 'attendance_access_request', request_id: id, class_id: classId });
    await audit(classId, date, session, 'access_request', `request ${id} from teacher ${req.user.id}`, req.user.id);
    res.status(201).json({ ok: true, id, status: 'pending', expires_at_epoch: expiresAt });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/access-requests', auth(['teacher']), async (req, res) => {
  const box = req.query.box === 'sent' ? 'sent' : 'inbox';
  try {
    await AttendanceAccess.expirePendingRequests();
    const column = box === 'sent' ? 'r.requested_by' : 'r.class_teacher_id';
    const [rows] = await pool.query(
      `SELECT r.*, c.name AS class_name,c.section,
              requester.name AS requester_name, ct.name AS class_teacher_name
       FROM attendance_access_requests r JOIN classes c ON c.id=r.class_id
       JOIN users requester ON requester.id=r.requested_by
       JOIN users ct ON ct.id=r.class_teacher_id
       WHERE ${column}=? ORDER BY r.id DESC LIMIT 100`, [req.user.id]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/access-requests/:id/decision', auth(['teacher']), async (req, res) => {
  const approve = req.body?.decision === 'accept';
  if (!approve && req.body?.decision !== 'reject') return res.status(400).json({ error: 'decision must be accept or reject' });
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [[request]] = await conn.query('SELECT * FROM attendance_access_requests WHERE id=? FOR UPDATE', [req.params.id]);
    if (!request || Number(request.class_teacher_id) !== Number(req.user.id)) {
      await conn.rollback(); return res.status(404).json({ error: 'Pending request not found.' });
    }
    const [[cls]] = await conn.query('SELECT teacher_id FROM classes WHERE id=?', [request.class_id]);
    if (!cls || Number(cls.teacher_id) !== Number(req.user.id)) {
      await conn.rollback(); return res.status(403).json({ error: 'বর্তমান class teacher ছাড়া সিদ্ধান্ত নেওয়া যাবে না।' });
    }
    if (request.status !== 'pending') {
      await conn.rollback(); return res.status(409).json({ error: `Request ${request.status}.` });
    }
    if (Number(request.expires_at_epoch) <= Date.now()) {
      await conn.query("UPDATE attendance_access_requests SET status='expired',decided_at=NOW() WHERE id=?", [request.id]);
      await conn.commit();
      await AttendanceAccess.notifyTeacher(request.requested_by, 'হাজিরার অনুরোধের সময় শেষ', 'অনুরোধটি মেয়াদোত্তীর্ণ হয়েছে।', request.id, 'attendance_access_expired');
      return res.status(409).json({ error: 'সময় শেষ—এই request আর অনুমোদন করা যাবে না।', status: 'expired' });
    }
    let delegationId = null;
    if (approve) {
      const [delegation] = await conn.query(
        `INSERT INTO attendance_delegation (class_id,date,session,granted_by,granted_to,expires_at_epoch)
         VALUES (?,?,?,?,?,?)`, [request.class_id, request.attendance_date, request.session, req.user.id, request.requested_by, request.expires_at_epoch]);
      delegationId = delegation.insertId;
    }
    const status = approve ? 'accepted' : 'rejected';
    await conn.query(
      `UPDATE attendance_access_requests SET status=?,decided_by=?,decided_at=NOW(),delegation_id=?
       WHERE id=? AND status='pending'`, [status, req.user.id, delegationId, request.id]);
    await conn.commit();
    const title = approve ? 'হাজিরার অনুরোধ অনুমোদিত' : 'হাজিরার অনুরোধ প্রত্যাখ্যাত';
    const body = approve ? 'আপনি নির্বাচিত class ও period-এর হাজিরা নিতে পারবেন।' : 'Class teacher আপনার হাজিরার অনুরোধ গ্রহণ করেননি।';
    await AttendanceAccess.notifyTeacher(request.requested_by, title, body, request.id, `attendance_access_${status}`);
    await audit(request.class_id, request.attendance_date, request.session, `access_${status}`, `request ${request.id}`, req.user.id);
    res.json({ ok: true, status, delegation_id: delegationId });
  } catch (err) {
    try { await conn.rollback(); } catch (_) {}
    console.error(err); res.status(500).json({ error: 'Server error' });
  } finally { conn.release(); }
});

router.post('/delegations', auth(['teacher']), async (req, res) => {
  const classId = Number(req.body?.class_id), teacherId = Number(req.body?.teacher_id);
  const date = String(req.body?.date || ''), session = req.body?.session === 'p5' ? 'p5' : req.body?.session === 'morning' ? 'morning' : null;
  if (!classId || !teacherId || !validAttendanceDate(date) || !session) return res.status(400).json({ error: 'আজকের class, teacher এবং attendance period দিন।' });
  try {
    const [[cls]] = await pool.query('SELECT id,name,teacher_id FROM classes WHERE id=?', [classId]);
    if (!cls) return res.status(404).json({ error: 'Class not found' });
    if (Number(cls.teacher_id) !== Number(req.user.id)) return res.status(403).json({ error: 'শুধু class teacher delegation দিতে পারবেন।' });
    if (teacherId === Number(req.user.id)) return res.status(400).json({ error: 'নিজেকে delegate করা যাবে না।' });
    const [[teacher]] = await pool.query("SELECT id,name FROM users WHERE id=? AND role='teacher' AND active=1", [teacherId]);
    if (!teacher) return res.status(404).json({ error: 'সক্রিয় teacher পাওয়া যায়নি।' });
    const expiresAt = await AttendanceAccess.requestExpiry(date, session);
    if (!expiresAt || expiresAt <= Date.now()) return res.status(409).json({ error: 'এই হাজিরার সময়সীমা শেষ।' });
    const [created] = await pool.query(
      `INSERT INTO attendance_delegation (class_id,date,session,granted_by,granted_to,expires_at_epoch) VALUES (?,?,?,?,?,?)`,
      [classId, date, session, req.user.id, teacherId, expiresAt]);
    const title = 'হাজিরার দায়িত্ব দেওয়া হয়েছে';
    const body = `${cls.name} — ${session === 'p5' ? '৫ম পিরিয়ড' : 'দৈনিক'} হাজিরার জন্য আপনাকে delegate করা হয়েছে।`;
    await pool.query(`INSERT INTO notifications (class_id,title,body,type,target_type,target_user_id,related_id,created_by)
      VALUES (?,?,?,'attendance','teacher',?,?,?)`, [classId,title,body,teacherId,created.insertId,req.user.id]);
    queuePush(await H.getTeacherTokens([teacherId]), title, body, { type: 'attendance', kind: 'delegate', class_id: classId });
    await audit(classId,date,session,'delegate',`to user ${teacherId}`,req.user.id);
    res.status(201).json({ ok: true, delegation_id: created.insertId, expires_at_epoch: expiresAt });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/delegated-history', auth(['teacher']), async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT a.id,a.date,a.session,a.recorded_at,a.status,a.student_id,s.name AS student_name,s.roll,
              c.id AS class_id,c.name AS class_name,c.section,u.name AS class_teacher_name
       FROM attendance a JOIN students s ON s.id=a.student_id JOIN classes c ON c.id=s.class_id
       LEFT JOIN users u ON u.id=c.teacher_id
       WHERE a.recorded_by=? AND c.teacher_id<>? ORDER BY a.date DESC,a.session,a.id DESC LIMIT 300`,
      [req.user.id,req.user.id]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/delegated-history/:id', auth(['teacher']), async (req, res) => {
  try {
    const [[row]] = await pool.query(
      `SELECT a.id,a.date,a.session,a.recorded_at,a.status,a.remark,s.id AS student_id,s.name AS student_name,s.roll,
              c.id AS class_id,c.name AS class_name,c.section,u.name AS class_teacher_name
       FROM attendance a JOIN students s ON s.id=a.student_id JOIN classes c ON c.id=s.class_id
       LEFT JOIN users u ON u.id=c.teacher_id
       WHERE a.id=? AND a.recorded_by=? AND c.teacher_id<>?`, [req.params.id,req.user.id,req.user.id]);
    if (!row) return res.status(404).json({ error: 'এই attendance record আপনার history-তে নেই।' });
    res.json(row);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

async function audit(classId, date, session, action, detail, actorId) {
  try {
    await pool.query(
      `INSERT INTO attendance_audit (class_id,date,session,action,detail,actor_id) VALUES (?,?,?,?,?,?)`,
      [classId, date, session, action, detail, actorId]);
  } catch (e) { console.error('audit err', e.message); }
}
async function notifyRow(studentId, title, body, targetType, dedupKey) {
  try {
    await pool.query(
      `INSERT INTO notifications (student_id, title, body, type, target_type, dedup_key)
       VALUES (?,?,?,'attendance',?,?) ON CONFLICT (dedup_key) DO NOTHING`,
      [studentId, title, body, targetType, dedupKey]);
  } catch (e) { /* ignore */ }
}
const dayFinal = H.dayFinal;
const rebuildSummary = H.rebuildSummary;

// ============================================================ TEACHER
// GET /attendance/today — classes & sessions the teacher must handle today.
router.get('/today', auth(['teacher']), async (req, res) => {
  try {
    const date = req.query.date || H.dhakaDate();
    const now = new Date();
    const d = H.dow(date);
    const globalHoliday = await H.getGlobalHoliday(date);

    const rows = [];
    // class teacher classes
    const [ctClasses] = await pool.query(
      `SELECT id, name, section, group_name FROM classes WHERE teacher_id=?`, [req.user.id]);
    for (const c of ctClasses) rows.push({ ...c, role: 'ct' });

    // 5th-period classes (routine day 0..4). "5th period" = slot starting
    // at/after 14:00 (2:00 PM) — NOT slot_order=5 (slot_order=1 is ASSEMBLY).
    if (d <= 4) {
      const { afternoon } = await H.sessionWindows();
      if (afternoon) {
        const [p5] = await pool.query(
          `SELECT DISTINCT COALESCE(rs.class_id, rg.class_id) AS id
           FROM routines r
           LEFT JOIN routine_sections rs ON rs.routine_id=r.id
           LEFT JOIN routine_groups rg ON rg.routine_id=r.id
           WHERE r.teacher_id=? AND r.day=? AND r.time_slot_id=?`,
          [req.user.id, d, afternoon.id]);
        for (const r of p5) {
          if (!r.id) continue;
          if (rows.some(x => x.id === r.id)) continue;
          const c = await getClass(r.id);
          if (c) rows.push({ ...c, role: 'p5' });
        }
      }
    }
    // delegations for today
    const [dels] = await pool.query(
      `SELECT d.*, c.name, c.section, c.group_name FROM attendance_delegation d
       JOIN classes c ON c.id=d.class_id
       WHERE d.granted_to=? AND d.date=? AND d.revoked=0 AND d.used=0
         AND (d.expires_at_epoch IS NULL OR d.expires_at_epoch>?)`, [req.user.id, date, Date.now()]);
    for (const r of dels) {
      if (rows.some(x => x.id === r.class_id)) continue;
      rows.push({ id: r.class_id, name: r.name, section: r.section, group_name: r.group_name, role: 'delegate', delegation_session: r.session });
    }

    const out = [];
    for (const c of rows) {
      // determine which sessions this teacher owns for this class
      const isCT = c.teacher_id === req.user.id || c.role === 'ct';
      const p5Ids = await fifthTeacherIds(c.id, date);
      const isP5 = p5Ids.includes(req.user.id);
      // role 'ct' → only morning. role 'p5' → only afternoon.
      // role 'delegate' → the delegated session. If teacher is both CT and P5 for same class → both.
      let sessions = [];
      if (c.role === 'delegate' && c.delegation_session != null) {
        sessions = [c.delegation_session];
      } else if (c.role === 'p5') {
        sessions = ['p5'];
      } else if (c.role === 'ct') {
        sessions = ['morning'];
        // Show the P5 close-out to the class teacher so they can review both
        // departure groups after the 5th-period teacher submits.
        if (isP5 || await H.p5Applicable(c.id, date)) sessions.push('p5');
      }
      if (sessions.length === 0) continue;

      const day = await getDay(c.id, date);
      const result = {
        class_id: c.id, class_name: c.name, section: c.section, group_name: c.group_name,
        role: c.role, delegation_session: c.delegation_session || null,
        is_weekend: H.isWeekend(date), is_holiday: !!(day && day.is_holiday) || globalHoliday.holiday,
        occasion: day && day.occasion || globalHoliday.title,
        open_override: !!(day && day.open_override),
        total_students: 0, present: 0, absent: 0,
        is_p5_teacher: isP5,
      };

      for (const sess of sessions) {
        const state = await openState(c.id, date, sess, now);
        const [[cnt]] = await pool.query(
          `SELECT COUNT(*) AS total,
            SUM(CASE WHEN a.status IN ('present','late') THEN 1 ELSE 0 END) AS present,
            SUM(CASE WHEN a.status='absent' THEN 1 ELSE 0 END) AS absent
           FROM attendance a JOIN students s ON s.id=a.student_id
           WHERE s.class_id=? AND a.date=? AND a.session=?`, [c.id, date, sess]);
        const [[meta]] = await pool.query(
          `SELECT MAX(a.recorded_by) AS by_id, MAX(a.recorded_at) AS at
           FROM attendance a JOIN students s ON s.id=a.student_id
           WHERE s.class_id=? AND a.date=? AND a.session=?`, [c.id, date, sess]);
        result[sess] = {
          ...state, taken: !!meta.by_id || !!state.locked, taken_at: meta.at,
          total: Number(cnt.total || 0), present: Number(cnt.present || 0), absent: Number(cnt.absent || 0),
        };
        if (sess === 'p5') {
          const [[p5Counts]] = await pool.query(
            `SELECT SUM(CASE WHEN m.status='present' THEN 1 ELSE 0 END) AS eligible,
                    SUM(CASE WHEN m.status='present' AND p.status='early_departure_with_leave' THEN 1 ELSE 0 END) AS with_leave,
                    SUM(CASE WHEN m.status='present' AND p.status='early_departure_no_leave' THEN 1 ELSE 0 END) AS without_leave
             FROM students s
             LEFT JOIN attendance m ON m.student_id=s.id AND m.date=? AND m.session='morning'
             LEFT JOIN attendance p ON p.student_id=s.id AND p.date=? AND p.session='p5'
             WHERE s.class_id=? AND (s.status IS NULL OR s.status='active')`,
            [date, date, c.id]);
          const eligible = Number(p5Counts?.eligible || 0);
          const withLeave = Number(p5Counts?.with_leave || 0);
          const withoutLeave = Number(p5Counts?.without_leave || 0);
          result[sess].eligible = eligible;
          result[sess].with_leave = withLeave;
          result[sess].without_leave = withoutLeave;
          result[sess].stayed = state.locked ? Math.max(0, eligible - withLeave - withoutLeave) : 0;
        }
        if (!result.total_students) result.total_students = Number(cnt.total || 0);
      }
      out.push(result);
    }
    res.json({ date, weekend: H.isWeekend(date), classes: out });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// GET /attendance/class/:id?date=&session= — roster + meta for entry.
router.get('/class/:id', auth(['teacher', 'admin']), async (req, res) => {
  try {
    const classId = Number(req.params.id);
    const date = req.query.date || H.dhakaDate();
    const session = req.query.session === 'p5' ? 'p5' : 'morning';
    const c = await getClass(classId);
    if (!c) return res.status(404).json({ error: 'Class not found' });
    if (!(await canView(classId, date, req.user, session))) {
      return res.status(403).json({ error: 'এই ক্লাস দেখার অনুমতি নেই।' });
    }
    const [students] = await pool.query(
      `SELECT id AS student_id, name, roll FROM students
       WHERE class_id=? AND (status IS NULL OR status='active') ORDER BY roll`, [classId]);
    const [att] = await pool.query(
      `SELECT a.student_id, a.status, a.remark, a.recorded_by, a.recorded_at, u.name AS recorded_by_name
       FROM attendance a LEFT JOIN users u ON u.id=a.recorded_by
       WHERE a.date=? AND a.session=? AND a.student_id IN (SELECT id FROM students WHERE class_id=?)`,
      [date, session, classId]);
    const [morning] = await pool.query(
      `SELECT student_id, status, remark FROM attendance
       WHERE date=? AND session='morning' AND student_id IN (SELECT id FROM students WHERE class_id=?)`,
      [date, classId]);
    const attBy = new Map(att.map(a => [a.student_id, a]));
    const mBy = new Map(morning.map(a => [a.student_id, { status: a.status, remark: a.remark }]));
    const state = await openState(classId, date, session);
    const submitted = !!state.locked;
    const roster = students.map(s => {
      const a = attBy.get(s.student_id);
      const mData = mBy.get(s.student_id) || { status: null, remark: null };
      const ms = mData.status;
      // P5 roster = exactly the students marked PRESENT in the 1st period.
      // No morning attendance (or absent/late/leave) means not shown in P5.
      const eligible = ms === 'present';
      return {
        student_id: s.student_id, name: s.name, roll: s.roll,
        status: a ? a.status : null, remark: a ? a.remark : null,
        recorded_by_name: a ? a.recorded_by_name : null, recorded_at: a ? a.recorded_at : null,
        morning_status: ms, morning_remark: mData.remark,
        p5_eligible: eligible,
        p5_outcome: session === 'p5' && eligible
          ? (a ? a.status : submitted ? 'p5_stayed' : null)
          : null,
      };
    });
    const day = await getDay(classId, date);
    const globalHoliday = await H.getGlobalHoliday(date);
    const [[meta]] = await pool.query(
      `SELECT MAX(recorded_by) AS by_id, MAX(recorded_at) AS at FROM attendance
       WHERE date=? AND session=? AND student_id IN (SELECT id FROM students WHERE class_id=?)`,
      [date, session, classId]);
    const can = await canTake(classId, date, session, req.user);
    res.json({
      class: c, date, session, students: roster,
      state, can_take: can.ok, can_take_how: can.how || null,
      taken: roster.some(r => r.status != null) || submitted, taken_at: meta.at,
      holiday: !!(day && day.is_holiday) || globalHoliday.holiday,
      occasion: day && day.occasion || globalHoliday.title,
      open_override: !!(day && day.open_override),
    });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// POST /attendance/class/:id — save a session (idempotent via idem_key).
router.post('/class/:id', auth(['teacher', 'admin']), async (req, res) => {
  const classId = Number(req.params.id);
  const { date, session, records, idem_key } = req.body || {};
  const sess = session === 'p5' ? 'p5' : 'morning';
  if (!date || !Array.isArray(records)) return res.status(400).json({ error: 'date and records required' });
  try {
    const c = await getClass(classId);
    if (!c) return res.status(404).json({ error: 'Class not found' });
    const can = await canTake(classId, date, sess, req.user);
    if (!can.ok) return res.status(403).json({ error: can.reason });
    const state = await openState(classId, date, sess);
    // A submitted session is immutable through this endpoint for teachers and
    // admins alike. Admin history is read-only; any exceptional correction
    // must use the audited reopen workflow first.
    if (!state.open) {
      const msg = state.reason === 'locked' ? 'হাজিরা জমা হয়ে গেছে — reopen-এর জন্য admin-কে request দিন।'
        : state.reason === 'weekend' ? 'শনি/শুক্রবার school বন্ধ। Present call খুলে নিলে হাজিরা নেওয়া যাবে।'
        : state.reason === 'holiday' ? `আজ ছুটি${state.occasion ? ' (' + state.occasion + ')' : ''}।`
        : state.reason === 'outside' ? 'এই পিরিয়ডের সময় এখন নেই।' : 'এই মুহূর্তে হাজিরা নেওয়া যাবে না।';
      return res.status(403).json({ error: msg, closed: true, reason: state.reason });
    }
    // dedupe + validate
    const byId = new Map();
    for (const r of records) {
      if (!STATUSES.includes(r.status)) continue;
      byId.set(Number(r.student_id), r);
    }
    let unique = [...byId.values()];
    if (!unique.length && sess !== 'p5') {
      return res.status(400).json({ error: 'no valid records' });
    }
    // 5th period is an EARLY-DEPARTURE register: only students who were
    // marked Present in the 1st period can be recorded, and only the two
    // departure statuses are accepted. Everyone else stayed at school.
    if (sess === 'p5' && unique.length) {
      unique = unique.filter(r => ['early_departure_with_leave', 'early_departure_no_leave'].includes(r.status));
      if (unique.length) {
        const [morn] = await pool.query(
          `SELECT student_id, status FROM attendance
           WHERE date=? AND session='morning' AND student_id IN (?)`,
          [date, unique.map(r => Number(r.student_id))]);
        const mMap = new Map(morn.map(m => [m.student_id, m.status]));
        unique = unique.filter(r => mMap.get(Number(r.student_id)) === 'present');
        if (!unique.length) {
          return res.status(400).json({ error: '৫ম পিরিয়ডে শুধু ১ম পিরিয়ডে উপস্থিত শিক্ষার্থীদের প্রস্থান রেকর্ড করা যাবে।' });
        }
      }
    }
    // P5 with nothing marked = nobody left early. Still lock the session.
    if (!unique.length && sess === 'p5') {
      await pool.query(
        `INSERT INTO attendance_lock (class_id,date,session,locked,updated_by) VALUES (?,?,?,1,?)
         ON CONFLICT (class_id,date,session) DO UPDATE SET locked=1, updated_by=EXCLUDED.updated_by, updated_at=now()`,
        [classId, date, sess, req.user.id]);
      await audit(classId, date, sess, 'save', '0 departures (locked)', req.user.id);
      return res.json({ ok: true, class_id: classId, date, session: sess, count: 0, finals: {} });
    }
    const ids = unique.map(r => Number(r.student_id));
    const [st] = await pool.query('SELECT id, name, status FROM students WHERE id IN (?)', [ids]);
    for (const s of st) {
      if (s.status && s.status !== 'active') return res.status(403).json({ error: `${s.name} inactive` });
    }
    const vals = unique.map(() => '(?,?,?,?,?,?,?,?,?)').join(',');
    const params = [];
    unique.forEach((r, i) => {
      // The whole batch shares ONE client idem_key, but `idem_key` has a
      // UNIQUE index — so suffix the row index to keep each row's key unique
      // while still letting a replay be detected by prefix.
      const rowKey = idem_key ? `${idem_key}#${i}` : null;
      const remark = r.remark != null ? String(r.remark).slice(0, 500) : null;
      params.push(r.student_id, date, sess, r.status, remark, req.user.id, 0, null, rowKey);
    });
    await pool.query(
      `INSERT INTO attendance (student_id,date,session,status,remark,recorded_by,is_escape,override_reason,idem_key)
       VALUES ${vals}
       ON CONFLICT (student_id,date,session) DO UPDATE SET
         status=EXCLUDED.status, remark=EXCLUDED.remark, recorded_by=EXCLUDED.recorded_by,
         recorded_at=now(), idem_key=COALESCE(EXCLUDED.idem_key, attendance.idem_key)`,
      params);
    // lock this session (submitted)
    await pool.query(
      `INSERT INTO attendance_lock (class_id,date,session,locked,updated_by) VALUES (?,?,?,1,?)
       ON CONFLICT (class_id,date,session) DO UPDATE SET locked=1, updated_by=EXCLUDED.updated_by, updated_at=now()`,
      [classId, date, sess, req.user.id]);
    // consume delegation after use
    if (can.how === 'delegate' && can.delegation) {
      await pool.query(`UPDATE attendance_delegation SET used=1, used_at=now() WHERE id=?`, [can.delegation.id]);
    }
    // synthesize day final for affected students
    const p5Known = await H.p5Applicable(classId, date);
    const finals = {};
    for (const id of ids) {
      const [[m]] = await pool.query(`SELECT status FROM attendance WHERE student_id=? AND date=? AND session='morning'`, [id, date]);
      const [[p]] = await pool.query(`SELECT status FROM attendance WHERE student_id=? AND date=? AND session='p5'`, [id, date]);
      const f = dayFinal(m ? m.status : null, p ? p.status : null, p5Known);
      finals[id] = f;
      await pool.query(`UPDATE attendance SET final_state=? WHERE student_id=? AND date=?`, [f, id, date]);
    }
    await audit(classId, date, sess, 'save', `${unique.length} records`, req.user.id);
    res.json({ ok: true, class_id: classId, date, session: sess, count: unique.length, finals });
    // background: guardian notifications + summaries + threshold alerts
    setImmediate(() => postSaveJobs(classId, date, sess, unique, req.user.id).catch(e => console.error('postSave', e.message)));
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

async function postSaveJobs(classId, date, sess, records, actorId) {
  const absent = records.filter(r => r.status === 'absent');
  const late = records.filter(r => r.status === 'late');
  const leave = records.filter(r => r.status === 'leave');
  // guardian push for absent / late / leave (dedupe per student/session/type)
  const notifyGroup = async (list, type, title, bodyFor) => {
    if (!list.length) return;
    const ids = list.map(r => Number(r.student_id));
    const tokens = await getGuardianTokens(ids);
    if (tokens.length) {
      const [names] = await pool.query('SELECT id, name FROM students WHERE id IN (?)', [ids]);
      const nm = new Map(names.map(x => [x.id, x.name]));
      await queuePush(tokens, title, list.map(r => bodyFor(nm.get(Number(r.student_id)) || 'শিক্ষার্থী')).join('\n'),
        { type: 'attendance', date: String(date), session: sess, kind: type });
    }
    for (const r of list) {
      await notifyRow(Number(r.student_id), title, bodyFor(''), 'guardians', `${type}:${date}:${sess}:${r.student_id}`);
    }
  };
  const sessBn = sess === 'p5' ? '৫ম পিরিয়ড' : 'সকাল';
  await notifyGroup(absent, 'absent', `অনুপস্থিতি (${sessBn})`, n => `${n} আজ ${sessBn} হাজিরায় অনুপস্থিত।`);
  await notifyGroup(late, 'late', `দেরিতে উপস্থিত (${sessBn})`, n => `${n} আজ ${sessBn} হাজিরায় দেরিতে এসেছে।`);
  await notifyGroup(leave, 'leave', `ছুটি (${sessBn})`, n => `${n}-এর জন্য ${sessBn} ছুটি রেকর্ড হয়েছে।`);

  // rebuild summaries + threshold alert
  const thr = Number(await H.getSetting('threshold_percent', '75')) || 75;
  const [y, mo] = date.split('-').map(Number);
  for (const r of records) {
    const sum = await rebuildSummary(Number(r.student_id), y, mo);
    if (sum.percent > 0 && sum.percent < thr) {
      await notifyRow(Number(r.student_id), '⚠️ কম হাজিরা',
        `এই মাসে হাজিরা ${sum.percent}% — নির্ধারিত ${thr}%-এর নিচে।`, 'guardians',
        `lowatt:${r.student_id}:${y}-${mo}`);
    }
  }
}

// POST /attendance/class/:id/holiday  { date, occasion, clear }
router.post('/class/:id/holiday', auth(['teacher', 'admin']), async (req, res) => {
  const classId = Number(req.params.id);
  const { date, occasion, clear } = req.body || {};
  if (!date) return res.status(400).json({ error: 'date required' });
  try {
    const c = await getClass(classId);
    if (!c) return res.status(404).json({ error: 'Class not found' });
    if (req.user.role !== 'admin' && c.teacher_id !== req.user.id) {
      return res.status(403).json({ error: 'শুধু শ্রেণি শিক্ষক ছুটির কারণ লিখতে পারবেন।' });
    }
    const hol = clear ? 0 : 1;
    await pool.query(
      `INSERT INTO attendance_day (class_id,date,is_holiday,occasion,set_by) VALUES (?,?,?,?,?)
       ON CONFLICT (class_id,date) DO UPDATE SET is_holiday=EXCLUDED.is_holiday, occasion=EXCLUDED.occasion, set_by=EXCLUDED.set_by, set_at=now()`,
      [classId, date, hol, occasion || null, req.user.id]);
    await audit(classId, date, null, hol ? 'holiday' : 'holiday_clear', occasion || '', req.user.id);
    res.json({ ok: true, is_holiday: !!hol, occasion: occasion || null });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// POST /attendance/class/:id/open  { date, session, close }
router.post('/class/:id/open', auth(['teacher', 'admin']), async (req, res) => {
  const classId = Number(req.params.id);
  const { date, session, close } = req.body || {};
  if (!date) return res.status(400).json({ error: 'date required' });
  try {
    const c = await getClass(classId);
    if (!c) return res.status(404).json({ error: 'Class not found' });
    if (req.user.role !== 'admin' && c.teacher_id !== req.user.id) {
      return res.status(403).json({ error: 'শুধু শ্রেণি শিক্ষক present call খুলতে পারবেন।' });
    }
    const val = close ? 0 : 1;
    await pool.query(
      `INSERT INTO attendance_day (class_id,date,open_override) VALUES (?,?,?)
       ON CONFLICT (class_id,date) DO UPDATE SET open_override=EXCLUDED.open_override, set_by=?, set_at=now()`,
      [classId, date, val, req.user.id]);
    await audit(classId, date, session || null, val ? 'open_day' : 'close_day', '', req.user.id);
    res.json({ ok: true, open_override: !!val });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// POST /attendance/class/:id/request-reopen  { date, session, reason }
router.post('/class/:id/request-reopen', auth(['teacher']), async (req, res) => {
  const classId = Number(req.params.id);
  const { date, session, reason } = req.body || {};
  const sess = session === 'p5' ? 'p5' : 'morning';
  if (!date) return res.status(400).json({ error: 'date required' });
  try {
    const c = await getClass(classId);
    if (!c) return res.status(404).json({ error: 'Class not found' });
    const can = await canTake(classId, date, sess, req.user);
    if (!can.ok) return res.status(403).json({ error: can.reason });
    await pool.query(
      `INSERT INTO attendance_reopen (class_id,date,session,requested_by,reason) VALUES (?,?,?,?,?)`,
      [classId, date, sess, req.user.id, (reason || '').slice(0, 255)]);
    await audit(classId, date, sess, 'reopen_request', reason || '', req.user.id);
    const tokens = await H.getAdminTokens();
    if (tokens.length) {
      await queuePush(tokens, '🔓 Reopen request',
        `${c.name} — ${date} (${sess}) হাজিরা reopen করার অনুরোধ।`, { type: 'attendance', kind: 'reopen_request' });
    }
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// GET /attendance/class/:id/history?days=30
router.get('/class/:id/history', auth(['teacher', 'admin']), async (req, res) => {
  const classId = Number(req.params.id);
  const days = Math.min(90, Math.max(1, parseInt(req.query.days || '30', 10)));
  try {
    // history viewable by admin, class teacher, or any 5th-period teacher
    const okView = req.user.role === 'admin' ||
      (await canView(classId, H.dhakaDate(), req.user, 'morning')) ||
      (await canView(classId, H.dhakaDate(), req.user, 'p5'));
    if (!okView) {
      return res.status(403).json({ error: 'অনুমতি নেই।' });
    }
    const [rows] = await pool.query(
      `SELECT a.date, a.session,
              SUM(CASE WHEN a.status='present' THEN 1 ELSE 0 END) AS present,
              SUM(CASE WHEN a.status='absent' THEN 1 ELSE 0 END) AS absent,
              SUM(CASE WHEN a.status='late' THEN 1 ELSE 0 END) AS late,
              SUM(CASE WHEN a.status='leave' THEN 1 ELSE 0 END) AS leave_count,
              COUNT(*) AS total, MAX(u.name) AS taken_by, MAX(a.recorded_at) AS taken_at
       FROM attendance a LEFT JOIN users u ON u.id=a.recorded_by
       WHERE a.student_id IN (SELECT id FROM students WHERE class_id=?)
         AND a.date >= (CURRENT_DATE - INTERVAL '${days} days')
       GROUP BY a.date, a.session ORDER BY a.date DESC, a.session`,
      [classId]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ============================================================ ADMIN
router.get('/admin/board', auth(['admin']), async (req, res) => {
  try {
    const date = req.query.date || H.dhakaDate();
    const now = new Date();
    const [classes] = await pool.query(`SELECT id, name, section, group_name, teacher_id FROM classes ORDER BY name, section`);
    const out = [];
    for (const c of classes) {
      const [[ct]] = await pool.query(`SELECT name FROM users WHERE id=?`, [c.teacher_id]);
      const m = await openState(c.id, date, 'morning', now);
      const a = await openState(c.id, date, 'p5', now);
      const [[ms]] = await pool.query(
        `SELECT MAX(a.recorded_by) AS by_id, MAX(u.name) AS by_name, MAX(a.recorded_at) AS at,
                SUM(CASE WHEN a.status='present' THEN 1 ELSE 0 END) AS present,
                SUM(CASE WHEN a.status='absent' THEN 1 ELSE 0 END) AS absent
         FROM attendance a LEFT JOIN users u ON u.id=a.recorded_by
         WHERE a.date=? AND a.session='morning' AND a.student_id IN (SELECT id FROM students WHERE class_id=?)`,
        [date, c.id]);
      const [[as]] = await pool.query(
        `SELECT MAX(a.recorded_by) AS by_id, MAX(u.name) AS by_name, MAX(a.recorded_at) AS at,
                SUM(CASE WHEN a.status='present' THEN 1 ELSE 0 END) AS present,
                SUM(CASE WHEN a.status='absent' THEN 1 ELSE 0 END) AS absent
         FROM attendance a LEFT JOIN users u ON u.id=a.recorded_by
         WHERE a.date=? AND a.session='p5' AND a.student_id IN (SELECT id FROM students WHERE class_id=?)`,
        [date, c.id]);
      const [[{ total }]] = await pool.query(
        `SELECT COUNT(*) AS total FROM students WHERE class_id=? AND (status IS NULL OR status='active')`, [c.id]);
      out.push({
        class_id: c.id, class_name: c.name, section: c.section, group_name: c.group_name,
        class_teacher: ct ? ct.name : null, total_students: Number(total),
        morning: { taken: !!ms.by_id, by: ms.by_name, at: ms.at, present: Number(ms.present || 0), absent: Number(ms.absent || 0), state: m },
        p5: { taken: !!as.by_id, by: as.by_name, at: as.at, present: Number(as.present || 0), absent: Number(as.absent || 0), state: a },
      });
    }
    res.json({ date, weekend: H.isWeekend(date), classes: out });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/admin/requests', auth(['admin']), async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT rq.*, c.name AS class_name, c.section, u.name AS requested_by_name
       FROM attendance_reopen rq JOIN classes c ON c.id=rq.class_id
       LEFT JOIN users u ON u.id=rq.requested_by
       WHERE rq.status='pending' ORDER BY rq.id DESC LIMIT 200`);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/admin/requests/:id/decide', auth(['admin']), async (req, res) => {
  const id = Number(req.params.id);
  const { approve, note } = req.body || {};
  try {
    const [[rq]] = await pool.query(`SELECT * FROM attendance_reopen WHERE id=?`, [id]);
    if (!rq) return res.status(404).json({ error: 'Request not found' });
    await pool.query(
      `UPDATE attendance_reopen SET status=?, decided_by=?, decided_at=now(), decision_note=? WHERE id=?`,
      [approve ? 'approved' : 'denied', req.user.id, (note || '').slice(0, 255), id]);
    if (approve) {
      // reopen for 2 hours
      await pool.query(
        `INSERT INTO attendance_lock (class_id,date,session,locked,reopen_until,updated_by)
         VALUES (?,?,?,0,now() + INTERVAL '2 hours',?)
         ON CONFLICT (class_id,date,session) DO UPDATE SET locked=0, reopen_until=now() + INTERVAL '2 hours', updated_by=EXCLUDED.updated_by, updated_at=now()`,
        [rq.class_id, rq.date, rq.session, req.user.id]);
    }
    await audit(rq.class_id, rq.date, rq.session, approve ? 'reopen_approved' : 'reopen_denied', note || '', req.user.id);
    const tokens = await H.getTeacherTokens([rq.requested_by]);
    if (tokens.length) {
      await queuePush(tokens, approve ? '✅ Reopen approved' : '❌ Reopen denied',
        approve ? `${rq.date} (${rq.session}) হাজিরা ২ ঘণ্টার জন্য খোলা হয়েছে।` : 'আপনার reopen request গ্রহণ করা হয়নি।',
        { type: 'attendance', kind: 'reopen_decided' });
    }
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/admin/unlock', auth(['admin']), async (req, res) => {
  const { class_id, classId, date, session, reason } = req.body || {};
  const cid = Number(class_id || classId);
  const sess = session === 'p5' ? 'p5' : 'morning';
  if (!cid || !date) return res.status(400).json({ error: 'class_id and date required' });
  try {
    await pool.query(
      `INSERT INTO attendance_lock (class_id,date,session,locked,reopen_until,note,updated_by)
       VALUES (?,?,?,0,now() + INTERVAL '2 hours',?,?)
       ON CONFLICT (class_id,date,session) DO UPDATE SET locked=0, reopen_until=now() + INTERVAL '2 hours', note=EXCLUDED.note, updated_by=EXCLUDED.updated_by, updated_at=now()`,
      [cid, date, sess, (reason || '').slice(0, 255), req.user.id]);
    await audit(cid, date, sess, 'admin_unlock', reason || '', req.user.id);
    res.json({ ok: true, reopen_until: '2h' });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/admin/report', auth(['admin']), async (req, res) => {
  try {
    const classId = Number(req.query.class_id || 0);
    const from = req.query.from || `${new Date().toISOString().slice(0, 7)}-01`;
    const to = req.query.to || H.dhakaDate();
    if (!classId) return res.status(400).json({ error: 'class_id required' });
    const [students] = await pool.query(
      `SELECT id, name, roll FROM students WHERE class_id=? AND (status IS NULL OR status='active') ORDER BY roll`, [classId]);
    const [att] = await pool.query(
      `SELECT a.student_id, to_char(a.date,'YYYY-MM-DD') AS d, a.session, a.status FROM attendance a
       WHERE a.date BETWEEN ? AND ? AND a.student_id IN (SELECT id FROM students WHERE class_id=?)`,
      [from, to, classId]);
    const byStudent = new Map();
    for (const a of att) {
      if (!byStudent.has(a.student_id)) byStudent.set(a.student_id, new Map());
      const day = a.d;
      if (!byStudent.get(a.student_id).has(day)) byStudent.get(a.student_id).set(day, {});
      byStudent.get(a.student_id).get(day)[a.session] = a.status;
    }
    const p5KnownByDate = new Map();
    for (const a of att) {
      const d = a.d;
      if (!p5KnownByDate.has(d)) p5KnownByDate.set(d, await H.p5Applicable(classId, d));
    }
    const report = students.map(s => {
      const days = byStudent.get(s.id) || new Map();
      let present = 0, late = 0, leave = 0, absent = 0, school = 0;
      for (const [d, sm] of days) {
        const f = dayFinal(sm.morning || null, sm.p5 || null, p5KnownByDate.get(d) !== false);
        if (f === null) continue;
        school++;
        if (f === 'leave') leave++;
        else if (f === 'present') (sm.morning === 'late' || sm.p5 === 'late') ? late++ : present++;
        else absent++;
      }
      return { student_id: s.id, name: s.name, roll: s.roll, present, late, leave, absent, school_days: school,
        percent: H.percent(present + late, school, leave) };
    });
    const thr = Number(await H.getSetting('threshold_percent', '75')) || 75;
    res.json({ class_id: classId, from, to, threshold: thr, students: report });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/admin/audit', auth(['admin']), async (req, res) => {
  try {
    const classId = Number(req.query.class_id || 0);
    const [rows] = await pool.query(
      `SELECT au.*, c.name AS class_name, u.name AS actor_name
       FROM attendance_audit au LEFT JOIN classes c ON c.id=au.class_id
       LEFT JOIN users u ON u.id=au.actor_id
       ${classId ? 'WHERE au.class_id=?' : ''} ORDER BY au.id DESC LIMIT 300`,
      classId ? [classId] : []);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/admin/settings', auth(['admin']), async (req, res) => {
  try {
    const [rows] = await pool.query(`SELECT key, value FROM attendance_setting`);
    const o = {}; for (const r of rows) o[r.key] = r.value;
    res.json({ threshold_percent: Number(o.threshold_percent || 75), reminder_time: o.reminder_time || '10:30' });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});
router.put('/admin/settings', auth(['admin']), async (req, res) => {
  const { threshold_percent, reminder_time } = req.body || {};
  try {
    if (threshold_percent != null) {
      await pool.query(`INSERT INTO attendance_setting(key,value) VALUES ('threshold_percent',?) ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value`, [String(threshold_percent)]);
    }
    if (reminder_time != null) {
      await pool.query(`INSERT INTO attendance_setting(key,value) VALUES ('reminder_time',?) ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value`, [String(reminder_time)]);
    }
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/admin/delegate', auth(['admin']), async (req, res) => {
  const { class_id, classId, date, session, to_user_id, toUserId } = req.body || {};
  const cid = Number(class_id || classId);
  const uid = Number(to_user_id || toUserId);
  const sess = session === 'p5' ? 'p5' : 'morning';
  if (!cid || !date || !uid) return res.status(400).json({ error: 'class_id, date, to_user_id required' });
  try {
    const expiresAt = await AttendanceAccess.requestExpiry(date, sess);
    if (!validAttendanceDate(date) || !expiresAt || expiresAt <= Date.now()) return res.status(400).json({ error: 'আজকের কার্যকর হাজিরার সময় দিন।' });
    await pool.query(
      `INSERT INTO attendance_delegation (class_id,date,session,granted_by,granted_to,expires_at_epoch) VALUES (?,?,?,?,?,?)`,
      [cid, date, sess, req.user.id, uid, expiresAt]);
    await audit(cid, date, sess, 'delegate', `to user ${uid}`, req.user.id);
    const tokens = await H.getTeacherTokens([uid]);
    if (tokens.length) {
      await queuePush(tokens, 'আজ হাজিরার দায়িত্ব', `${date} (${sess}) — একটি ক্লাসের হাজিরা নেওয়ার দায়িত্ব দেওয়া হয়েছে।`,
        { type: 'attendance', kind: 'delegate' });
    }
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});
router.delete('/admin/delegate/:id', auth(['admin']), async (req, res) => {
  try {
    await pool.query(`UPDATE attendance_delegation SET revoked=1 WHERE id=?`, [Number(req.params.id)]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/admin/export', auth(['admin']), async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT a.date, a.session, c.name AS class_name, c.section, s.roll, s.name AS student_name,
              a.status, a.final_state, u.name AS recorded_by, a.recorded_at, a.remark
       FROM attendance a JOIN students s ON s.id=a.student_id JOIN classes c ON c.id=s.class_id
       LEFT JOIN users u ON u.id=a.recorded_by
       ORDER BY a.date DESC, c.name, s.roll`);
    const header = 'date,session,class,section,roll,student,status,final_state,recorded_by,recorded_at,remark';
    const lines = rows.map(r => [r.date, r.session, r.class_name, r.section, r.roll, r.student_name, r.status, r.final_state, r.recorded_by, r.recorded_at, (r.remark || '').replace(/[\n,]/g, ' ')].join(','));
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="attendance_export.csv"');
    res.send([header, ...lines].join('\n'));
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/admin/rebuild-summary', auth(['admin']), async (req, res) => {
  const { year, month, class_id } = req.body || {};
  try {
    const y = Number(year) || new Date().getFullYear();
    const m = Number(month) || (new Date().getMonth() + 1);
    const [students] = await pool.query(
      class_id ? `SELECT id FROM students WHERE class_id=? AND (status IS NULL OR status='active')`
               : `SELECT id FROM students WHERE (status IS NULL OR status='active')`,
      class_id ? [Number(class_id)] : []);
    for (const s of students) await rebuildSummary(s.id, y, m);
    res.json({ ok: true, count: students.length });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ============================================================ GUARDIAN
async function guardianOwnsStudent(studentId, userId) {
  const [[row]] = await pool.query(
    `SELECT s.id FROM students s WHERE s.id=? AND (s.guardian_id=?
       OR EXISTS (SELECT 1 FROM guardian_links gl WHERE gl.student_id=s.id AND gl.guardian_id=? AND gl.status='approved'))`,
    [studentId, userId, userId]);
  return !!row;
}
router.get('/guardian/:studentId', auth(['guardian', 'admin']), async (req, res) => {
  const studentId = Number(req.params.studentId);
  try {
    if (req.user.role !== 'admin' && !(await guardianOwnsStudent(studentId, req.user.id))) {
      return res.status(403).json({ error: 'অনুমতি নেই।' });
    }
    const month = req.query.month || H.dhakaDate().slice(0, 7);
    const from = `${month}-01`;
    const [rows] = await pool.query(
      `SELECT a.date, a.session, a.status, a.remark, a.final_state,
              u.name AS recorded_by, a.recorded_at
       FROM attendance a LEFT JOIN users u ON u.id=a.recorded_by
       WHERE a.student_id=? AND a.date >= ?::date AND a.date < (?::date + INTERVAL '1 month')
       ORDER BY a.date`, [studentId, from, from]);
    const [[sum]] = await pool.query(
      `SELECT * FROM attendance_summary WHERE student_id=? AND year=? AND month=?`,
      [studentId, Number(month.slice(0, 4)), Number(month.slice(5, 7))]);
    const [recent] = await pool.query(
      `SELECT a.date, a.session, u.name AS recorded_by, a.recorded_at
       FROM attendance a LEFT JOIN users u ON u.id=a.recorded_by
       WHERE a.student_id=? ORDER BY a.date DESC, a.session DESC LIMIT 20`, [studentId]);
    const [takers] = await pool.query(
      `SELECT DISTINCT u.name, u.id FROM attendance a JOIN users u ON u.id=a.recorded_by WHERE a.student_id=?`, [studentId]);
    res.json({ student_id: studentId, month, records: rows, summary: sum || null, recent, takers });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;
