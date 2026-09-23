const router = require('express').Router();
const pool = require('../db');
const { auth } = require('../middleware/auth');
const { computeResult } = require('../grading');

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
      `SELECT s.id, s.name, s.student_code, s.roll, s.dob, s.class_id, c.name AS class_name, c.section
       FROM students s JOIN classes c ON s.class_id = c.id
       WHERE ${APPROVED_SCOPE} ORDER BY s.id`,
      [req.user.id]
    );
    const [notifications] = await pool.query(
      `SELECT n.id, n.title, n.body, n.type, n.created_at
       FROM notifications n
       WHERE n.student_id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')
          OR (n.student_id IS NULL AND (n.class_id IS NULL OR n.class_id IN (
             SELECT class_id FROM students WHERE id IN (SELECT student_id FROM guardian_links WHERE guardian_id=? AND status='approved')
          )))
       ORDER BY n.id DESC LIMIT 50`,
      [req.user.id, req.user.id]
    );
    res.json({ guardian: req.user, students, notifications });
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
    const [rows] = await pool.query(
      'SELECT date, status, remark FROM attendance WHERE student_id=? ORDER BY date DESC LIMIT 60',
      [req.params.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/marks', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [rows] = await pool.query(
      `SELECT m.marks, m.total, m.comment, e.name AS exam_name, e.exam_type, e.exam_date, e.id AS exam_id, sub.name AS subject_name
       FROM marks m JOIN exams e ON m.exam_id = e.id JOIN subjects sub ON e.subject_id = sub.id
       WHERE m.student_id = ? AND e.status = 'published' ORDER BY e.id DESC, sub.id`,
      [req.params.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/homework', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [rows] = await pool.query(
      `SELECT h.id, h.title, h.description, h.due_date,
              sub.name AS subject_name, u.name AS teacher_name, h.created_at
       FROM homework h
       LEFT JOIN subjects sub ON h.subject_id = sub.id
       LEFT JOIN users u ON h.created_by = u.id
       WHERE h.class_id = ?
       ORDER BY h.id DESC LIMIT 50`,
      [stu.class_id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/student/:id/notifications', async (req, res) => {
  try {
    const stu = await getApprovedStudent(req.user.id, req.params.id);
    if (!stu) return res.status(403).json({ error: 'Not authorized for this student' });
    const [rows] = await pool.query(
      `SELECT id, title, body, type, related_id AS exam_id, created_at FROM notifications
       WHERE student_id = ? OR (student_id IS NULL AND (class_id IS NULL OR class_id = ?))
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
      `SELECT e.id, e.name, e.start_date,
              (SELECT COUNT(*) FROM exams x WHERE x.event_id = e.id AND x.class_id = ? AND x.status='published') AS subject_count
       FROM exam_events e
       WHERE e.id IN (SELECT DISTINCT event_id FROM exams WHERE class_id = ? AND status = 'published')
       ORDER BY e.id DESC`,
      [stu.class_id, stu.class_id]
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
      `SELECT COUNT(*) AS cnt FROM exams WHERE event_id = ? AND class_id = ? AND status = 'published'`,
      [eventId, stu.class_id]
    );
    if (!pub || pub.cnt === 0) return res.status(403).json({ error: 'Result not yet published' });
    const [[event]] = await pool.query('SELECT * FROM exam_events WHERE id = ?', [eventId]);
    if (!event) return res.status(404).json({ error: 'Exam event not found' });
    const result = await computeResult(stu.id, eventId);
    if (!result) return res.status(404).json({ error: 'No result data for this exam' });
    const [[saved]] = await pool.query(
      'SELECT teacher_remarks FROM results WHERE student_id = ? AND exam_id = ?',
      [stu.id, eventId]
    );
    const [settingsRows] = await pool.query('SELECT setting_key, setting_value FROM app_settings');
    const settings = {};
    settingsRows.forEach(s => { settings[s.setting_key] = s.setting_value; });
    res.json({ student: stu, event, result, remarks: saved ? saved.teacher_remarks : null, settings });
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

module.exports = router;