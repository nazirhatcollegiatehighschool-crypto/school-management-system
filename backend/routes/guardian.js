const router = require('express').Router();
const pool = require('../db');
const { dhakaToday } = require('../dates');
const { auth } = require('../middleware/auth');
const { computeResult, gradePaper, classLevelOf } = require('../grading');
const PDFDocument = require('pdfkit');
const path = require('path');
const fs = require('fs');
const { loadTeacherSignature } = require('../lib/teacher_signatures');
const { loadStudentActivities } = require('../lib/student_activities');
const { normalizeGender } = require('../lib/gender');
const { canonicalReligion } = require('../curriculum');
const { queuePush } = require('../fcm');

router.use(auth('guardian'));

// =====================================================================
// STRICT DATA ISOLATION — MAGIC STRING:
// A guardian can only ever see students whom they OWN via an ADMIN-APPROVED
// link (guardian_links.status='approved'). The student they log in with is
// auto-approved; every other child must be added via a sibling request and
// approved by an admin. Until approval, ZERO data of that student is exposed.
// =====================================================================
const APPROVED_SCOPE = `s.id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')`;

async function getApprovedStudent(guardianId, studentId) {
  const [rows] = await pool.query(
    `SELECT s.*, c.name AS class_name, c.section FROM students s JOIN classes c ON s.class_id=c.id
     WHERE ${APPROVED_SCOPE} AND s.id=?`,
    [guardianId, studentId]
  );
  return rows[0] || null;
}

router.get('/profile', async (req, res) => {
  try {
    const [students] = await pool.query(
      `SELECT s.id, s.name, s.student_code, s.roll, s.dob, s.class_id, s.guardian_profile_locked_at, s.is_irregular, c.name AS class_name, c.section
       FROM students s JOIN classes c ON s.class_id = c.id
       WHERE ${APPROVED_SCOPE} ORDER BY s.id`,
      [req.user.id]
    );
    const [notifications] = await pool.query(
      `SELECT n.id, n.title, n.body, n.type, n.created_at
       FROM notifications n
       WHERE n.target_type<>'teacher' AND (n.student_id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')
          OR (n.student_id IS NULL AND (n.class_id IS NULL OR n.class_id IN (
             SELECT class_id FROM students WHERE id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')
          ))))
       ORDER BY n.id DESC LIMIT 50`,
      [req.user.id, req.user.id]
    );
    res.json({ guardian: req.user, students, notifications });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Guardians may complete a newly admitted student's profile once. All future
// changes go through a review request and are applied by school staff.
router.get('/student/:id/profile', async (req, res) => {
  try {
    const s = await getApprovedStudent(req.user.id, req.params.id);
    if (!s) return res.status(403).json({ error: 'Not authorized for this student' });
    const [religionRows] = await pool.query(`SELECT DISTINCT religion FROM students WHERE religion IS NOT NULL AND TRIM(religion)<>'' ORDER BY religion`);
    const [requests] = await pool.query(`SELECT id,reason,proposed_changes,status,admin_note,created_at,reviewed_at FROM student_profile_edit_requests WHERE student_id=? AND guardian_id=? ORDER BY id DESC LIMIT 50`, [s.id, req.user.id]);
    const { birth_cert_no, phone, email, ...safe } = s;
    res.json({ student: safe, religions: [...new Set([...religionRows.map(r => r.religion), 'Islam','Hinduism','Christianity','Buddhism','Other'])], requests });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/student/:id/profile/complete', async (req, res) => {
  const allowed = ['name','religion','receives_scholarship','guardian_name','guardian_phone','father_name','mother_name','address','gender','blood_group'];
  const body = req.body || {};
  if (!['name','religion','guardian_name','guardian_phone','father_name','mother_name','address','gender'].every(k => String(body[k] || '').trim()) || !String(body.guardian_phone || '').replace(/\D/g,'').match(/\d{10,}/)) {
    return res.status(400).json({ error: 'শিক্ষার্থীর নাম, ধর্ম, অভিভাবকের তথ্য, বাবা-মায়ের নাম, ঠিকানা, লিঙ্গ ও সঠিক ফোন পূরণ করুন।' });
  }
  const gender = normalizeGender(body.gender);
  if (!['Male', 'Female', 'Other'].includes(gender)) {
    return res.status(400).json({ error: 'লিঙ্গ Male, Female অথবা Other হতে হবে।' });
  }
  const clean = { ...body, gender, religion: canonicalReligion(body.religion) };
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [rows] = await conn.query(`SELECT s.* FROM students s JOIN guardian_links gl ON gl.student_id=s.id WHERE gl.guardian_id=? AND gl.status='approved' AND s.id=? FOR UPDATE`, [req.user.id, req.params.id]);
    const s = rows[0];
    if (!s) { await conn.rollback(); return res.status(403).json({ error: 'Not authorized for this student' }); }
    if (s.guardian_profile_locked_at) { await conn.rollback(); return res.status(409).json({ error: 'প্রোফাইল একবার জমা হয়েছে; সংশোধনের অনুরোধ পাঠান।' }); }
    const updates = [], params = [];
    for (const key of allowed) if (clean[key] !== undefined) { updates.push(`${key}=?`); params.push(key === 'receives_scholarship' ? (clean[key] ? 1 : 0) : String(clean[key]).trim()); }
    updates.push('guardian_profile_locked_at=NOW()'); params.push(s.id);
    await conn.query(`UPDATE students SET ${updates.join(',')} WHERE id=? AND guardian_profile_locked_at IS NULL`, params);
    await conn.commit();
    res.json({ ok: true, locked: true });
  } catch (err) { try { await conn.rollback(); } catch (_) {} console.error(err); res.status(500).json({ error: 'Server error' }); }
  finally { conn.release(); }
});

router.post('/student/:id/profile-edit-requests', async (req, res) => {
  const reason = String(req.body?.reason || '').trim();
  if (reason.length < 5) return res.status(400).json({ error: 'সংশোধনের কারণ লিখুন।' });
  try {
    const s = await getApprovedStudent(req.user.id, req.params.id);
    if (!s) return res.status(403).json({ error: 'Not authorized for this student' });
    const [[cls]] = await pool.query('SELECT teacher_id FROM classes WHERE id=?', [s.class_id]);
    const [result] = await pool.query(`INSERT INTO student_profile_edit_requests (student_id,guardian_id,class_id,class_teacher_id,reason,proposed_changes) VALUES (?,?,?,?,?,?)`, [s.id,req.user.id,s.class_id,cls?.teacher_id || null,reason.slice(0,1000),JSON.stringify(req.body?.proposed_changes || {})]);
    const title = 'শিক্ষার্থী প্রোফাইল সংশোধন অনুরোধ';
    const body = `${s.name} (Roll ${s.roll}): অভিভাবক প্রোফাইল সংশোধন চেয়েছেন।`;
    if (cls?.teacher_id) await pool.query(`INSERT INTO notifications (student_id,class_id,title,body,type,target_type,related_id,target_user_id,created_by) VALUES (?,?,?,?,'general','teacher',?,?,?)`, [s.id,s.class_id,title,body,result.insertId,cls.teacher_id,req.user.id]);
    const [admins] = await pool.query(`SELECT id FROM users WHERE role='admin' AND active=TRUE`);
    for (const a of admins) await pool.query(`INSERT INTO notifications (student_id,class_id,title,body,type,target_type,related_id,target_user_id,created_by) VALUES (?,?,?,?,'general','teacher',?,?,?)`, [s.id,s.class_id,title,body,result.insertId,a.id,req.user.id]);
    const targets=[...(cls?.teacher_id?[Number(cls.teacher_id)]:[]),...admins.map(a=>Number(a.id))];
    if(targets.length) { const [tokens]=await pool.query(`SELECT fcm_token FROM device_tokens WHERE user_id IN (${targets.map(()=>'?').join(',')}) AND active=TRUE`,targets); queuePush(tokens.map(t=>t.fcm_token),title,body,{type:'general',kind:'student_profile_edit_request',request_id:result.insertId,student_id:s.id}); }
    res.status(201).json({ ok: true, id: result.insertId });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/attendance/monthly', async (req, res) => {
  const m = String((req.query && req.query.month) || new Date().toISOString().slice(0, 7));
  try {
    const [links] = await pool.query(
      `SELECT s.id AS student_id, s.name, s.roll, c.name AS class_name, c.section
       FROM students s JOIN classes c ON s.class_id=c.id
       JOIN guardian_links gl ON gl.student_id = s.id
       WHERE gl.guardian_id=? ORDER BY s.roll`, [req.user.id]
    );
    const kids = [];
    for (const k of links) {
      const [rows] = await pool.query(
        `SELECT COALESCE(SUM(CASE WHEN a.is_escape THEN 1 ELSE 0 END),0) AS escape_days,
                COALESCE(SUM(CASE WHEN a.status <> 'present' THEN 1 ELSE 0 END),0) AS absent_days
         FROM attendance a WHERE a.student_id=? AND a.date BETWEEN ? AND ?`,
        [k.student_id, m + '-01', m + '-31']
      );
      kids.push({ ...k, ...(rows[0] || {}) });
    }
    res.json({ month: m, kids });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/attendance/monthly', async (req, res) => {
  const m = String((req.query && req.query.month) || new Date().toISOString().slice(0, 7));
  try {
    const [[gl]] = await pool.query(
      'SELECT id FROM guardian_links WHERE guardian_id=? AND student_id=?',
      [req.user.id, req.params.id]
    );
    if (!gl) return res.status(403).json({ error: 'You may only view your own child' });
    const [rows] = await pool.query(
      'SELECT date, status, remark, is_escape FROM attendance WHERE student_id=? AND date BETWEEN ? AND ? ORDER BY date',
      [req.params.id, m + '-01', m + '-31']
    );
    res.json({ month: m, rows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/attendance', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    // FSM-aware: both sessions + synthesized final state per day.
    const [rows] = await pool.query(
      `SELECT date, session, status, remark, final_state, is_escape
       FROM attendance WHERE student_id=? ORDER BY date DESC, session ASC LIMIT 120`,
      [req.params.id]
    );
    // Collapse to per-day timeline: morning + p5 + final (Bangladesh labels).
    const { FINAL_BN } = require('../attendance_fsm');
    const byDay = new Map();
    for (const r of rows) {
      if (!byDay.has(r.date)) byDay.set(r.date, { date: r.date, morning: null, p5: null, final_state: null, is_escape: 0 });
      const d = byDay.get(r.date);
      if (r.session === 'p5') d.p5 = r.status; else d.morning = r.status;
      if (r.final_state) d.final_state = r.final_state;
      if (r.is_escape) d.is_escape = 1;
      if (r.remark && !d.remark) d.remark = r.remark;
    }
    const days = [...byDay.values()].slice(0, 60).map(d => ({
      ...d, final_bn: d.final_state ? (FINAL_BN[d.final_state] || d.final_state) : null,
    }));
    res.json(days);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/daily-reports', async (req, res) => {
  try {
    const student = await getApprovedStudent(req.user.id, req.params.id);
    if (!student) return res.status(403).json({ error: 'Not authorized for this student' });
    const [rows] = await pool.query(
      `SELECT r.report_date, r.subject_name, r.homework_status, r.learning_status,
              r.performance, r.note, r.updated_at,
              u.name AS teacher_name
       FROM student_daily_reports r JOIN users u ON u.id=r.teacher_id
       WHERE r.student_id=? ORDER BY r.report_date DESC, r.updated_at DESC`,
      [student.id]);
    const [uniformRows] = await pool.query(
      `SELECT r.report_date, FALSE AS uniform_brought, MAX(r.note) AS note,
              MAX(r.updated_at) AS updated_at, MAX(u.name) AS teacher_name
       FROM student_uniform_reports r JOIN users u ON u.id=r.teacher_id
       WHERE r.student_id=? ORDER BY r.report_date DESC, r.updated_at DESC`,
      [student.id]);
    const [legacyUniformRows] = await pool.query(
      `SELECT r.report_date, r.uniform_brought, r.note, r.updated_at,
              u.name AS teacher_name
       FROM student_daily_reports r LEFT JOIN users u ON u.id=r.teacher_id
       WHERE r.student_id=? AND r.uniform_brought=FALSE
         AND NOT EXISTS (SELECT 1 FROM student_uniform_reports ur
                         WHERE ur.student_id=r.student_id AND ur.report_date=r.report_date)
       GROUP BY r.report_date
       ORDER BY r.report_date DESC`, [student.id]);
    res.json([...rows, ...uniformRows, ...legacyUniformRows].map(row => ({
      ...row,
      ...(row.subject_name == null ? { report_type: 'uniform', subject_name: 'Uniform' } : {}),
    })).sort((a, b) => String(b.report_date).localeCompare(String(a.report_date))));
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Today's live status for one child: morning mark + P5 mark + final synthesis.
router.get('/student/:id/attendance/today', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const { FINAL_BN, WINDOWS } = require('../attendance_fsm');
    const today = dhakaToday();
    const [rows] = await pool.query(
      `SELECT session, status, final_state, remark, created_at FROM attendance
       WHERE student_id=? AND date=?`, [req.params.id, today]);
    const morning = rows.find(r => r.session !== 'p5') || null;
    const p5 = rows.find(r => r.session === 'p5') || null;
    const fin = (morning && morning.final_state) || (p5 && p5.final_state) || null;
    res.json({
      date: today, morning, p5,
      final_state: fin, final_bn: fin ? (FINAL_BN[fin] || fin) : 'এখনো হাজিরা হয়নি',
      windows: WINDOWS,
    });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ---- Leave tickets: guardian applies (advance digital leave), tracks status.
// Approved by class teacher/admin → auto-feeds the attendance FSM synthesis.
router.post('/leave-tickets', async (req, res) => {
  const { student_id, leave_date, kind, reason } = req.body || {};
  if (!student_id || !leave_date) {
    return res.status(400).json({ error: 'student_id and leave_date required' });
  }
  const kk = ['full_day', 'morning_only', 'early_departure'].includes(kind) ? kind : 'full_day';
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(leave_date))) {
    return res.status(400).json({ error: 'leave_date must be YYYY-MM-DD' });
  }
  try {
    const stu = await getApprovedStudent(req.user.id, student_id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [[dup]] = await pool.query(
      `SELECT id FROM leave_tickets WHERE student_id=? AND leave_date=? AND status='pending'`,
      [student_id, leave_date]);
    if (dup) return res.status(409).json({ error: 'এই তারিখের জন্য ইতিমধ্যে একটি pending আবেদন আছে।' });
    const [r] = await pool.query(
      `INSERT INTO leave_tickets (student_id, guardian_id, leave_date, kind, reason, status)
       VALUES (?,?,?,?,?,'pending')`,
      [student_id, req.user.id, leave_date, kk, (reason || '').slice(0, 500) || null]);
    // Notify the class teacher (inbox) that a leave needs review.
    await pool.query(
      `INSERT INTO notifications (student_id, title, body, type, target_type, related_id)
       VALUES (?,?,?,?,?,?)`,
      [student_id, 'ছুটির আবেদন',
       `${stu.name}-এর ${leave_date} তারিখের ছুটির আবেদন এসেছে — review করুন।`,
       'general', 'teacher', r.insertId]);
    res.status(201).json({ ok: true, id: r.insertId });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/leave-tickets', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT t.*, s.name AS student_name FROM leave_tickets t
       JOIN students s ON s.id=t.student_id
       WHERE t.guardian_id=? AND t.student_id IN
        (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')
       ORDER BY t.id DESC LIMIT 100`, [req.user.id, req.user.id]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/marks', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [rows] = await pool.query(
      `SELECT m.marks, m.total, m.cq, m.mcq, m.practical, m.written, m.ca, m.absent,
              m.comment, e.name AS exam_name, e.exam_type, e.exam_date, e.id AS exam_id,
              sub.name AS subject_name, sub.full_marks, sub.cq_full, sub.mcq_full,
              sub.practical_full, sub.written_full, sub.ca_full, c.name AS class_name
       FROM marks m JOIN exams e ON m.exam_id = e.id
       JOIN exam_events ev ON ev.id=e.event_id
       JOIN subjects sub ON e.subject_id = sub.id
       JOIN classes c ON c.id=e.class_id
       WHERE m.student_id = ? AND e.status = 'published'
         AND (ev.exam_kind<>'special_model_test' OR EXISTS (
           SELECT 1 FROM promotions mp JOIN exam_events src ON src.id=mp.event_id
           WHERE mp.student_id=? AND mp.destination_session_id=ev.session_id AND mp.decision='promoted'
             AND src.exam_kind='test' AND src.year=ev.year-1))
       ORDER BY e.id DESC, sub.id`,
      [req.params.id, stu.id]
    );
    res.json(rows.map(row => {
      const grade = gradePaper(
        classLevelOf(row.class_name),
        row,
        { name: row.subject_name, full_marks: row.full_marks },
        {
          cq_full: row.cq_full,
          mcq_full: row.mcq_full,
          practical_full: row.practical_full,
          written_full: row.written_full,
          ca_full: row.ca_full,
        }
      );
      return {
        ...row,
        letter_grade: grade.absent ? 'Absent' : grade.letter_grade,
        grade_point: grade.grade_point,
      };
    }));
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/homework', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [rows] = await pool.query(
      `SELECT h.id, h.title, h.description, h.due_date, h.subject_id,
              sub.name AS subject_name, u.id AS teacher_id, u.name AS teacher_name,
              u.phone AS teacher_phone, c.name AS class_name, c.section, h.created_at
       FROM homework h
       LEFT JOIN subjects sub ON h.subject_id = sub.id
       LEFT JOIN users u ON h.created_by = u.id
       JOIN classes c ON c.id = h.class_id
       WHERE h.class_id = ?
       ORDER BY h.id DESC LIMIT 50`,
      [stu.class_id]
    );
    const ids = rows.map(r => r.id);
    let byHw = {};
    if (ids.length) {
      const [files] = await pool.query(
        `SELECT id, homework_id, file_name, file_path, mime_type, file_size, created_at
         FROM homework_attachments WHERE homework_id IN (?) ORDER BY id`, [ids]);
      for (const a of files) {
        (byHw[a.homework_id] = byHw[a.homework_id] || []).push({
          ...a, url: '/uploads/homework/' + a.file_path
        });
      }
    }
    res.json(rows.map(r => ({ ...r, attachments: byHw[r.id] || [] })));
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/notifications', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [rows] = await pool.query(
      `SELECT id, title, body, type, related_id AS exam_id, created_at FROM notifications
       WHERE target_type<>'teacher' AND (student_id = ? OR (student_id IS NULL AND (class_id IS NULL OR class_id = ?)))
       ORDER BY id DESC LIMIT 50`,
      [req.params.id, stu.class_id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Complaints & remarks module: teacher complaints/special notices for the child
// plus per-exam teacher comments (remarks) written on the marksheet.
router.get('/student/:id/complaints', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [complaints] = await pool.query(
      `SELECT n.id, n.title, n.body, n.type, n.is_read, n.related_id, n.created_by, u.name AS teacher_name, n.created_at
       FROM notifications n LEFT JOIN users u ON u.id = n.created_by
       WHERE n.student_id = ? AND n.type IN ('complaint','special')
       ORDER BY n.id DESC LIMIT 100`,
      [req.params.id]
    );
    const [remarks] = await pool.query(
      `SELECT m.id, e.name AS exam_name, sub.name AS subject_name, e.status, m.comment, m.recorded_at
       FROM marks m
       JOIN exams e ON m.exam_id = e.id
       JOIN subjects sub ON e.subject_id = sub.id
       WHERE m.student_id = ? AND m.comment IS NOT NULL AND m.comment <> '' AND e.status = 'published'
       ORDER BY m.id DESC LIMIT 50`,
      [req.params.id]
    );
    res.json({ complaints, remarks });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/notifications', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT n.id, n.title, n.body, n.type, n.is_read, n.student_id, n.class_id, n.related_id AS exam_id, n.created_at
       FROM notifications n
       WHERE n.student_id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')
          OR (n.student_id IS NULL AND (n.class_id IS NULL OR n.class_id IN (
             SELECT class_id FROM students s WHERE s.id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')
          )))
       ORDER BY n.id DESC LIMIT 100`,
      [req.user.id, req.user.id]
    );
    const [[unread]] = await pool.query(
      `SELECT COUNT(*) AS cnt FROM notifications n
       WHERE n.is_read=0 AND (
         n.student_id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')
         OR (n.student_id IS NULL AND (n.class_id IS NULL OR n.class_id IN (
            SELECT class_id FROM students s WHERE s.id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')
         ))))`,
      [req.user.id, req.user.id]
    );
    res.json({ notifications: rows, unread: unread.cnt });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/notifications/read', async (req, res) => {
  const { ids, all } = req.body || {};
  try {
    const linked = `student_id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')`;
    const classesScope = `student_id IS NULL AND (class_id IS NULL OR class_id IN (
         SELECT class_id FROM students WHERE id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')))`;
    const scope = `(${linked} OR (${classesScope}))`;
    if (all) {
      await pool.query(`UPDATE notifications SET is_read=1 WHERE ${scope}`, [req.user.id, req.user.id]);
    } else if (Array.isArray(ids) && ids.length) {
      const placeholders = ids.map(() => '?').join(',');
      await pool.query(
        `UPDATE notifications SET is_read=1 WHERE id IN (${placeholders}) AND ${scope}`,
        [...ids, req.user.id, req.user.id]
      );
    } else {
      return res.status(400).json({ error: 'ids array or all:true required' });
    }
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Detailed single-result view (used by notification deep links)
router.get('/student/:id/result/:examId', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [rows] = await pool.query(
      `SELECT m.marks, m.total, m.comment, m.recorded_at,
              e.id AS exam_id, e.name AS exam_name, e.exam_type, e.exam_date, e.status,
              sub.name AS subject_name, c.name AS class_name, c.section,
              u.name AS teacher_name,
              ROUND(m.marks / m.total * 100, 1) AS percentage
       FROM marks m
       JOIN exams e ON m.exam_id = e.id
       JOIN subjects sub ON e.subject_id = sub.id
       JOIN classes c ON e.class_id = c.id
       LEFT JOIN users u ON m.recorded_by = u.id
       WHERE m.student_id = ? AND e.id = ?`,
      [req.params.id, req.params.examId]
    );
    if (rows.length === 0) return res.status(404).json({ error: 'Result not found' });
    if (rows[0].status !== 'published') return res.status(403).json({ error: 'Result not yet published' });
    res.json(rows[0]);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// GUARDIAN MARKSHEET (published-gated)
// Raw subject-wise marks are exposed via /student/:id/marks (published only).
// A full SSC-style marksheet is derived through the same grading engine the
// admin uses, but ONLY for exams whose status='published'. Unpublished admin
// exams NEVER leak to any guardian, even if the raw marks already exist.
// =====================================================================

// Published exam-events available to this student (for the marksheet picker)
router.get('/student/:id/exam-events', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [rows] = await pool.query(
      `SELECT e.id, e.name, e.start_date, e.exam_kind, e.year, e.session_id,
              ss.name AS session_name, ec.name AS result_class_name, ec.section AS result_section,
              prior.promoted_roll AS result_roll,
              (SELECT COUNT(*) FROM exams x JOIN marks xm ON xm.exam_id=x.id
                WHERE x.event_id=e.id AND xm.student_id=? AND x.status='published') AS subject_count
       FROM exam_events e
       LEFT JOIN sessions ss ON ss.id=e.session_id
       LEFT JOIN classes ec ON ec.id=(SELECT ex.class_id FROM exams ex JOIN marks em ON em.exam_id=ex.id
                                      WHERE ex.event_id=e.id AND em.student_id=? ORDER BY ex.id LIMIT 1)
       LEFT JOIN promotions prior ON prior.id=(SELECT pr.id FROM promotions pr
         WHERE pr.student_id=? AND pr.to_class=ec.name AND pr.destination_session_id=e.session_id
           AND pr.promoted_roll IS NOT NULL ORDER BY pr.id DESC LIMIT 1)
       WHERE EXISTS (SELECT 1 FROM exams x JOIN marks xm ON xm.exam_id=x.id
                      WHERE x.event_id=e.id AND xm.student_id=? AND x.status='published')
         AND e.is_published = 1
          AND (e.exam_kind<>'special_model_test' OR EXISTS (
            SELECT 1 FROM promotions mp JOIN exam_events src ON src.id=mp.event_id
            WHERE mp.student_id=? AND mp.destination_session_id=e.session_id AND mp.decision='promoted'
              AND src.exam_kind='test' AND src.year=e.year-1))
       ORDER BY e.id DESC`,
      [stu.id, stu.id, stu.id, stu.id, stu.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/marksheet', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const eventId = Number(req.query.event_id);
    if (!eventId) return res.status(400).json({ error: 'event_id query param required' });
    const [[pub]] = await pool.query(
      `SELECT COUNT(*) AS cnt FROM exams e JOIN marks m ON m.exam_id=e.id
        WHERE e.event_id = ? AND m.student_id = ? AND e.status = 'published'`,
      [eventId, stu.id]
    );
    if (!pub || pub.cnt === 0) return res.status(403).json({ error: 'Result not yet published' });
    const [[event]] = await pool.query('SELECT * FROM exam_events WHERE id = ?', [eventId]);
    if (!event) return res.status(404).json({ error: 'Exam event not found' });
    if (event.exam_kind === 'special_model_test') {
      const [[eligible]] = await pool.query(
        `SELECT mp.student_id FROM promotions mp JOIN exam_events src ON src.id=mp.event_id
         WHERE mp.student_id=? AND mp.destination_session_id=? AND mp.decision='promoted'
           AND src.exam_kind='test' AND src.year=? LIMIT 1`,
        [stu.id, event.session_id, Number(event.year) - 1]);
      if (!eligible) return res.status(403).json({ error: 'এই Special Model Test শুধু আগের বছরের Test-এ promoted শিক্ষার্থীদের জন্য।' });
    }
    const result = await computeResult(stu.id, eventId);
    if (!result) return res.status(404).json({ error: 'No result data for this exam' });
    // Q8 gate: conditional / not-all-pass students may not pull the full
    // marksheet detail. Only the outcome card is available to them.
    const [promoRows] = await pool.query(
      'SELECT decision FROM promotions WHERE student_id = ? AND event_id = ?', [stu.id, eventId]);
    const isConditional = promoRows.some(p => p.decision === 'grace_promoted' || p.decision === 'admin_override');
    if (isConditional || result.result_status !== 'PASSED') {
      return res.status(403).json({
        error: 'এই ফলাফলের বিস্তারিত মার্কশিট এখনো প্রকাশ করা হয়নি।',
        marksheet_hidden: true,
        promotion: promoRows.length ? {
          decision: promoRows[0].decision,
          status_bn: promoRows[0].decision === 'retained' ? 'উত্তীর্ণ নয়' : 'উত্তীর্ণ',
        } : null,
      });
    }
    const [[saved]] = await pool.query(
      'SELECT teacher_remarks FROM results WHERE student_id = ? AND exam_id = ?',
      [stu.id, eventId]
    );
    const [settingsRows] = await pool.query('SELECT setting_key, setting_value FROM app_settings');
    const settings = {};
    settingsRows.forEach(s => { settings[s.setting_key] = s.setting_value; });

    // Promotion status for promotional events (Annual for 6-9, Test for 10).
    // Exposes the guardian-friendly decision + new roll + year — never raw fails.
    let promotion = null;
    {
      const [[t]] = await pool.query(
        `SELECT COUNT(*) AS cnt FROM exams e JOIN marks m ON m.exam_id=e.id
          WHERE e.event_id = ? AND m.student_id = ? AND e.exam_type IN ('annual','test','class_test')`,
        [eventId, stu.id]
      );
      if (t && t.cnt > 0) {
        const [prows] = await pool.query(
          `SELECT decision, promoted_roll, to_class, passing_year FROM promotions WHERE student_id = ? AND event_id = ?`,
          [stu.id, eventId]
        );
        if (prows.length) {
          const p = prows[0];
          const promoted = p.decision !== 'retained';
          const conditional = p.decision === 'grace_promoted' || p.decision === 'admin_override';
          promotion = {
            promoted,
            conditional,
            status_bn: !promoted ? 'অনুত্তীর্ণ (Retained)' : (conditional ? 'শর্তসাপেক্ষে উত্তীর্ণ' : 'উত্তীর্ণ'),
            status_en: !promoted ? 'RETAINED' : (conditional ? 'CONDITIONALLY_PROMOTED' : 'PROMOTED'),
            decision: p.decision,
            to_class: p.to_class,
            promoted_roll: p.promoted_roll,
            passing_year: p.passing_year || null
          };
        }
      }
    }
    res.json({ student: stu, event, result, promotion, remarks: saved ? saved.teacher_remarks : null, settings });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// GUARDIAN RESULT CARD (published-gated)
// JSON + Bengali A4 PDF. Same grading engine as the admin marksheet, but
// promotion-aware: for a Class-10 (Test) exam whose promotion has been run
// by the admin, the card shows উত্তীর্ণ (promoted) with the NEW SSC roll,
// or উত্তীর্ণ নয় (not promoted). All other exam types show only GPA/marks.
// Guardians NEVER see the failed-subject breakdown beyond their own marks.
// =====================================================================

async function loadResultCardPayload(guardianId, studentId, eventId) {
  const stu = await getApprovedStudent(guardianId, studentId);
  if (!stu) return null;
  const [[pub]] = await pool.query(
    `SELECT COUNT(*) AS cnt FROM exams e JOIN marks m ON m.exam_id=e.id
      WHERE e.event_id = ? AND m.student_id = ? AND e.status = 'published'`,
    [eventId, stu.id]
  );
  if (!pub || pub.cnt === 0) return null; // not published yet
  const [[event]] = await pool.query('SELECT * FROM exam_events WHERE id = ?', [eventId]);
  if (!event) return null;
  const [[eventClass]] = await pool.query(
    `SELECT c.id AS class_id, c.name AS class_name, c.section, c.group_name
       FROM exams e JOIN marks m ON m.exam_id=e.id JOIN classes c ON c.id=e.class_id
      WHERE e.event_id=? AND m.student_id=? ORDER BY e.id LIMIT 1`, [eventId, stu.id]);
  const resultClassId = Number(eventClass && eventClass.class_id) || Number(stu.class_id);
  const resultStudent = eventClass ? { ...stu, class_name: eventClass.class_name, section: eventClass.section, group_name: eventClass.group_name } : stu;
  if (eventClass) {
    event.result_class_name = eventClass.class_name;
    event.result_section = eventClass.group_name || eventClass.section;
    const [[priorPromotion]] = await pool.query(
      `SELECT promoted_roll FROM promotions WHERE student_id=? AND to_class=?
         AND destination_session_id=? AND promoted_roll IS NOT NULL ORDER BY id DESC LIMIT 1`,
      [stu.id, eventClass.class_name, event.session_id]);
    event.result_roll = priorPromotion?.promoted_roll || null;
  }
  if (event.session_id) {
    const [[session]] = await pool.query('SELECT name FROM sessions WHERE id=?', [event.session_id]);
    event.session_name = session?.name || String(event.year || '');
  }
  const result = await computeResult(stu.id, eventId);
  if (!result) return null;
  const [settingsRows] = await pool.query('SELECT setting_key, setting_value FROM app_settings');
  const settings = {};
  settingsRows.forEach(s => { settings[s.setting_key] = s.setting_value; });

  // Guardian transcript activity snapshot, bounded by this academic session
  // and the result date. Each optional feed is isolated so an older database
  // missing a newer activity table can still serve the published result.
  const sessionName = String(event.year || event.name || '');
  const sessionYear = Number((sessionName.match(/20\d{2}/) || [])[0]) || new Date().getFullYear();
  const activityFrom = `${sessionYear}-01-01`;
  const activityTo = String(event.result_date || event.exam_date || dhakaToday()).slice(0, 10);
  const activities = await loadStudentActivities(pool, {
    studentId: stu.id, classId: resultClassId, eventId: Number(eventId),
    year: sessionYear, to: activityTo,
  });

  const examTypeList = await pool.query(
    `SELECT DISTINCT e.exam_type FROM exams e JOIN marks m ON m.exam_id=e.id
      WHERE e.event_id = ? AND m.student_id = ?`, [eventId, stu.id]);
  const examTypes = examTypeList[0].map(x => x.exam_type);

  // Promotion decision (if the admin has executed it for this class/event).
  // Friendly outcome. Q8 visibility rule:
  //   - class 6-9  : 'শর্তসাপেক্ষে উত্তীর্ণ' wording IS shown
  //   - class 10   : only "উত্তীর্ণ / উত্তীর্ণ নয়" — conditional words are hidden
  //   - a CONDITIONAL student's full marksheet is HIDDEN server-side (they may
  //     only see the binary outcome). A clean all-pass student sees everything.
  let promotion = null;
  let marksheet_hidden = false;
  {
    const [prows] = await pool.query(
      `SELECT decision, promoted_roll, to_class, passing_year FROM promotions WHERE student_id = ? AND event_id = ?`,
      [stu.id, eventId]
    );
    if (prows.length) {
      const p = prows[0];
      const promoted = p.decision !== 'retained';
      const conditional = p.decision === 'grace_promoted' || p.decision === 'admin_override';
      const isClass10 = /class\s*10|ssc/i.test(String(resultStudent.class_name || ''));
      promotion = {
        promoted,
        conditional,
        status_bn: !promoted ? 'অনুত্তীর্ণ (Retained)'
          : (conditional ? (isClass10 ? 'উত্তীর্ণ' : 'শর্তসাপেক্ষে উত্তীর্ণ') : 'উত্তীর্ণ'),
        status_en: !promoted ? 'RETAINED'
          : (conditional ? (isClass10 ? 'PROMOTED' : 'CONDITIONALLY_PROMOTED') : 'PROMOTED'),
        decision: p.decision,
        to_class: p.to_class,
        promoted_roll: p.promoted_roll,
        passing_year: p.passing_year || null,
      };
      // Q8: hide the detailed marksheet unless the student passed everything.
      if (conditional) marksheet_hidden = true;
    }
  }
  if (!marksheet_hidden && result.result_status !== 'PASSED') marksheet_hidden = true;
  // Merit position. Prefer the MATERIALIZED positions written at publish
  // time (Q9): section_position + combined_position are a snapshot, so a
  // late-joining student cannot silently shift everyone's rank. Fall back
  // to a live computation only when the snapshot is absent.
  let position = null;
  let dual_position = null;
  const subjectHighest = {};
  try {
    const [siblings] = await pool.query(
      `SELECT c.id, c.section, c.group_name FROM classes c
        WHERE c.name=(SELECT name FROM classes WHERE id=?)
          AND COALESCE(c.group_name,'')=COALESCE((SELECT group_name FROM classes WHERE id=?),'')
          AND EXISTS (SELECT 1 FROM exams ex WHERE ex.event_id=? AND ex.class_id=c.id)`,
      [resultClassId, resultClassId, eventId]);
    const siblingIds = siblings.map(c => Number(c.id));
    const [classmates] = siblingIds.length
      ? await pool.query('SELECT id, class_id FROM students WHERE class_id IN (?) ORDER BY id', [siblingIds])
      : await pool.query('SELECT id, class_id FROM students WHERE class_id=? ORDER BY id', [resultClassId]);
    const sectionByClass = new Map(siblings.map(c => [Number(c.id), String(c.section || c.group_name || '')]));
    const scored = [];
    for (const cm of classmates) {
      const r = await computeResult(cm.id, eventId);
      if (!r) continue;
      for (const f of (r.families || [])) {
        const cur = subjectHighest[f.subject];
        const tot = Number(f.total || 0);
        if (cur == null || tot > cur) subjectHighest[f.subject] = tot;
      }
      scored.push({
        id: cm.id, class_id: Number(cm.class_id), section: sectionByClass.get(Number(cm.class_id)) || '',
        gpa: Number(r.final_gpa || 0), total: Number(r.total_marks || 0),
      });
    }
    const gradeRank = g => { const n = Number(g || 0); return n >= 5 ? 7 : n >= 4 ? 6 : n >= 3.5 ? 5 : n >= 3 ? 4 : n >= 2 ? 3 : n >= 1 ? 2 : 1; };
    const tieKey = id => require('crypto').createHash('sha256').update(`merit:${eventId}:${id}`).digest('hex');
    scored.sort((a, b) => gradeRank(b.gpa) - gradeRank(a.gpa) || (b.total - a.total) || tieKey(a.id).localeCompare(tieKey(b.id)));
    const idx = scored.findIndex(s => s.id === stu.id);
    const totalRanked = scored.length;
    if (idx !== -1) position = { rank: idx + 1, of: totalRanked };
    const counters = new Map();
    const sectionTotals = new Map();
    for (const row of scored) sectionTotals.set(row.section, (sectionTotals.get(row.section) || 0) + 1);
    let calculatedDual = null;
    for (let i = 0; i < scored.length; i++) {
      const row = scored[i];
      const localRank = (counters.get(row.section) || 0) + 1;
      counters.set(row.section, localRank);
      if (Number(row.id) === Number(stu.id)) calculatedDual = {
        section: localRank, section_of: sectionTotals.get(row.section) || 0,
        combined: i + 1, combined_of: totalRanked,
      };
    }

    // Materialized snapshot (authoritative when present).
    const [snap] = await pool.query(
      `SELECT section_position, combined_position, section_size, combined_size, total_marks_obtained, total_marks_full, pass_all
         FROM results r JOIN exams e ON e.id = r.exam_id
        WHERE r.student_id = ? AND e.event_id = ? LIMIT 1`, [stu.id, eventId]);
    if (snap.length && (snap[0].section_position != null || snap[0].combined_position != null)) {
      dual_position = {
        section: snap[0].section_position != null ? snap[0].section_position : (position ? position.rank : null),
        combined: snap[0].combined_position != null ? snap[0].combined_position : (position ? position.rank : null),
        section_of: Number(snap[0].section_size || calculatedDual?.section_of || totalRanked),
        combined_of: Number(snap[0].combined_size || calculatedDual?.combined_of || totalRanked),
      };
    } else if (calculatedDual) {
      dual_position = calculatedDual;
    }
  } catch (e) { /* rank optional */ }


  // Attendance percentage: all recorded working days since join.
  let attendance = null;
  try {
    const [[att]] = await pool.query(
      `SELECT COUNT(*) AS total, SUM(CASE WHEN status='present' THEN 1 ELSE 0 END) AS present
       FROM attendance WHERE student_id=? AND date BETWEEN ? AND ?`, [stu.id, activityFrom, activityTo]);
    const total = Number(att.total || 0);
    attendance = {
      total_days: total,
      present_days: Number(att.present || 0),
      percentage: total ? +((Number(att.present || 0) / total) * 100).toFixed(1) : null,
    };
  } catch (e) { /* attendance optional */ }
  // Signature stamps: class teacher + head teacher (auto-attached by role).
  // Head = whoever currently holds the exclusive Head Teacher post;
  // CT = the class_teacher of the student's class. Falls back to school logo.
  let signatures = { class_teacher: null, head_teacher: null };
  try {
    const [[ct]] = await pool.query(
      `SELECT u.id, u.name, u.designation, u.signature, u.signature_name
       FROM classes c JOIN users u ON u.id=c.teacher_id WHERE c.id=?`, [resultClassId]);
    const [heads] = await pool.query(
      `SELECT id, name, designation, signature, signature_name FROM users WHERE role='teacher'
        AND LOWER(TRIM(designation)) IN ('head teacher','headmaster','principal') LIMIT 1`);
    const head = heads[0] || null;
    const pack = async (u, fallback) => {
      if (!u) return null;
      const bytes = await loadTeacherSignature(u.signature);
      return { name: u.signature_name || u.name, designation: u.designation || fallback,
        data_base64: bytes ? bytes.toString('base64') : null };
    };
    signatures = { class_teacher: await pack(ct, 'শ্রেণি শিক্ষক'), head_teacher: await pack(head, 'প্রধান শিক্ষক') };
  } catch (e) { /* signatures optional */ }
  return { student: resultStudent, event, result, promotion, position, dual_position, marksheet_hidden, subject_highest: subjectHighest, attendance, activities, activity_period: { from: activities.from, to: activities.to }, settings, examTypes, signatures };
}

router.get('/student/:id/result-card', async (req, res) => {
  try {
    const eventId = Number(req.query.event_id);
    if (!eventId) return res.status(400).json({ error: 'event_id required' });
    const payload = await loadResultCardPayload(req.user.id, req.params.id, eventId);
    if (!payload) return res.status(403).json({ error: 'Result not published / not authorized' });
    // Q8: a conditional / not-all-pass student gets ONLY the binary outcome —
    // the subject-by-subject detail is withheld server-side.
    if (payload.marksheet_hidden) {
      return res.json({
        student: payload.student, event: payload.event,
        promotion: payload.promotion, position: payload.position,
        dual_position: payload.dual_position,
        marksheet_hidden: true, result: null,
        attendance: payload.attendance, activities: payload.activities,
        activity_period: payload.activity_period, settings: payload.settings,
      });
    }
    res.json(payload);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/result-card.pdf', async (req, res) => {
  try {
    const eventId = Number(req.query.event_id);
    if (!eventId) return res.status(400).json({ error: 'event_id required' });
    const payload = await loadResultCardPayload(req.user.id, req.params.id, eventId);
    if (!payload) return res.status(403).json({ error: 'Result not published / not authorized' });
    const { student, event, result, promotion, position, dual_position, attendance, settings, signatures } = payload;
    const fontPath = path.join(__dirname, '..', 'assets', 'fonts', 'Kalpurush.ttf');
    const doc = new PDFDocument({ size: 'A4', margin: 42, bufferPages: true });
    const hasBd = fs.existsSync(fontPath);
    if (hasBd) doc.registerFont('Kalpurush', fontPath);
    const BOLD = hasBd ? 'Kalpurush' : 'Helvetica-Bold';
    const NORMAL = hasBd ? 'Kalpurush' : 'Helvetica';

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition',
      `attachment; filename=result_card_${student.student_code}_${eventId}.pdf`);
    doc.pipe(res);

    const CW = doc.page.width - 84;
    let y = 44;
    // School watermark (transcript-generator design): faint logo centered.
    const wmPaths = [
      path.join(__dirname, '..', 'assets', 'school-watermark.png'),
      path.join(__dirname, '..', 'assets', 'logo.png'),
    ];
    for (const wp of wmPaths) {
      if (fs.existsSync(wp)) {
        try {
          doc.save();
          doc.opacity(0.07);
          const S = 320;
          doc.image(wp, (doc.page.width - S) / 2, (doc.page.height - S) / 2, { width: S, height: S });
          doc.restore();
        } catch (_) {}
        break;
      }
    }
    const schoolName = settings.school_name || settings.school || settings.school_name_en || 'School';
    const schoolAddr = settings.school_address || settings.address || '';
    doc.font(BOLD).fontSize(15).fillColor('#0b3d91').text(String(schoolName), 42, y, { align: 'center', width: CW });
    y += 20;
    if (schoolAddr) {
      doc.font(NORMAL).fontSize(9).fillColor('#555').text(String(schoolAddr), 42, y, { align: 'center', width: CW });
      y += 14;
    }
    doc.font(BOLD).fontSize(12).fillColor('#111').text('ফলাফল কার্ড / Result Card', 42, y, { align: 'center', width: CW });
    y += 11;
    doc.font(NORMAL).fontSize(9.5).fillColor('#333').text(String(event.name) + '  •  ' + String(student.class_name || ''), 42, y, { align: 'center', width: CW });
    y += 22;

    // ---- Promotion banner (any executed promotion) ----
    if (promotion) {
      const bannerY = y;
      const bannerBg = promotion.promoted
        ? (promotion.conditional ? '#fff8e1' : '#e8f5e9')
        : '#fdecea';
      doc.roundedRect(42, bannerY, CW, 48, 5).fillColor(bannerBg).fill();
      const bannerFg = promotion.promoted
        ? (promotion.conditional ? '#8d6e00' : '#1b5e20')
        : '#b71c1c';
      doc.fillColor(bannerFg).fill();
      doc.font(BOLD).fontSize(21).text(promotion.status_bn, 52, bannerY + 4, { width: CW - 20, align: 'left' });
      const sub = promotion.promoted
        ? `${promotion.to_class || 'পরবর্তী শ্রেণি'} এ প্রচারিত${promotion.promoted_roll != null ? '  •  নতুন রোল: ' + promotion.promoted_roll : ''}${promotion.passing_year != null ? '  •  SSC ' + promotion.passing_year : ''}`
        : 'এই পরীক্ষায় উত্তীর্ণ হতে পারেননি';
      doc.font(NORMAL).fontSize(9.5)
        .text(sub, 52, bannerY + 30, { width: CW - 20 });
      y = bannerY + 58;
    }

    // ---- Student identity (rank + attendance on the card) ----
    doc.font(BOLD).fontSize(11).fillColor('#0b5394').text('শিক্ষার্থীর তথ্য / Student Info', 42, y);
    y += 16;
    const rows = [
      ['নাম / Name', String(student.name || '')],
      ['রোল / Roll', String(student.roll || '')],
      ['শ্রেণি / Class', `${student.class_name || ''}${student.section ? ' (' + student.section + ')' : ''}`],
      ['আইডি / Student ID', String(student.student_code || '')],
      ['মেধা স্থান / Merit Position', dual_position
        ? `${dual_position.section ?? '—'} / ${dual_position.section_of ?? '—'} (শাখা), ${dual_position.combined ?? '—'} / ${dual_position.combined_of ?? '—'} (সব শাখা)`
        : position ? `${position.rank} / ${position.of} জন` : '—'],
      ['উপস্থিতি / Attendance', attendance && attendance.percentage != null
        ? `${attendance.percentage}% (${attendance.present_days}/${attendance.total_days} দিন)` : '—'],
    ];
    rows.forEach(([k, v]) => {
      doc.font(NORMAL).fontSize(9.5).fillColor('#333').text(k + ':', 42, y, { width: 150 });
      doc.font(BOLD).fillColor('#111').text(String(v), 130, y, { width: CW - 88 });
      y += 13;
    });
    y += 10;

    // ---- Subject result table ----
    const th = () => { doc.font(BOLD).fontSize(9).fillColor('#ffffff'); };
    const cols = [215, 70, 75, 85, 85].map(w => w); // Subject Total Scaled% Grade GPA
    const rowH = 18;
    const tableX = 42;
    doc.rect(tableX, y, CW, rowH).fill('#0b5394');
    th();
    let cx = tableX;
    ['বিষয় / Subject', 'প্রাপ্ত', 'শতকরা', 'গ্রেড', 'GPA'].forEach((t, i) => {
      doc.text(t, cx + 5, y + 5, { width: cols[i] - 10, align: i === 0 ? 'left' : 'center' });
      cx += cols[i];
    });
    y += rowH;
    (payload.marksheet_hidden ? [] : (result.families || [])).forEach((f, i) => {
      if (y > doc.page.height - 60) { doc.addPage(); y = 40; }
      if (i % 2 === 0) { doc.fillColor('#eef3f9').rect(tableX, y, CW, rowH).fill(); }
      doc.fillColor('#111').font(NORMAL).fontSize(9);
      const subject = (f.is_optional ? '(৪র্থ) ' : '') + (f.subject || '');
      cx = tableX;
      doc.text(subject, cx + 5, y + 5, { width: cols[0] - 10 }); cx += cols[0];
      doc.text(f.absent ? '—' : `${f.total}/${f.full}`, cx + 5, y + 5, { width: cols[1] - 10, align: 'center' }); cx += cols[1];
      doc.text(f.absent ? '—' : f.scaled.toFixed(2) + '%', cx + 5, y + 5, { width: cols[2] - 10, align: 'center' }); cx += cols[2];
      doc.text(f.absent ? '—' : f.letter_grade, cx + 5, y + 5, { width: cols[3] - 10, align: 'center' }); cx += cols[3];
      doc.text(f.absent ? '—' : f.grade_point.toFixed(1), cx + 5, y + 5, { width: cols[4] - 10, align: 'center' });
      y += rowH;
    });
    if (!payload.marksheet_hidden) doc.strokeColor('#0b5394').lineWidth(1).rect(tableX, y - rowH * (result.families || []).length, CW, rowH * (result.families || []).length).stroke();
    y += 14;

    // ---- GPA summary ----
    if (!payload.marksheet_hidden) doc.font(BOLD).fontSize(10.5).fillColor('#0b5394')
      .text(`ফলাফল: ${result.result_status === 'PASSED' ? 'পাস' : (result.result_status === 'ABSENT' ? 'অনুপস্থিত' : 'ফেল')}      মোট নম্বর: ${Number(result.total_marks || 0)}/${Number(result.total_full || 0)}      ফাইনাল GPA: ${Number(result.final_gpa || 0).toFixed(2)}`, 42, y, { width: CW });
    y += 18;

    if (payload.remarks) {
      doc.font(BOLD).fontSize(9.5).fillColor('#111').text('শিক্ষকের মন্তব্য:', 42, y);
      y += 14;
      doc.font(NORMAL).fontSize(9.5).fillColor('#333').text(String(payload.remarks), 42, y, { width: CW });
      y += 18;
    }

    // signatures — transcript-generator style: school watermark on the page,
    // signature stamps (auto-attached) above each name line.
    y = Math.max(y + 8, doc.page.height - 150);
    const drawSigBlock = (sig, fallbackTitle, x) => {
      let imgTop = y;
      if (sig && sig.data_base64) {
        try {
          doc.image(Buffer.from(sig.data_base64, 'base64'), x + 25, y, { fit: [110, 34], align: 'center' });
          imgTop = y + 34;
        } catch (_) { /* stamp optional */ }
      }
      doc.font(NORMAL).fontSize(9.5).fillColor('#111');
      doc.text('─'.repeat(18), x, imgTop + 2, { width: 160, align: 'center' });
      doc.font(BOLD).fontSize(9.5).text(sig && sig.name ? String(sig.name) : fallbackTitle, x, imgTop + 15, { width: 160, align: 'center' });
      doc.font(NORMAL).fontSize(8.5).fillColor('#555')
        .text(sig && sig.designation ? String(sig.designation) : fallbackTitle, x, imgTop + 28, { width: 160, align: 'center' });
    };
    doc.font(NORMAL).fontSize(9.5).fillColor('#111');
    drawSigBlock(signatures.class_teacher, 'শ্রেণি শিক্ষক', 60);
    drawSigBlock(signatures.head_teacher, 'প্রধান শিক্ষক', doc.page.width - 220);

    // Page two is reserved for session activity; the academic result remains
    // on page one. A retained student receives the same PDF without any
    // subject-level marks being disclosed.
    doc.addPage();
    y = 44;
    doc.font(BOLD).fontSize(15).fillColor('#0b3d91').text(String(schoolName), 42, y, { align: 'center', width: CW });
    y += 22;
    doc.font(BOLD).fontSize(13).fillColor('#111').text('শিক্ষাবর্ষের কার্যক্রম / Session Activity', 42, y, { align: 'center', width: CW });
    y += 20;
    doc.font(NORMAL).fontSize(9).fillColor('#555').text(`${payload.activity_period.from} থেকে ${payload.activity_period.to} পর্যন্ত`, 42, y, { align: 'center', width: CW });
    y += 24;
    const activitySection = (title, rows, format) => {
      if (!rows || !rows.length) return;
      if (y > doc.page.height - 72) { doc.addPage(); y = 42; }
      doc.font(BOLD).fontSize(10.5).fillColor('#0b5394').text(title, 42, y, { width: CW });
      y += 17;
      for (const row of rows) {
        if (y > doc.page.height - 44) { doc.addPage(); y = 42; }
        doc.font(NORMAL).fontSize(10).fillColor('#222').text(format(row), 48, y, { width: CW - 12 });
        y = doc.y + 4;
      }
      y += 8;
    };
    const acts = payload.activities || {};
    const attendanceActivity = r => ({
      p5_stayed: '৫ম পিরিয়ড পর্যন্ত স্কুলে ছিলেন',
      early_departure_with_leave: 'ছুটি নিয়ে প্রস্থান',
      early_departure_no_leave: 'ছুটি ছাড়া প্রস্থান',
      present: 'উপস্থিত', absent: 'অনুপস্থিত', late: 'দেরি', leave: 'ছুটি',
    }[r.final_state || r.status] || r.final_state || r.status || '—');
    activitySection('উপস্থিতি', acts.attendance, r => `${String(r.date).slice(0,10)} • ${r.session === 'p5' ? '৫ম পিরিয়ড' : 'সকাল'} • ${attendanceActivity(r)}${r.remark ? ' • ' + r.remark : ''}`);
    activitySection('শ্রেণিকক্ষের দৈনিক অগ্রগতি', acts.daily_reports, r => `${String(r.report_date).slice(0,10)} • ${r.subject_name} • পাঠ: ${r.learning_status} • কাজ: ${r.homework_status} • ${r.performance}${r.note ? ' • ' + r.note : ''}`);
    activitySection('শ্রেণি পরীক্ষা ও অন্যান্য মূল্যায়ন', acts.class_tests, r => `${r.exam_name} • ${r.subject_name} • ${r.absent ? 'অনুপস্থিত' : `${r.marks}/${r.total}`}`);
    activitySection('বাড়ির কাজ', acts.homework, r => `${String(r.due_date || '').slice(0,10)} • ${r.subject_name || ''} • ${r.title}${r.description ? ' — ' + r.description : ''}`);
    if (y === 88) doc.font(NORMAL).fontSize(10).fillColor('#555').text('এই সেশনের জন্য কোনো অতিরিক্ত কার্যক্রম নথিভুক্ত নেই।', 42, y, { width: CW, align: 'center' });

    const pages = doc.bufferedPageRange();
    for (let i = pages.start; i < pages.start + pages.count; i++) {
      doc.switchToPage(i);
      doc.font(NORMAL).fontSize(8).fillColor('#888')
        .text(`পৃষ্ঠা ${i - pages.start + 1} / ${pages.count}  •  Generated ${dhakaToday()}`,
          42, doc.page.height - 30, { align: 'center', width: CW });
    }
    doc.end();
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// RE-EXAM REQUESTS — guardian-রা published result-এর পর re-exam আবেদন করে।
// Flow: guardian আবেদন করে (reason সহ) → admin approve করলে ওই student-এর
// সংশ্লিষ্ট exam-এর entry reopen (unlock) হয় → admin/teacher number ঠিক
// করে → admin result republish করে → guardian নতুন result দেখে।
// =====================================================================
router.post('/reexam-request', async (req, res) => {
  const { student_id, event_id, reason } = req.body || {};
  if (!student_id || !event_id) {
    return res.status(400).json({ error: 'student_id and event_id required' });
  }
  try {
    const stu = await getApprovedStudent(req.user.id, student_id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [[pub]] = await pool.query(
      `SELECT COUNT(*) AS cnt FROM exams WHERE event_id=? AND class_id=? AND status='published'`,
      [event_id, stu.class_id]);
    if (!pub || pub.cnt === 0) {
      return res.status(400).json({ error: 'এই পরীক্ষার result এখনো publish হয়নি — publish-এর পর আবেদন করা যাবে।' });
    }
    const [[exists]] = await pool.query(
      `SELECT id FROM reexam_requests WHERE guardian_id=? AND student_id=? AND event_id=? AND status='pending'`,
      [req.user.id, student_id, event_id]);
    if (exists) {
      return res.status(409).json({ error: 'এই পরীক্ষার জন্য ইতিমধ্যে একটি pending আবেদন আছে।' });
    }
    const [r] = await pool.query(
      `INSERT INTO reexam_requests (guardian_id, student_id, event_id, class_id, reason, status)
       VALUES (?,?,?,?,?, 'pending')`,
      [req.user.id, student_id, event_id, stu.class_id, (reason || '').slice(0, 1000) || null]);
    res.status(201).json({ ok: true, id: r.insertId });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/reexam-requests', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT r.*, s.name AS student_name, s.roll, e.name AS event_name
       FROM reexam_requests r
       JOIN students s ON s.id=r.student_id
       JOIN exam_events e ON e.id=r.event_id
       WHERE r.guardian_id=? ORDER BY r.id DESC LIMIT 100`,
      [req.user.id]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// SIBLING LINKING WITH ADMIN APPROVAL
// =====================================================================
// Guardian submits full identity of a sibling; backend verifies the details
// match a REAL student record, then creates a PENDING link. The student's
// data stays invisible until an admin approves the request.
router.post('/sibling-request', async (req, res) => {
  const { student_code, dob, class_name, section, roll, phone, relation } = req.body || {};
  if (!student_code || !dob || !class_name || !section || !roll || !phone) {
    return res.status(400).json({ error: 'All fields required: student code, DOB, class, section, roll, phone' });
  }
  try {
    const [[requester]] = await pool.query(
      `SELECT s.id FROM students s
       WHERE s.id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')
       ORDER BY s.id LIMIT 1`,
      [req.user.id]
    );
    if (!requester) return res.status(403).json({ error: 'No approved student on this account yet' });

    // Verify the submitted identity matches a REAL student (same checks as login)
    const [rows] = await pool.query(
      `SELECT s.*, c.name AS class_name, c.section
       FROM students s JOIN classes c ON s.class_id = c.id
       WHERE s.student_code = ?`, [String(student_code).trim()]
    );
    if (rows.length === 0) return res.status(404).json({ error: 'Student not found with this ID' });
    const s = rows[0];
    const d = s.dob instanceof Date ? s.dob : new Date(s.dob);
    const dobStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    if (!s.dob || dobStr !== String(dob).trim()) return res.status(401).json({ error: 'Date of birth does not match' });
    const storedClassNum = (String(s.class_name).match(/\d+/) || [])[0];
    const givenClassNum = (String(class_name).match(/\d+/) || [])[0];
    if (!storedClassNum || !givenClassNum || storedClassNum !== givenClassNum) {
      return res.status(401).json({ error: 'Class does not match' });
    }
    if (String(s.section).toLowerCase() !== String(section).toLowerCase()) {
      return res.status(401).json({ error: 'Section does not match' });
    }
    if (Number(s.roll) !== Number(roll)) return res.status(401).json({ error: 'Roll number does not match' });
    const mainPhone = String(s.guardian_phone || '').trim();
    if (!mainPhone || mainPhone.replace(/[^0-9]/g, '').slice(-11) !== String(phone).replace(/[^0-9]/g, '').slice(-11)) {
      return res.status(401).json({ error: 'Phone number does not match admission record' });
    }
    if (String(s.id) === String(requester.id)) {
      return res.status(400).json({ error: 'This student is already linked to the account' });
    }

    await pool.query(
      `INSERT INTO guardian_links (guardian_id, student_id, role, status, requester_student_id)
       VALUES (?,?,'sibling','pending',?)
       ON CONFLICT (guardian_id, student_id) DO UPDATE SET status='pending', requester_student_id=EXCLUDED.requester_student_id`,
      [req.user.id, s.id, requester.id]
    );
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'sibling_request', 'Sibling link requested for student ' + s.id]);
    res.status(201).json({ ok: true, status: 'pending', message: 'Request sent for admin approval. The student will be visible once approved.' });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/sibling-requests', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT gl.id, gl.student_id, gl.status, gl.requested_at,
              s.name AS student_name, c.name AS class_name, c.section
       FROM guardian_links gl
       JOIN students s ON gl.student_id = s.id
       JOIN classes c ON s.class_id = c.id
       WHERE gl.guardian_id=? AND gl.role='sibling'
       ORDER BY gl.id DESC LIMIT 50`,
      [req.user.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// Result analytics (Q9 enhancement): subject-wise % for the latest
// published event + a trend across past events + session GPA (Q2).
// Everything is derived from data the app already has via the API.
// =====================================================================
router.get('/student/:id/result-analytics', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });

    // Published events from every session remain available after promotion.
    const [events] = await pool.query(
      `SELECT DISTINCT e.id, e.name, e.exam_kind, e.year, e.start_date, e.is_published
         FROM exam_events e
         JOIN exams x ON x.event_id = e.id
        WHERE e.is_published = 1
          AND (e.exam_kind<>'special_model_test' OR EXISTS (
            SELECT 1 FROM promotions mp JOIN exam_events src ON src.id=mp.event_id
            WHERE mp.student_id=? AND mp.destination_session_id=e.session_id AND mp.decision='promoted'
              AND src.exam_kind='test' AND src.year=e.year-1))
        ORDER BY e.start_date DESC NULLS LAST, e.id DESC`, [stu.id]);

    const history = [];
    for (const ev of events) {
      const r = await computeResult(stu.id, ev.id);
      if (!r) continue;
      history.push({
        event_id: ev.id, event_name: ev.name, exam_kind: ev.exam_kind, year: ev.year,
        final_gpa: r.final_gpa, result_status: r.result_status,
        total_marks: r.total_marks, total_full: r.total_full,
        subjects: (r.families || []).map(f => ({
          subject: f.subject, total: f.total, full: f.full,
          scaled: f.scaled, letter_grade: f.letter_grade, grade_point: f.grade_point,
        })),
      });
    }

    // Session GPA (weighted across exam kinds).
    let session = null;
    try {
      const { sessionGpa } = require('../session_gpa');
      session = await sessionGpa(stu.id, stu.session_id);
    } catch (e) { /* optional */ }

    res.json({ student: stu, history, session_gpa: session });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;
