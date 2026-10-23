const router = require('express').Router();
const bcrypt = require('bcrypt');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const pool = require('../db');
const { auth } = require('../middleware/auth');
const { computeResult } = require('../grading');
const { queuePush, getAllGuardianTokens, getGuardianTokens } = require('../fcm');
const { validateStudent, validateMarksValue } = require('../validate');
const { ymd } = require('../dates');
const { ensureSessionExams, ensureSessionHorizon, syncCanonicalEventClasses } = require('./results');
const { getUnifiedExamDashboard } = require('../lib/exam_dashboard');
const { getEntryProgress, importMarks, getMarksheetTemplate, saveMarksheetTemplate, getExamCalendar, updateExamDates, getAnalytics, autoCreateSubjectExams, validateConflicts } = require('../lib/exam_progress');
const { uploadSchoolLogo } = require('../lib/school_logo');
const { getClassSignatories } = require('../lib/teacher_signatures');

const uploadsDir = process.env.VERCEL_UPLOAD_DIR
  ? path.join(process.env.VERCEL_UPLOAD_DIR, 'photos')
  : path.join(__dirname, '..', 'uploads', 'photos');
if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });
const photoUpload = multer({
  storage: multer.diskStorage({
    destination: uploadsDir,
    filename: (req, file, cb) => {
      const ext = (path.extname(file.originalname) || '.jpg').toLowerCase();
      cb(null, 'stu_' + Date.now() + '_' + Math.floor(Math.random() * 10000) + ext);
    }
  }),
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (/^image\/(jpeg|png|webp)$/.test(file.mimetype)) cb(null, true);
    else cb(new Error('Only JPG/PNG/WebP images allowed'));
  }
});

router.use(auth('admin'));

function log(userId, action, detail) {
  return pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)', [userId, action, detail || '']).catch(() => {});
}

async function genStudentCode() {
  for (let i = 0; i < 30; i++) {
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const [[row]] = await pool.query('SELECT id FROM students WHERE student_code=?', [code]);
    if (!row) return code;
  }
  throw new Error('Could not generate unique code');
}

// Religion-subject auto-allocation (NCTB): every Religion & Moral Education subject in the
// student's class is auto-attached as mandatory. Named so because the same subject serves
// Islam / Hindu students via subject_aliases; the student's religion drives display only.
async function autoAssignReligionSubjects(studentId, classId, religion, assignedBy = null) {
  if (!classId || !religion) return;
  const [subjects] = await pool.query(
    `SELECT sub.id FROM subjects sub
     WHERE sub.class_id = ? AND (
        sub.name ILIKE '%religion%' OR sub.name ILIKE '%islam%' OR sub.name ILIKE '%hindu%'
     )`,
    [classId]
  );
  for (const s of subjects) {
    const [[existing]] = await pool.query(
      'SELECT id FROM student_subjects WHERE student_id=? AND subject_id=?', [studentId, s.id]
    );
    if (!existing) {
      await pool.query(
        'INSERT INTO student_subjects (student_id, subject_id, is_mandatory, is_fourth_subject, is_elective, assigned_by) VALUES (?,?,1,0,0,?)',
        [studentId, s.id, assignedBy]
      );
    }
  }
}

router.get('/stats', async (req, res) => {
  try {
    const [[students]] = await pool.query('SELECT COUNT(*) AS total FROM students');
    const [[teachers]] = await pool.query("SELECT COUNT(*) AS total FROM users WHERE role='teacher'");
    const [[classes]] = await pool.query('SELECT COUNT(*) AS total FROM classes');
    const [[guardians]] = await pool.query("SELECT COUNT(*) AS total FROM users WHERE role='guardian'");
    const [[exams]] = await pool.query('SELECT COUNT(*) AS total FROM exams');
    const [today] = await pool.query(
      "SELECT status, COUNT(*) AS cnt FROM attendance WHERE date = CURDATE() GROUP BY status"
    );
    res.json({
      students: students.total, teachers: teachers.total, classes: classes.total,
      guardians: guardians.total, exams: exams.total,
      todayAttendance: today
    });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/activity', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT a.*, u.name AS user_name FROM activity_log a
       LEFT JOIN users u ON a.user_id = u.id ORDER BY a.id DESC LIMIT 50`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/delete-logs', async (req, res) => {
  const beforeId = Number(req.query.before || 0);
  const limit = Math.min(200, Math.max(1, Number(req.query.limit || 100)));
  try {
    const [rows] = await pool.query(
      `SELECT a.id, a.action, a.detail, a.created_at, a.user_id, u.name AS admin_name
       FROM activity_log a LEFT JOIN users u ON u.id=a.user_id
       WHERE a.action IN ('student_delete','event_delete','exam_delete') AND (?=0 OR a.id<?)
       ORDER BY a.id DESC LIMIT ?`, [beforeId, beforeId, limit]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// SIBLING-LINK APPROVAL WORKFLOW
// =====================================================================
// Guardians can only see their OWN (login) child. To see a sibling they
// must submit a request (code/DOB/class/roll/phone), which lands here as
// pending. Admin either APPROVES (link becomes active, guardian/father/
// mother name + address common) or REJECTS — until then the sibling's
// data is invisible to the guardian.
// =====================================================================
router.get('/sibling-requests', async (req, res) => {
  const status = req.query.status || 'pending';
  try {
    const [rows] = await pool.query(
      `SELECT gl.id, gl.role, gl.status, gl.requested_at, gl.decided_at, gl.remark,
              u.id AS guardian_id, u.name AS guardian_name, u.phone AS guardian_phone,
              rs.name AS requester_name, rs.roll AS requester_roll, rs.student_code AS requester_code,
              s.id AS student_id, s.name AS student_name, s.student_code, s.roll, s.dob,
              c.name AS class_name, c.section
       FROM guardian_links gl
       JOIN users u ON gl.guardian_id = u.id
       JOIN students s ON gl.student_id = s.id
       JOIN classes c ON s.class_id = c.id
       LEFT JOIN students rs ON gl.requester_student_id = rs.id
       WHERE gl.status = ?
       ORDER BY gl.id DESC LIMIT 100`,
      [status]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/sibling-requests/:id/approve', async (req, res) => {
  try {
    const [[reqRow]] = await pool.query('SELECT * FROM guardian_links WHERE id=?', [req.params.id]);
    if (!reqRow) return res.status(404).json({ error: 'Request not found' });
    if (reqRow.status !== 'pending') return res.status(400).json({ error: 'Request already ' + reqRow.status });

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      // The requester's own child = source of the shared guardian/father/mother/address
      const [sourceRows] = await conn.query(
        `SELECT * FROM students WHERE id=?`, [reqRow.requester_student_id || reqRow.student_id]
      );
      const source = sourceRows[0];
      // Make guardian identity + father/mother name + address COMMON on the sibling
      await conn.query(
        `UPDATE students SET
           guardian_name=?, guardian_phone=?, guardian_email=?, address=?,
           father_name=?, mother_name=?, guardian_id=?
         WHERE id=?`,
        [source.guardian_name, source.guardian_phone, source.guardian_email, source.address,
         source.father_name, source.mother_name, reqRow.guardian_id, reqRow.student_id]
      );
      await conn.query(
        `UPDATE guardian_links SET status='approved', decided_by=?, decided_at=NOW(), remark=NULL WHERE id=?`,
        [req.user.id, req.params.id]
      );
      // Notify the sibling's guardian their child is now linked
      const [student] = await conn.query('SELECT id, name FROM students WHERE id=?', [reqRow.student_id]);
      await conn.query(
        `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, created_by)
         VALUES (?,?,?,?,?,?,?)`,
        [reqRow.student_id, 'Sibling link approved',
         student[0].name + ' has been linked to your guardian account.',
         'notice', 'students', reqRow.id, req.user.id]
      );
      await conn.commit();
      const tokens = await getGuardianTokens([reqRow.student_id]);
      await queuePush(tokens,
        'Sibling link approved',
        student[0] ? student[0].name + ' is now visible in the Guardian app' : 'Sibling link approved',
        { type: 'notice', student_id: String(reqRow.student_id) }
      );
      await log(req.user.id, 'sibling_approve', 'Approved sibling link #' + req.params.id);
      res.json({ ok: true });
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/sibling-requests/:id/reject', async (req, res) => {
  const remark = (req.body || {}).remark || 'Request rejected';
  try {
    const [[reqRow]] = await pool.query('SELECT * FROM guardian_links WHERE id=?', [req.params.id]);
    if (!reqRow) return res.status(404).json({ error: 'Request not found' });
    if (reqRow.status !== 'pending') return res.status(400).json({ error: 'Request already ' + reqRow.status });
    // The sibling keeps their own guardian identity; nothing is shared.
    await pool.query(
      `UPDATE guardian_links SET status='rejected', decided_by=?, decided_at=NOW(), remark=? WHERE id=?`,
      [req.user.id, remark, req.params.id]
    );
    await log(req.user.id, 'sibling_reject', 'Rejected sibling link #' + req.params.id + ': ' + remark);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/students', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT s.*, c.name AS class_name, c.section
       FROM students s JOIN classes c ON s.class_id = c.id ORDER BY s.class_id, s.roll`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/students', async (req, res) => {
  const { name, dob, roll, class_id, religion, guardian_id, guardian_name, guardian_phone, guardian_email, address, father_name, mother_name, birth_cert_no, gender, blood_group, optional_subject, phone, email, receives_scholarship } = req.body || {};
  let { student_code } = req.body || {};
  if (!name || !roll || !class_id) {
    return res.status(400).json({ error: 'name, roll, class_id required' });
  }
  const vErrs = validateStudent({ name, roll, dob, guardian_phone });
  if (vErrs.length) return res.status(400).json({ error: vErrs.join('; ') });
  try {
    if (!student_code || !String(student_code).trim()) {
      student_code = await genStudentCode();
    }
    const [result] = await pool.query(
      `INSERT INTO students (student_code, name, dob, roll, class_id, religion, guardian_id, guardian_name, guardian_phone, guardian_email, address, father_name, mother_name, birth_cert_no, gender, blood_group, optional_subject, phone, email, receives_scholarship)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [String(student_code).trim(), name, dob || null, roll, class_id, religion || null, guardian_id || null, guardian_name || null, guardian_phone || null, guardian_email || null, address || null, father_name || null, mother_name || null, birth_cert_no || null, gender || null, blood_group || null, optional_subject || null, phone || null, email || null, receives_scholarship ? 1 : 0]
    );
    await autoAssignReligionSubjects(result.insertId, class_id, religion, req.user.id);
    await log(req.user.id, 'student_add', 'Added student ' + name + ' (' + student_code + (religion ? ', ' + religion : '') + ')');
    res.status(201).json({ id: result.insertId, student_code: String(student_code).trim() });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.code === 'ER_DUP_ENTRY' ? 'Duplicate code or roll in class' : 'Server error' });
  }
});

router.put('/students/:id', async (req, res) => {
  const { student_code, name, dob, roll, class_id, religion, guardian_id, guardian_name, guardian_phone, guardian_email, address, father_name, mother_name, birth_cert_no, gender, blood_group, optional_subject, phone, email, status, receives_scholarship } = req.body || {};
  try {
    const [[cur]] = await pool.query('SELECT student_code, class_id FROM students WHERE id=?', [req.params.id]);
    if (!cur) return res.status(404).json({ error: 'Student not found' });
    const code = student_code !== undefined && student_code !== '' ? String(student_code).trim() : cur.student_code;
    const st = status === undefined || status === null || status === '' ? undefined : String(status).trim().toLowerCase();
    if (st !== undefined && st !== 'active' && st !== 'inactive') {
      return res.status(400).json({ error: "status must be 'active' or 'inactive'" });
    }
    await pool.query(
      `UPDATE students SET student_code=?, name=?, dob=?, roll=?, class_id=?, religion=?, guardian_id=?, guardian_name=?, guardian_phone=?, guardian_email=?, address=?, father_name=?, mother_name=?, birth_cert_no=?, gender=?, blood_group=?, optional_subject=?, phone=?, email=?, receives_scholarship=?${st !== undefined ? ', status=?' : ''} WHERE id=?`,
      st !== undefined
        ? [code, name, dob || null, roll, class_id, religion || null, guardian_id || null, guardian_name || null, guardian_phone || null, guardian_email || null, address || null, father_name || null, mother_name || null, birth_cert_no || null, gender || null, blood_group || null, optional_subject || null, phone || null, email || null, receives_scholarship ? 1 : 0, st, req.params.id]
        : [code, name, dob || null, roll, class_id, religion || null, guardian_id || null, guardian_name || null, guardian_phone || null, guardian_email || null, address || null, father_name || null, mother_name || null, birth_cert_no || null, gender || null, blood_group || null, optional_subject || null, phone || null, email || null, receives_scholarship ? 1 : 0, req.params.id]
    );
    await autoAssignReligionSubjects(req.params.id, class_id, religion, req.user.id);
    await log(req.user.id, 'student_update', 'Updated student id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/students/:id', async (req, res) => {
  const reason = String((req.body && req.body.reason) || '').trim();
  if (!reason) return res.status(400).json({ error: 'শিক্ষার্থী delete করার কারণ লিখতে হবে।' });
  let conn;
  try {
    conn = await pool.getConnection();
    await conn.beginTransaction();
    const [[student]] = await conn.query(
      `SELECT s.*, c.name AS class_name, c.section AS class_section, c.group_name
       FROM students s LEFT JOIN classes c ON c.id=s.class_id WHERE s.id=? FOR UPDATE`,
      [req.params.id]
    );
    if (!student) {
      await conn.rollback();
      return res.status(404).json({ error: 'Student not found' });
    }
    const [attendanceHistory] = await conn.query(
      'SELECT * FROM attendance WHERE student_id=? ORDER BY date, session', [req.params.id]);
    const [markHistory] = await conn.query(
      `SELECT m.*, e.name AS exam_name, e.event_id, sub.name AS subject_name
       FROM marks m LEFT JOIN exams e ON e.id=m.exam_id
       LEFT JOIN subjects sub ON sub.id=e.subject_id
       WHERE m.student_id=? ORDER BY m.id`, [req.params.id]);
    const [dailyReports] = await conn.query(
      'SELECT * FROM student_daily_reports WHERE student_id=? ORDER BY report_date, id', [req.params.id]);
    const [promotions] = await conn.query(
      'SELECT * FROM promotions WHERE student_id=? ORDER BY created_at, id', [req.params.id]);
    const [studentNotifications] = await conn.query(
      'SELECT * FROM notifications WHERE student_id=? ORDER BY id', [req.params.id]);
    const [[admin]] = await conn.query('SELECT name FROM users WHERE id=?', [req.user.id]);
    const audit = {
      student,
      attendance: attendanceHistory,
      marks: markHistory,
      daily_reports: dailyReports,
      promotions,
      notifications: studentNotifications,
      reason,
      deleted_by: { id: req.user.id, name: admin?.name || req.user.name || null },
      deleted_at: new Date().toISOString(),
    };
    await conn.query(
      'INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'student_delete', JSON.stringify(audit)]
    );
    await conn.query('DELETE FROM students WHERE id=?', [req.params.id]);
    await conn.commit();
    res.json({ ok: true });
  } catch (err) {
    if (conn) { try { await conn.rollback(); } catch (_) {} }
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  } finally { if (conn) conn.release(); }
});

// ---- Student subject allocation (NCTB) ----
router.get('/students/:id/subjects', async (req, res) => {
  try {
    const [stu] = await pool.query(
      'SELECT s.id, s.name, s.class_id, c.name AS class_name, c.group_name, c.section FROM students s JOIN classes c ON s.class_id=c.id WHERE s.id=?',
      [req.params.id]
    );
    if (!stu[0]) return res.status(404).json({ error: 'Student not found' });
    const student = stu[0];
    const assigned = await pool.query(
      `SELECT ss.id, ss.is_mandatory, ss.is_fourth_subject, ss.is_elective,
              sub.id AS subject_id, sub.name, sub.group_name, sub.is_optional, sub.is_fourth_subject AS pool_fourth,
              sub.is_elective AS pool_elective
       FROM student_subjects ss JOIN subjects sub ON ss.subject_id = sub.id
       WHERE ss.student_id = ? ORDER BY sub.name`,
      [student.id]
    );
    const avail = await pool.query(
      `SELECT sub.id AS subject_id, sub.name, sub.group_name, sub.is_fourth_subject, sub.is_elective, sub.excluded_from_gpa
       FROM subjects sub WHERE sub.class_id = ? AND sub.id NOT IN (SELECT subject_id FROM student_subjects WHERE student_id = ?)
       ORDER BY (sub.sort_order IS NULL), sub.sort_order, sub.name`,
      [student.class_id, student.id]
    );
    res.json({ student, assigned: assigned[0], available: avail[0] });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Adjust a student's subject allocation: attach/detach optional (4th / elective) subjects.
// Body: { subject_id }  attach, or { subject_id, remove: true } to detach, or { subject_id, is_fourth_subject: true, is_elective: false }
router.put('/students/:id/subjects', async (req, res) => {
  const { subject_id, remove, is_fourth_subject, is_elective } = req.body || {};
  if (!subject_id) return res.status(400).json({ error: 'subject_id required' });
  const sid = Number(req.params.id);
  const subjId = Number(subject_id);
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [sub] = await conn.query('SELECT id, class_id, is_fourth_subject, is_elective FROM subjects WHERE id=?', [subjId]);
    if (!sub[0]) { await conn.rollback(); return res.status(404).json({ error: 'Subject not found' }); }
    if (remove) {
      await conn.query('DELETE FROM student_subjects WHERE student_id=? AND subject_id=? AND is_mandatory=0', [sid, subjId]);
    } else {
      const [existing] = await conn.query('SELECT id FROM student_subjects WHERE student_id=? AND subject_id=?', [sid, subjId]);
      if (existing[0]) {
        await conn.query('UPDATE student_subjects SET is_mandatory=0, is_fourth_subject=?, is_elective=?, assigned_by=? WHERE id=?',
          [is_fourth_subject ? 1 : 0, is_elective ? 1 : 0, req.user.id, existing[0].id]);
      } else {
        await conn.query('INSERT INTO student_subjects (student_id, subject_id, is_mandatory, is_fourth_subject, is_elective, assigned_by) VALUES (?,?,0,?,?,?)',
          [sid, subjId, is_fourth_subject ? 1 : 0, is_elective ? 1 : 0, req.user.id]);
      }
    }
    await conn.commit();
    await log(req.user.id, 'student_subject', `Updated subjects for student id ${sid}`);
    res.json({ ok: true });
  } catch (err) { await conn.rollback(); console.error(err); res.status(500).json({ error: 'Server error' }); }
  finally { conn.release(); }
});

// Subjects a student can/must take, referenced by other apps (guardian marksheet, routine filter)
router.get('/students/:id/subject-list', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT sub.id, sub.name, ss.is_mandatory, ss.is_fourth_subject, ss.is_elective
       FROM student_subjects ss JOIN subjects sub ON ss.subject_id=sub.id
       WHERE ss.student_id=? ORDER BY (sub.sort_order IS NULL), sub.sort_order, sub.name`,
      [req.params.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

async function refreshClassTeacher(teacherId) {
  try {
    const [cls] = await pool.query(
      `SELECT c.id AS class_id, c.name AS class_name, c.section, c.group_name
       FROM classes c WHERE c.teacher_id = ? ORDER BY c.name, c.section`,
      [teacherId]
    );
    const payload = cls.map(c => ({
      class: c.class_name,
      section: c.group_name || c.section,
      group: c.group_name,
      class_id: c.class_id
    }));
    await pool.query('UPDATE users SET is_class_teacher = ?::jsonb WHERE id = ?',
      [JSON.stringify(payload), teacherId]);
  } catch (err) { console.error(err); }
}

router.get('/teachers', async (req, res) => {
  try {
    const [rows] = await pool.query(
      "SELECT id, username, name, email, phone, active, is_class_teacher, designation, sort_order, signature, signature_name FROM users WHERE role='teacher' ORDER BY sort_order ASC, name"
    );
    for (const t of rows) {
      const [cls] = await pool.query(
        'SELECT id FROM classes WHERE teacher_id = ?', [t.id]
      );
      t.class_teacher_ids = cls.map(c => c.id);
      t.class_teacher = typeof t.is_class_teacher === 'string'
        ? JSON.parse(t.is_class_teacher || '[]')
        : (t.is_class_teacher || []);
      t.signature_url = t.signature || null;
    }
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/class-signatories', async (req, res) => {
  const classId = Number(req.query.class_id);
  if (!classId) return res.status(400).json({ error: 'class_id required' });
  try { res.json(await getClassSignatories(classId)); }
  catch (err) { console.error(err); res.status(500).json({ error: 'Signatories could not be loaded' }); }
});

router.put('/teachers/:id/active', async (req, res) => {
  const { active } = req.body || {};
  if (active === undefined) return res.status(400).json({ error: 'active (true/false) required' });
  try {
    await pool.query("UPDATE users SET active=? WHERE id=? AND role='teacher'", [active ? 1 : 0, req.params.id]);
    if (!active) {
      await pool.query('UPDATE device_tokens SET active=0 WHERE user_id=?', [req.params.id]);
    }
    await log(req.user.id, 'teacher_status', `Teacher ${req.params.id} ${active ? 'activated' : 'deactivated'}`);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/teachers', async (req, res) => {
  const { name, username, password, email, phone, class_teacher, designation, sort_order } = req.body || {};
  if (!name || !username || !password) return res.status(400).json({ error: 'name, username, password required' });
  try {
    const hash = await bcrypt.hash(password, 10);
    const [result] = await pool.query(
      "INSERT INTO users (role, username, password_hash, name, email, phone, designation, sort_order) VALUES ('teacher',?,?,?,?,?,?,?)",
      [username, hash, name, email || null, phone || null, designation || '', sort_order != null ? Number(sort_order) : 99]
    );
    const tid = result.insertId;
    if (Array.isArray(class_teacher) && class_teacher.length) {
      // assign this teacher as class teacher, removing any previous assignee
      const ids = class_teacher.map(Number);
      await pool.query('UPDATE classes SET teacher_id=? WHERE id IN (?) AND teacher_id IS NULL',
        [tid, ids]);
      await refreshClassTeacher(tid);
    }
    await log(req.user.id, 'teacher_add', 'Added teacher ' + name);
    res.status(201).json({ id: tid });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.code === 'ER_DUP_ENTRY' ? 'Username already exists' : 'Server error' });
  }
});

router.put('/teachers/:id', async (req, res) => {
  const { name, username, password, email, phone, class_teacher, designation, sort_order } = req.body || {};
  try {
    // Admin removing an exclusive post (Head/Assistant Head) frees the slot
    // for someone else — empty designation = slot released.
    if (designation !== undefined) {
      const norm = String(designation).trim().toLowerCase().replace(/\s+/g, ' ');
      const exclusive = ['head teacher', 'headmaster', 'principal', 'assistant head teacher', 'assistant headmaster', 'vice principal'];
      if (norm && exclusive.indexOf(norm) !== -1) {
        const headFam = ['head teacher', 'headmaster', 'principal'];
        const wantHead = headFam.indexOf(norm) !== -1;
        const [holders] = await pool.query(
          "SELECT id, name, designation FROM users WHERE role='teacher' AND id<>? AND LOWER(TRIM(designation)) IN ('head teacher','headmaster','principal','assistant head teacher','assistant headmaster','vice principal')",
          [req.params.id]);
        const clash = holders.find(h => {
          const hn = String(h.designation || '').toLowerCase().trim();
          return wantHead ? headFam.indexOf(hn) !== -1 : headFam.indexOf(hn) === -1;
        });
        if (clash) {
          return res.status(409).json({ error: `“${String(designation).trim()}” পদটি এখন ${clash.name}-এর দখলে — আগে ওই teacher-এর designation খালি করে slot free করুন।` });
        }
      }
    }
    if (password) {
      const hash = await bcrypt.hash(password, 10);
      await pool.query("UPDATE users SET name=?, username=?, password_hash=?, email=?, phone=?, designation=?, sort_order=? WHERE id=? AND role='teacher'",
        [name, username, hash, email || null, phone || null, designation || '', sort_order != null ? Number(sort_order) : 99, req.params.id]);
    } else {
      await pool.query("UPDATE users SET name=?, username=?, email=?, phone=?, designation=?, sort_order=? WHERE id=? AND role='teacher'",
        [name, username, email || null, phone || null, designation || '', sort_order != null ? Number(sort_order) : 99, req.params.id]);
    }
    if (Array.isArray(class_teacher)) {
      const tid = Number(req.params.id);
      const ids = class_teacher.map(Number);
      // unassign classes this teacher no longer has
      await pool.query('UPDATE classes SET teacher_id=NULL WHERE teacher_id=? AND id NOT IN (?)',
        [tid, ids.length ? ids : [-1]]);
      // assign new ones (replace previous assignee), skip self
      if (ids.length) {
        await pool.query('UPDATE classes SET teacher_id=? WHERE id IN (?) AND (teacher_id IS NULL OR teacher_id<>?)',
          [tid, ids, tid]);
      }
      await refreshClassTeacher(tid);
    }
    await log(req.user.id, 'teacher_update', 'Updated teacher id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/teachers/:id', async (req, res) => {
  try {
    await pool.query('UPDATE classes SET teacher_id=NULL WHERE teacher_id=?', [req.params.id]);
    await pool.query('UPDATE subjects SET teacher_id=NULL WHERE teacher_id=?', [req.params.id]);
    await pool.query('UPDATE exams SET created_by=1 WHERE created_by=? AND id IN (SELECT DISTINCT x.id FROM exams x JOIN subjects sub ON sub.id=x.subject_id WHERE sub.teacher_id IS NULL) AND created_by<>1', [req.params.id]);
    await pool.query("DELETE FROM users WHERE id=? AND role='teacher'", [req.params.id]);
    await log(req.user.id, 'teacher_delete', 'Deleted teacher id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/guardians', async (req, res) => {
  try {
    const [rows] = await pool.query(
      "SELECT id, username, name, email, phone FROM users WHERE role='guardian' ORDER BY name"
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/classes', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT c.*, u.name AS teacher_name,
        (SELECT COUNT(*) FROM students s WHERE s.class_id = c.id) AS student_count
       FROM classes c LEFT JOIN users u ON c.teacher_id = u.id ORDER BY c.name, c.section`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/classes', async (req, res) => {
  const { name, section, group_name, teacher_id } = req.body || {};
  if (!name || !section) return res.status(400).json({ error: 'name and section required' });
  try {
    const [result] = await pool.query('INSERT INTO classes (name, section, group_name, teacher_id) VALUES (?,?,?,?)', [name, section, group_name || null, teacher_id || null]);
    await syncCanonicalEventClasses();
    if (teacher_id) await refreshClassTeacher(Number(teacher_id));
    await log(req.user.id, 'class_add', 'Added class ' + name + ' ' + section + (group_name ? ' (' + group_name + ')' : ''));
    res.status(201).json({ id: result.insertId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.code === 'ER_DUP_ENTRY' ? 'Class already exists' : 'Server error' });
  }
});

router.put('/classes/:id', async (req, res) => {
  const { name, section, group_name, teacher_id } = req.body || {};
  try {
    const [prev] = await pool.query('SELECT teacher_id FROM classes WHERE id=?', [req.params.id]);
    const prevTid = prev[0]?.teacher_id;
    await pool.query('UPDATE classes SET name=?, section=?, group_name=?, teacher_id=? WHERE id=?', [name, section, group_name || null, teacher_id || null, req.params.id]);
    await syncCanonicalEventClasses();
    const newTid = Number(teacher_id) || null;
    if (prevTid && prevTid !== newTid) await refreshClassTeacher(prevTid);
    if (newTid) await refreshClassTeacher(newTid);
    await log(req.user.id, 'class_update', 'Updated class id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/classes/:id', async (req, res) => {
  try {
    const [prev] = await pool.query('SELECT teacher_id FROM classes WHERE id=?', [req.params.id]);
    await pool.query('DELETE FROM classes WHERE id=?', [req.params.id]);
    await syncCanonicalEventClasses();
    if (prev[0]?.teacher_id) await refreshClassTeacher(prev[0].teacher_id);
    await log(req.user.id, 'class_delete', 'Deleted class id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// SESSIONS — academic year sessions. Creating a session auto-creates the 4
// canonical exam shells (Half Yearly, Annual, Pre-Test, Test) with the year.
// =====================================================================
router.get('/sessions', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT s.*, (SELECT COUNT(*) FROM exam_events e WHERE e.session_id=s.id) AS event_count
       FROM sessions s ORDER BY s.name DESC`);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/sessions', async (req, res) => {
  const { name, is_active } = req.body || {};
  const sessionName = String(name || '').trim();
  if (!sessionName) return res.status(400).json({ error: 'name required (e.g. 2026)' });
  if (!/^\d{4}$/.test(sessionName)) return res.status(400).json({ error: 'Academic session must be a 4-digit year (e.g. 2027)' });
  let conn;
  try {
    conn = await pool.getConnection();
    await conn.beginTransaction();
    const [inserted] = await conn.query(
      'INSERT INTO sessions (name, is_active) VALUES (?,?) ON CONFLICT (name) DO NOTHING',
      [sessionName, is_active ? 1 : 0]);
    const sid = inserted.insertId || (await conn.query('SELECT id FROM sessions WHERE name=?', [sessionName]))[0][0]?.id;
    if (!sid) throw new Error('Session row could not be resolved after insert');
    if (is_active) await conn.query('UPDATE sessions SET is_active=0 WHERE id<>?', [sid]);
    const ensured = await ensureSessionExams(sid, conn);
    await conn.commit();
    await log(req.user.id, 'session_create', `Session ${sessionName} ensured (${ensured.created.length} created, ${ensured.adopted.length} adopted)`);
    res.status(201).json({ id: sid, ensured });
  } catch (err) {
    if (conn) { try { await conn.rollback(); } catch (_) {} }
    const requestId = `session-${Date.now().toString(36)}`;
    console.error(`[${requestId}] session creation failed`, { code: err.code, constraint: err.constraint, message: err.message, stack: err.stack });
    if (err.code === '42703' || err.code === '42P01') {
      return res.status(503).json({ error: 'Database schema update required. Apply backend/migrations/20261022_exam_session_columns.sql in Supabase, then retry.', code: 'SCHEMA_MIGRATION_REQUIRED', request_id: requestId });
    }
    if (err.code === '23505') return res.status(409).json({ error: 'This academic session already exists.', code: 'SESSION_ALREADY_EXISTS' });
    res.status(500).json({ error: 'Academic session could not be created. Please retry or share this reference with support.', request_id: requestId });
  } finally { conn?.release(); }
});

router.put('/sessions/:id/active', async (req, res) => {
  const { is_active } = req.body || {};
  if (is_active === undefined) return res.status(400).json({ error: 'is_active required' });
  try {
    await pool.query('UPDATE sessions SET is_active=? WHERE id=?', [is_active ? 1 : 0, req.params.id]);
    if (is_active) await pool.query('UPDATE sessions SET is_active=0 WHERE id<>?', [req.params.id]);
    await log(req.user.id, 'session_active', `Session ${req.params.id} active=${is_active ? 1 : 0}`);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// CLASS-TEACHER REQUEST WORKFLOW
// Teachers ask to become class teacher of a class they consider theirs;
// the admin approves (sets classes.teacher_id) or rejects from here.
// =====================================================================
router.get('/class-teacher-requests', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT r.*, c.name AS class_name, c.section, c.group_name,
              c.teacher_id AS class_teacher_id,
              ct.name AS current_teacher_name,
              u.name AS teacher_name, u.phone AS teacher_phone, d.name AS decider_name
       FROM class_teacher_requests r
       JOIN classes c ON r.class_id = c.id
       JOIN users u ON r.teacher_id = u.id
       LEFT JOIN users ct ON c.teacher_id = ct.id
       LEFT JOIN users d ON r.decided_by = d.id
       ORDER BY (r.status = 'pending') DESC, r.id DESC LIMIT 200`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/class-teacher-requests/:id/approve', async (req, res) => {
  try {
    const [rq] = await pool.query(
      `SELECT r.*, c.teacher_id AS current_teacher FROM class_teacher_requests r
       JOIN classes c ON r.class_id = c.id WHERE r.id=?`,
      [req.params.id]
    );
    if (!rq[0]) return res.status(404).json({ error: 'Request not found' });
    if (rq[0].status !== 'pending') return res.status(400).json({ error: 'Request already ' + rq[0].status });
    const prev = rq[0].current_teacher;
    await pool.query(
      "UPDATE class_teacher_requests SET status='approved', decided_by=?, decided_at=now() WHERE id=?",
      [req.user.id, req.params.id]
    );
    await pool.query('UPDATE classes SET teacher_id=? WHERE id=?', [rq[0].teacher_id, rq[0].class_id]);
    if (prev && prev !== rq[0].teacher_id) await refreshClassTeacher(prev);
    await refreshClassTeacher(rq[0].teacher_id);
    await log(req.user.id, 'class_teacher_approve', 'Made teacher ' + rq[0].teacher_id + ' class teacher of class ' + rq[0].class_id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/class-teacher-requests/:id/reject', async (req, res) => {
  try {
    const [rq] = await pool.query('SELECT * FROM class_teacher_requests WHERE id=?', [req.params.id]);
    if (!rq[0]) return res.status(404).json({ error: 'Request not found' });
    if (rq[0].status !== 'pending') return res.status(400).json({ error: 'Request already ' + rq[0].status });
    await pool.query(
      "UPDATE class_teacher_requests SET status='rejected', decided_by=?, decided_at=now() WHERE id=?",
      [req.user.id, req.params.id]
    );
    await log(req.user.id, 'class_teacher_reject', 'Rejected class-teacher request id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/subjects', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT sub.*, c.name AS class_name, c.section, u.name AS teacher_name
       FROM subjects sub JOIN classes c ON sub.class_id = c.id
       LEFT JOIN users u ON sub.teacher_id = u.id ORDER BY sub.class_id, sub.id`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/subjects', async (req, res) => {
  const { name, class_id, teacher_id, full_marks, pass_marks, group_name, is_optional, excluded_from_gpa, cq_full, mcq_full, practical_full, written_full, ca_full, subject_code, is_fourth_subject, is_elective, sort_order } = req.body || {};
  if (!name || !class_id) return res.status(400).json({ error: 'name and class_id required' });
  try {
    const [result] = await pool.query(
      `INSERT INTO subjects (name, class_id, teacher_id, full_marks, pass_marks, group_name, is_optional, excluded_from_gpa, cq_full, mcq_full, practical_full, written_full, ca_full, subject_code, is_fourth_subject, is_elective, sort_order)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, ?,?)`,
      [name, class_id, teacher_id || null, full_marks || 100, pass_marks || null, group_name || 'Compulsory',
       is_optional ? 1 : 0, excluded_from_gpa ? 1 : 0, cq_full || null, mcq_full || null, practical_full || null, written_full || null, ca_full || null, subject_code || null,
       is_fourth_subject ? 1 : 0, is_elective ? 1 : 0, sort_order != null ? Number(sort_order) : null]
    );
    await log(req.user.id, 'subject_add', 'Added subject ' + name);
    res.status(201).json({ id: result.insertId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.code === 'ER_DUP_ENTRY' ? 'Subject already exists in class' : 'Server error' });
  }
});

router.put('/subjects/:id', async (req, res) => {
  const { name, class_id, teacher_id, full_marks, pass_marks, group_name, is_optional, excluded_from_gpa, cq_full, mcq_full, practical_full, written_full, ca_full, subject_code, is_fourth_subject, is_elective, sort_order } = req.body || {};
  try {
    await pool.query(
      `UPDATE subjects SET name=?, class_id=?, teacher_id=?, full_marks=?, pass_marks=?, group_name=?, is_optional=?, excluded_from_gpa=?, cq_full=?, mcq_full=?, practical_full=?, written_full=?, ca_full=?, subject_code=?, is_fourth_subject=?, is_elective=?, sort_order=? WHERE id=?`,
      [name, class_id, teacher_id || null, full_marks || 100, pass_marks || null, group_name || 'Compulsory',
       is_optional ? 1 : 0, excluded_from_gpa ? 1 : 0, cq_full || null, mcq_full || null, practical_full || null, written_full || null, ca_full || null, subject_code || null,
       is_fourth_subject ? 1 : 0, is_elective ? 1 : 0, sort_order != null ? Number(sort_order) : null, req.params.id]
    );
    await log(req.user.id, 'subject_update', 'Updated subject id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/subjects/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM subjects WHERE id=?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/exams', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT e.*, c.name AS class_name, c.section, sub.name AS subject_name, u.name AS created_by_name,
              ev.name AS event_name,
              (SELECT COUNT(*) FROM marks m WHERE m.exam_id = e.id) AS marks_count,
              (SELECT COUNT(*) FROM students s WHERE s.class_id = e.class_id) AS student_count
       FROM exams e JOIN classes c ON e.class_id = c.id
       JOIN subjects sub ON e.subject_id = sub.id
       JOIN users u ON e.created_by = u.id
       LEFT JOIN exam_events ev ON e.event_id = ev.id
       ORDER BY e.created_at DESC`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Unified Exam Session Dashboard for Admin
// Returns complete event + class + subject data with progress
router.get('/exam-dashboard', async (req, res) => {
  try {
    await ensureSessionHorizon();
    return getUnifiedExamDashboard(req, res);
  } catch (err) {
    console.error('exam session horizon provisioning failed:', err);
    res.status(500).json({ error: 'Academic session horizon could not be prepared.' });
  }
});

router.post('/exams', async (req, res) => {
  const { name, exam_type, class_id, subject_id, exam_date, entry_deadline, event_id } = req.body || {};
  if (!name || !class_id || !subject_id) return res.status(400).json({ error: 'name, class_id, subject_id required' });
  try {
    const [[subj]] = await pool.query('SELECT id, class_id FROM subjects WHERE id=?', [subject_id]);
    if (!subj) return res.status(404).json({ error: 'Subject not found' });
    if (Number(subj.class_id) !== Number(class_id)) {
      return res.status(400).json({ error: 'subject_id does not belong to the selected class' });
    }
    // Fixed core exams (half_yearly/annual/pretest/test) auto-populate their
    // subjects from teacher mark entries — no manual subject-exam attaching.
    if (event_id) {
      const [[ev]] = await pool.query('SELECT exam_kind FROM exam_events WHERE id=?', [event_id]);
      if (ev && ['half_yearly', 'annual', 'pretest', 'test'].indexOf(ev.exam_kind) !== -1) {
        return res.status(400).json({ error: 'Fixed core exam-এ subject হাতে যোগ করা যায় না — teacher mark entry দিলে auto তৈরি হবে।' });
      }
    }
    const [result] = await pool.query(
      'INSERT INTO exams (name, exam_type, class_id, subject_id, source, created_by, exam_date, entry_deadline, event_id) VALUES (?,?,?,?,?,?,?,?,?)',
      [name, exam_type || 'class_test', class_id, subject_id, 'admin', req.user.id, exam_date || null, entry_deadline || null, event_id || null]
    );
    await log(req.user.id, 'exam_create', 'Created exam ' + name);
    res.status(201).json({ id: result.insertId });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/exams/:id', async (req, res) => {
  const { name, exam_type, class_id, subject_id, exam_date, entry_deadline, event_id } = req.body || {};
  try {
    const [[exam]] = await pool.query('SELECT * FROM exams WHERE id=?', [req.params.id]);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    if (exam.source === 'teacher') {
      return res.status(403).json({ error: 'Cannot edit teacher-created class tests from admin panel' });
    }
    if (subject_id && class_id) {
      const [[subj]] = await pool.query('SELECT id, class_id FROM subjects WHERE id=?', [subject_id]);
      if (!subj) return res.status(404).json({ error: 'Subject not found' });
      if (Number(subj.class_id) !== Number(class_id)) {
        return res.status(400).json({ error: 'subject_id does not belong to the selected class' });
      }
    }
    const updates = [];
    const params = [];
    if (name !== undefined) { updates.push('name=?'); params.push(name); }
    if (exam_type !== undefined) { updates.push('exam_type=?'); params.push(exam_type); }
    if (class_id !== undefined) { updates.push('class_id=?'); params.push(Number(class_id)); }
    if (subject_id !== undefined) { updates.push('subject_id=?'); params.push(Number(subject_id)); }
    if (exam_date !== undefined) { updates.push('exam_date=?'); params.push(exam_date || null); }
    if (entry_deadline !== undefined) { updates.push('entry_deadline=?'); params.push(entry_deadline || null); }
    if (event_id !== undefined) { updates.push('event_id=?'); params.push(event_id ? Number(event_id) : null); }
    if (updates.length === 0) return res.status(400).json({ error: 'Nothing to update' });
    params.push(req.params.id);
    await pool.query(`UPDATE exams SET ${updates.join(', ')} WHERE id=?`, params);
    await log(req.user.id, 'exam_edit', 'Edited exam ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/exams/:id', async (req, res) => {
  // Password-gated delete: exam-সহ সব marks মুছে যাবে — নিজের admin
  // password দিয়ে confirm করতে হবে।
  const { password, confirm_password, reason } = req.body || {};
  const pw = password !== undefined ? password : confirm_password;
  if (!pw) return res.status(400).json({ error: 'Admin password required to delete an exam' });
  if (!String(reason || '').trim()) return res.status(400).json({ error: 'পরীক্ষা delete করার কারণ লিখতে হবে।' });
  try {
    const [[me]] = await pool.query('SELECT id, password_hash FROM users WHERE id=? AND role=?', [req.user.id, 'admin']);
    if (!me) return res.status(403).json({ error: 'Admin account not found' });
    const ok = await bcrypt.compare(String(pw), me.password_hash);
    if (!ok) return res.status(403).json({ error: 'ভুল password — exam delete হয়নি।' });
    const [[exam]] = await pool.query(
      `SELECT e.*, c.name AS class_name, c.section, sub.name AS subject_name,
              ev.name AS event_name, ev.session_id, ev.exam_kind, ev.year
       FROM exams e LEFT JOIN classes c ON c.id=e.class_id
       LEFT JOIN subjects sub ON sub.id=e.subject_id
       LEFT JOIN exam_events ev ON ev.id=e.event_id WHERE e.id=?`, [req.params.id]);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const [markRows] = await conn.query('SELECT * FROM marks WHERE exam_id=? ORDER BY id', [req.params.id]);
      const [shareRows] = await conn.query('SELECT * FROM exam_shares WHERE exam_id=? ORDER BY id', [req.params.id]);
      const [notificationRows] = await conn.query(
        `SELECT * FROM notifications WHERE related_id=? AND type IN ('result','class_test_result') ORDER BY id`, [req.params.id]);
      const [[admin]] = await conn.query('SELECT name FROM users WHERE id=?', [req.user.id]);
      const audit = {
        exam, marks: markRows, shares: shareRows, notifications: notificationRows,
        reason: String(reason).trim(),
        deleted_by: { id: req.user.id, name: admin?.name || req.user.name || null },
        deleted_at: new Date().toISOString(),
      };
      await conn.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
        [req.user.id, 'exam_delete', JSON.stringify(audit)]);
      const [m] = await conn.query('DELETE FROM marks WHERE exam_id=?', [req.params.id]);
      await conn.query('DELETE FROM exam_shares WHERE exam_id=?', [req.params.id]);
      await conn.query(`DELETE FROM notifications WHERE related_id=? AND type IN ('result','class_test_result')`, [req.params.id]);
      await conn.query('DELETE FROM exams WHERE id=?', [req.params.id]);
      await conn.commit();
    } catch (e) {
      try { await conn.rollback(); } catch (_) {}
      throw e;
    } finally { conn.release(); }
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// 1-click marks-entry permission, per exam. entry_open=0 revokes teacher
// entry instantly (teacher POSTs return 403); =1 re-grants it.
router.put('/exams/:id/entry', async (req, res) => {
  const open = req.body && req.body.entry_open !== undefined
    ? Number(!!req.body.entry_open) : null;
  if (open === null || (open !== 0 && open !== 1)) {
    return res.status(400).json({ error: 'entry_open (0/1) required' });
  }
  try {
    const [r] = await pool.query('UPDATE exams SET entry_open=? WHERE id=?', [open, req.params.id]);
    if (!r.affectedRows) return res.status(404).json({ error: 'Exam not found' });
    await log(req.user.id, 'exam_entry_' + (open ? 'open' : 'revoke'), `Exam ${req.params.id} entry ${open ? 'opened' : 'revoked'}`);
    res.json({ ok: true, entry_open: open });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// 1-click marks-entry permission for a whole event (all its subject exams).
router.post('/events/:id/entry', async (req, res) => {
  const open = req.body && req.body.entry_open !== undefined
    ? Number(!!req.body.entry_open) : null;
  if (open === null || (open !== 0 && open !== 1)) {
    return res.status(400).json({ error: 'entry_open (0/1) required' });
  }
  try {
    const [[ev]] = await pool.query('SELECT id FROM exam_events WHERE id=?', [req.params.id]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    const [r] = await pool.query('UPDATE exams SET entry_open=? WHERE event_id=?', [open, req.params.id]);
    await log(req.user.id, 'event_entry_' + (open ? 'open' : 'revoke'), `Event ${req.params.id} entry ${open ? 'opened' : 'revoked'} (${r.affectedRows} exams)`);
    res.json({ ok: true, entry_open: open, exams: r.affectedRows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/exams/:id/marks', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT m.*, s.name AS student_name, s.roll,
        (m.edit_until IS NOT NULL AND m.edit_until > NOW()) AS editable
       FROM marks m JOIN students s ON m.student_id = s.id
       WHERE m.exam_id = ? ORDER BY s.roll`,
      [req.params.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/marks/:id', async (req, res) => {
  const { marks, total, cq, mcq, practical, written, ca, comment } = req.body || {};
  try {
    // Preserve the existing total + components when not explicitly provided.
    const [[mark]] = await pool.query(
      'SELECT m.*, e.subject_id FROM marks m JOIN exams e ON e.id=m.exam_id WHERE m.id=?',
      [req.params.id]);
    if (!mark) return res.status(404).json({ error: 'Mark not found' });
    const effectiveTotal = total !== undefined ? total : mark.total;
    const [[subj]] = await pool.query(
      'SELECT full_marks, cq_full, mcq_full, practical_full, written_full, ca_full FROM subjects WHERE id=?',
      [mark.subject_id]);
    const layout = subj ? {
      full_marks: Number(subj.full_marks) || 100,
      cq_full: subj.cq_full, mcq_full: subj.mcq_full, practical_full: subj.practical_full,
      written_full: subj.written_full, ca_full: subj.ca_full,
    } : { full_marks: 100 };
    const next = {
      student_id: mark.student_id,
      marks: marks !== undefined ? marks : mark.marks,
      total: effectiveTotal,
      cq: cq !== undefined ? cq : mark.cq,
      mcq: mcq !== undefined ? mcq : mark.mcq,
      practical: practical !== undefined ? practical : mark.practical,
      written: written !== undefined ? written : mark.written,
      ca: ca !== undefined ? ca : mark.ca,
      comment: comment !== undefined ? comment : mark.comment,
    };
    const { validateMarksRecord } = require('../validate');
    const recErrs = validateMarksRecord(next, layout);
    if (recErrs.length) return res.status(400).json({ error: recErrs[0] });
    await pool.query(
      `UPDATE marks SET marks=?, total=?, cq=?, mcq=?, practical=?, written=?, ca=?, comment=?, edit_until=NULL WHERE id=?`,
      [Number(next.marks), effectiveTotal,
       next.cq === '' ? null : next.cq, next.mcq === '' ? null : next.mcq,
       next.practical === '' ? null : next.practical, next.written === '' ? null : next.written,
       next.ca === '' ? null : next.ca, next.comment || null, req.params.id]);
    await log(req.user.id, 'mark_edit', 'Admin edited mark id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/marks/:id/unlock', async (req, res) => {
  try {
    await pool.query('UPDATE marks SET edit_until = DATE_ADD(NOW(), INTERVAL 5 HOUR) WHERE id=?', [req.params.id]);
    await log(req.user.id, 'mark_unlock', 'Unlocked mark id ' + req.params.id + ' for 5 hours');
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// DESIGNATION SLOTS — exclusive posts (Head Teacher / Assistant Head Teacher):
// only ONE holder at a time. Admin sees holders here, removes a holder
// (clear their designation), which frees the post for someone else.
// =====================================================================
router.put('/leadership-assignments', async (req, res) => {
  const body = req.body || {};
  const headId = body.headmaster_id == null || body.headmaster_id === '' ? null : Number(body.headmaster_id);
  const assistantId = body.assistant_headmaster_id == null || body.assistant_headmaster_id === '' ? null : Number(body.assistant_headmaster_id);
  const seniorIds = Array.isArray(body.senior_teacher_ids) ? body.senior_teacher_ids.map(Number) : [];
  const assistantTeacherIds = Array.isArray(body.assistant_teacher_ids) ? body.assistant_teacher_ids.map(Number) : [];
  const all = [headId, assistantId, ...seniorIds, ...assistantTeacherIds].filter(Boolean);
  if (all.some(id => !Number.isInteger(id) || id < 1) || new Set(all).size !== all.length) {
    return res.status(400).json({ error: 'একজন শিক্ষককে একাধিক পদে নির্বাচন করা যাবে না।' });
  }
  let conn;
  try {
    if (all.length) {
      const marks = all.map(() => '?').join(',');
      const [found] = await pool.query(`SELECT id FROM users WHERE role='teacher' AND active=1 AND id ${all.length === 1 ? '= ?' : `IN (${marks})`}`, all);
      if (found.length !== all.length) return res.status(400).json({ error: 'নির্বাচিত শিক্ষক সক্রিয় নন বা পাওয়া যায়নি।' });
    }
    conn = await pool.getConnection();
    await conn.beginTransaction();
    await conn.query(`UPDATE users SET designation='' WHERE role='teacher'
      AND LOWER(TRIM(designation)) IN ('headmaster','head teacher','principal','assistant headmaster','assistant head teacher','vice principal','senior teacher','assistant teacher')`);
    const assignments = [
      ...(headId ? [[headId, 'Headmaster']] : []),
      ...(assistantId ? [[assistantId, 'Assistant Headmaster']] : []),
      ...seniorIds.map(id => [id, 'Senior Teacher']),
      ...assistantTeacherIds.map(id => [id, 'Assistant Teacher']),
    ];
    for (const [id, title] of assignments) await conn.query("UPDATE users SET designation=? WHERE id=? AND role='teacher'", [title, id]);
    await conn.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'leadership_assignments', JSON.stringify({ headId, assistantId, seniorIds, assistantTeacherIds })]);
    await conn.commit();
    res.json({ ok: true });
  } catch (err) {
    if (conn) { try { await conn.rollback(); } catch (_) {} }
    console.error(err); res.status(500).json({ error: 'পদবি সংরক্ষণ করা যায়নি।' });
  } finally { if (conn) conn.release(); }
});

router.get('/designation-slots', async (req, res) => {
  try {
    const headFam = ['head teacher', 'headmaster', 'principal'];
    const asstFam = ['assistant head teacher', 'assistant headmaster', 'vice principal'];
    const [rows] = await pool.query(
      `SELECT id, name, username, designation FROM users WHERE role='teacher'
        AND LOWER(TRIM(designation)) IN ('head teacher','headmaster','principal','assistant head teacher','assistant headmaster','vice principal')`);
    const head = rows.find(r => headFam.indexOf(String(r.designation || '').toLowerCase().trim()) !== -1) || null;
    const asst = rows.find(r => asstFam.indexOf(String(r.designation || '').toLowerCase().trim()) !== -1) || null;
    res.json({
      head_teacher: head ? { id: head.id, name: head.name, username: head.username, designation: head.designation } : null,
      assistant_head: asst ? { id: asst.id, name: asst.name, username: asst.username, designation: asst.designation } : null,
    });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Release an exclusive post: clears the holder's designation.
router.post('/designation-slots/release', async (req, res) => {
  const { user_id } = req.body || {};
  if (!user_id) return res.status(400).json({ error: 'user_id required' });
  try {
    const [[u]] = await pool.query("SELECT id, name, designation FROM users WHERE id=? AND role='teacher'", [user_id]);
    if (!u) return res.status(404).json({ error: 'Teacher not found' });
    await pool.query("UPDATE users SET designation='' WHERE id=?", [user_id]);
    await log(req.user.id, 'designation_release', `Released “${u.designation}” from ${u.name} (id ${user_id})`);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// RE-EXAM REQUESTS — guardian আবেদন করে, admin approve/reject করে।
// Approve → ওই student-এর সংশ্লিষ্ট exam-গুলোর marks আবার editable হয়
// (edit_until = +5h) → admin number ঠিক করে → event republish → guardian
// নতুন result দেখে। Student-এর পুরনো result history অক্ষত থাকে।
// =====================================================================
router.get('/reexam-requests', async (req, res) => {
  const status = req.query.status || 'pending';
  try {
    const [rows] = await pool.query(
      `SELECT r.*, s.name AS student_name, s.roll, s.student_code,
              c.name AS class_name, c.section, c.group_name,
              e.name AS event_name, g.name AS guardian_name,
              (SELECT COUNT(*) FROM marks m JOIN exams x ON x.id=m.exam_id
                WHERE x.event_id=r.event_id AND m.student_id=r.student_id) AS marks_count
       FROM reexam_requests r
       JOIN students s ON s.id=r.student_id
       JOIN classes c ON c.id=r.class_id
       JOIN exam_events e ON e.id=r.event_id
       LEFT JOIN users g ON g.id=r.guardian_id
       WHERE r.status=? ORDER BY r.id DESC LIMIT 200`,
      [status]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/reexam-requests/:id/approve', async (req, res) => {
  try {
    const [[r]] = await pool.query('SELECT * FROM reexam_requests WHERE id=?', [req.params.id]);
    if (!r) return res.status(404).json({ error: 'Request not found' });
    if (r.status !== 'pending') return res.status(400).json({ error: 'Request already ' + r.status });
    // ওই student + event-এর সব mark আবার ৫ ঘণ্টার জন্য editable।
    const [u] = await pool.query(
      `UPDATE marks m JOIN exams x ON x.id=m.exam_id
        SET m.edit_until = DATE_ADD(NOW(), INTERVAL 5 HOUR)
       WHERE x.event_id=? AND m.student_id=?`, [r.event_id, r.student_id]);
    await pool.query(
      `UPDATE reexam_requests SET status='approved', decided_by=?, decided_at=NOW() WHERE id=?`,
      [req.user.id, req.params.id]);
    await pool.query(
      `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, created_by)
       VALUES (?,?,?,?,?,?,?)`,
      [r.student_id, 'Re-Exam আবেদন গৃহীত',
       'আপনার re-exam আবেদন approve হয়েছে — শীঘ্রই সংশোধিত result publish হবে।',
       'general', 'students', r.event_id, req.user.id]);
    await log(req.user.id, 'reexam_approve', `Approved re-exam request ${req.params.id} (student ${r.student_id}, event ${r.event_id}, ${u.affectedRows || 0} marks unlocked)`);
    res.json({ ok: true, unlocked: u.affectedRows || 0 });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/reexam-requests/:id/reject', async (req, res) => {
  const { note } = req.body || {};
  try {
    const [[r]] = await pool.query('SELECT * FROM reexam_requests WHERE id=?', [req.params.id]);
    if (!r) return res.status(404).json({ error: 'Request not found' });
    if (r.status !== 'pending') return res.status(400).json({ error: 'Request already ' + r.status });
    await pool.query(
      `UPDATE reexam_requests SET status='rejected', decided_by=?, decided_at=NOW(), admin_note=? WHERE id=?`,
      [req.user.id, (note || '').slice(0, 500) || null, req.params.id]);
    await pool.query(
      `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, created_by)
       VALUES (?,?,?,?,?,?,?)`,
      [r.student_id, 'Re-Exam আবেদন',
       'আপনার re-exam আবেদনটি বিবেচনা করা যায়নি।' + ((note || '').trim() ? ' কারণ: ' + String(note).slice(0, 300) : ''),
       'general', 'students', r.event_id, req.user.id]);
    await log(req.user.id, 'reexam_reject', `Rejected re-exam request ${req.params.id}`);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});
// admin অনুমতিতে। Teacher request পাঠায়, admin এখানে approve/reject করে।
// Approve → ওই mark-এ নতুন করে ৫ ঘণ্টার edit window খুলে যায়।
// =====================================================================
router.get('/mark-edit-requests', async (req, res) => {
  const status = req.query.status || 'pending';
  try {
    const [rows] = await pool.query(
      `SELECT r.*, s.name AS student_name, s.roll, e.name AS exam_name,
              sub.name AS subject_name, c.name AS class_name, c.section,
              u.name AS teacher_name,
              (m.edit_until IS NOT NULL AND m.edit_until > NOW()) AS currently_editable
       FROM mark_edit_requests r
       JOIN marks m ON m.id = r.mark_id
       JOIN students s ON s.id = r.student_id
       JOIN exams e ON e.id = r.exam_id
       JOIN subjects sub ON sub.id = e.subject_id
       JOIN classes c ON c.id = e.class_id
       JOIN users u ON u.id = r.teacher_id
       WHERE r.status = ?
       ORDER BY r.id DESC LIMIT 200`,
      [status]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/mark-edit-requests/:id/approve', async (req, res) => {
  try {
    const [[r]] = await pool.query(`SELECT * FROM mark_edit_requests WHERE id=?`, [req.params.id]);
    if (!r) return res.status(404).json({ error: 'Request not found' });
    if (r.status !== 'pending') return res.status(400).json({ error: 'Request already ' + r.status });
    await pool.query('UPDATE marks SET edit_until = DATE_ADD(NOW(), INTERVAL 5 HOUR) WHERE id=?', [r.mark_id]);
    await pool.query(`UPDATE mark_edit_requests SET status='approved', decided_at=NOW(), decided_by=? WHERE id=?`,
      [req.user.id, req.params.id]);
    await log(req.user.id, 'mark_edit_approve', `Approved edit request ${req.params.id} (mark ${r.mark_id}, +5h window)`);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/mark-edit-requests/:id/reject', async (req, res) => {
  try {
    const [[r]] = await pool.query(`SELECT * FROM mark_edit_requests WHERE id=?`, [req.params.id]);
    if (!r) return res.status(404).json({ error: 'Request not found' });
    if (r.status !== 'pending') return res.status(400).json({ error: 'Request already ' + r.status });
    await pool.query(`UPDATE mark_edit_requests SET status='rejected', decided_at=NOW(), decided_by=? WHERE id=?`,
      [req.user.id, req.params.id]);
    await log(req.user.id, 'mark_edit_reject', `Rejected edit request ${req.params.id}`);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Per-exam coverage: কতজন student-এর number entry হয়েছে / কত বাকি।
router.get('/exams/:id/coverage', async (req, res) => {
  try {
    const [[exam]] = await pool.query(
      `SELECT e.*, c.name AS class_name, c.section, sub.name AS subject_name
       FROM exams e JOIN classes c ON c.id=e.class_id JOIN subjects sub ON sub.id=e.subject_id WHERE e.id=?`,
      [req.params.id]);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    const [rows] = await pool.query(
      `SELECT s.id AS student_id, s.name, s.roll,
              m.id AS mark_id, m.marks, m.total,
              (m.edit_until IS NOT NULL AND m.edit_until > NOW()) AS editable
       FROM students s LEFT JOIN marks m ON m.student_id=s.id AND m.exam_id=?
       WHERE s.class_id=? ORDER BY s.roll`,
      [req.params.id, exam.class_id]);
    const entered = rows.filter(r => r.mark_id != null);
    res.json({
      exam,
      student_count: rows.length,
      entered_count: entered.length,
      pending_count: rows.length - entered.length,
      entered, pending: rows.filter(r => r.mark_id == null)
    });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/attendance/monthly', async (req, res) => {
  const m = String((req.query && req.query.month) || new Date().toISOString().slice(0, 7));
  try {
    const [rows] = await pool.query(
      `SELECT c.id AS class_id, c.name, c.section,
              COUNT(DISTINCT s.id) AS student_count,
              COALESCE(SUM(CASE WHEN a.is_escape THEN 1 ELSE 0 END),0) AS escape_days,
              COALESCE(SUM(CASE WHEN a.status <> 'present' THEN 1 ELSE 0 END),0) AS absent_days
       FROM students s JOIN classes c ON s.class_id=c.id
       LEFT JOIN attendance a ON a.student_id=s.id AND a.date BETWEEN ? AND ?
       GROUP BY c.id, c.name, c.section ORDER BY c.name, c.section`,
      [m + '-01', m + '-31']
    );
    res.json({ month: m, rows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/attendance', async (req, res) => {
  const { date, class_id, session, final_state } = req.query;
  try {
    let query = `
      SELECT a.id, a.student_id, s.name AS student_name, s.roll, a.status, a.session,
             a.final_state, a.remark, a.date, a.override_by, a.override_reason,
             c.id AS class_id, c.name AS class_name, c.section
      FROM attendance a JOIN students s ON a.student_id = s.id JOIN classes c ON s.class_id = c.id
      WHERE 1=1`;
    const params = [];
    if (date) { query += ' AND a.date = ?'; params.push(date); }
    if (class_id) { query += ' AND c.id = ?'; params.push(class_id); }
    if (session) { query += ' AND a.session = ?'; params.push(session); }
    if (final_state) { query += ' AND a.final_state = ?'; params.push(final_state); }
    query += ' ORDER BY a.date DESC, s.roll';
    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ---- Truancy exception dashboard: today's TRUANT / LATE flags + overrides ----
router.get('/attendance/exceptions', async (req, res) => {
  const date = req.query.date || dhakaToday();
  try {
    const { FINAL_BN } = require('../attendance_fsm');
    const [rows] = await pool.query(
      `SELECT DISTINCT a.student_id, s.name AS student_name, s.roll,
              c.id AS class_id, c.name AS class_name, c.section,
              MAX(a.final_state) AS final_state,
              MAX(CASE WHEN a.override_reason IS NOT NULL THEN a.override_reason END) AS override_reason
       FROM attendance a JOIN students s ON s.id=a.student_id
       JOIN classes c ON c.id=s.class_id
       WHERE a.date=? AND a.final_state IN ('TRUANT_UNAUTHORIZED','LATE_ARRIVAL_UNCHECKED')
       GROUP BY a.student_id, s.name, s.roll, c.id, c.name, c.section
       ORDER BY c.name, s.roll`,
      [date]);
    res.json({ date,
      exceptions: rows.map(r => ({ ...r, final_bn: FINAL_BN[r.final_state] || r.final_state })) });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ---- Admin attendance override (out-of-window correction) — audit-logged ----
router.post('/attendance/override', async (req, res) => {
  const { student_id, date, session, status, remark, reason } = req.body || {};
  if (!student_id || !date || !status || !reason) {
    return res.status(400).json({ error: 'student_id, date, status, reason required' });
  }
  const sess = session === 'p5' ? 'p5' : 'morning';
  if (!['present', 'absent', 'late'].includes(status)) {
    return res.status(400).json({ error: 'Invalid status' });
  }
  try {
    await pool.query(
      `INSERT INTO attendance (student_id, date, session, status, remark, recorded_by, override_by, override_reason)
       VALUES (?,?,?,?,?,?,?,?)
       ON CONFLICT (student_id, date, session) DO UPDATE SET status=EXCLUDED.status,
        remark=EXCLUDED.remark, recorded_by=EXCLUDED.recorded_by,
        override_by=EXCLUDED.override_by, override_reason=EXCLUDED.override_reason`,
      [student_id, date, sess, status, remark || null, req.user.id, req.user.id, String(reason).slice(0, 255)]);
    await log(req.user.id, 'attendance_override',
      `Override ${student_id}/${date}/${sess} -> ${status}: ${reason}`);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ---- Leave inbox (admin sees all; class teacher sees own classes) ----
router.get('/leave-tickets', async (req, res) => {
  const status = req.query.status || 'pending';
  try {
    const [rows] = await pool.query(
      `SELECT t.*, s.name AS student_name, s.roll, c.name AS class_name, c.section
       FROM leave_tickets t JOIN students s ON s.id=t.student_id
       JOIN classes c ON c.id=s.class_id
       WHERE t.status=? ORDER BY t.leave_date DESC, t.id DESC LIMIT 300`, [status]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/notifications', async (req, res) => {
  const { class_id, student_id } = req.query;
  try {
    let query = `
      SELECT n.*, s.name AS student_name, c.name AS class_name, c.section, u.name AS sender_name
      FROM notifications n
      LEFT JOIN students s ON n.student_id = s.id
      LEFT JOIN classes c ON n.class_id = c.id
      LEFT JOIN users u ON n.created_by = u.id
      WHERE 1=1`;
    const params = [];
    if (class_id) { query += ' AND n.class_id = ?'; params.push(class_id); }
    if (student_id) { query += ' AND n.student_id = ?'; params.push(student_id); }
    query += ' ORDER BY n.id DESC LIMIT 200';
    const [rows] = await pool.query(query, params);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/notices', async (req, res) => {
  const { title, body, target_type, class_id, section, student_ids, guardian_ids } = req.body || {};
  if (!title) return res.status(400).json({ error: 'title required' });
  const type = target_type || 'all';
  let studentIdsFilter = null;
  let notifyStudentIds = null;
  try {
    // Resolve targeting into a set of recipient student ids / guardian tokens.
    let recipients = null; // null = all
    if (type === 'class') {
      if (!class_id) return res.status(400).json({ error: 'class_id required for class-type notice' });
      [recipients] = await pool.query('SELECT id FROM students WHERE class_id=?', [class_id]);
    } else if (type === 'section') {
      if (!class_id || !section) return res.status(400).json({ error: 'class_id and section required for section-type notice' });
      [recipients] = await pool.query(
        `SELECT s.id FROM students s JOIN classes c ON s.class_id=c.id WHERE c.id=? AND c.section=?`,
        [class_id, section]
      );
    } else if (type === 'students') {
      if (!Array.isArray(student_ids) || !student_ids.length) return res.status(400).json({ error: 'student_ids array required' });
      [recipients] = await pool.query('SELECT id FROM students WHERE id IN (?)', [student_ids]);
    } else if (type === 'guardians') {
      if (!Array.isArray(guardian_ids) || !guardian_ids.length) return res.status(400).json({ error: 'guardian_ids array required' });
      [recipients] = await pool.query('SELECT id FROM students WHERE guardian_id IN (?)', [guardian_ids]);
    }

    const noticeStudents = recipients ? recipients.map(r => r.id) : null;

    if (noticeStudents && noticeStudents.length) {
      // Bulk-insert notification rows (one per student) in a single query.
      const nValues = noticeStudents.map(() => '(?,?,?,?,?,?,?,?)').join(',');
      const nParams = [];
      for (const sid of noticeStudents) {
        nParams.push(sid, class_id || null, title, body || '', 'notice', type, null, req.user.id);
      }
      await pool.query(
        `INSERT INTO notifications (student_id, class_id, title, body, type, target_type, related_id, created_by)
         VALUES ${nValues}`,
        nParams
      );
      // Classroom-wide portion also stored once with no student for class/all
    } else {
      await pool.query(
        'INSERT INTO notifications (student_id, class_id, title, body, type, target_type, created_by) VALUES (NULL,?,?,?,?,?,?)',
        [class_id || null, title, body || '', 'notice', type, req.user.id]
      );
    }

    let tokens = noticeStudents
      ? await getGuardianTokens(noticeStudents)
      : await getAllGuardianTokens(type === 'class' || type === 'section' ? class_id || null : null);
    const queued = await queuePush(tokens, '🔔 New School Notice', title,
      { type: 'notice', target_type: type, class_id: String(class_id || ''), section: String(section || '') });
    await log(req.user.id, 'notice_send', 'Notice: ' + title + ` (${type}) [queued:${queued.queued}]`);
    res.status(201).json({ ok: true, push_sent: queued.queued || 0, students: noticeStudents ? noticeStudents.length : Infinity });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/holidays', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM holidays ORDER BY date');
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/holidays', async (req, res) => {
  const { date, title } = req.body || {};
  if (!date || !title) return res.status(400).json({ error: 'date and title required' });
  try {
    await pool.query('INSERT INTO holidays (date, title) VALUES (?,?) ON CONFLICT (date) DO UPDATE SET title=EXCLUDED.title', [date, title]);
    res.status(201).json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/holidays/:date', async (req, res) => {
  try {
    await pool.query('DELETE FROM holidays WHERE date=?', [req.params.date]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// Exam catalog + weightage engine (NCTB bands)
// =====================================================================
router.get('/exam-catalog', async (req, res) => {
  try {
    const [rows] = await pool.query(
      'SELECT id, band, exam_kind, weight_pct, is_promotion_source, sort_order FROM exam_catalog ORDER BY band, sort_order, id');
    res.json({ catalog: rows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/exam-catalog', async (req, res) => {
  const rows = Array.isArray(req.body && req.body.catalog) ? req.body.catalog : [];
  if (!rows.length) return res.status(400).json({ error: 'catalog array required' });
  try {
    for (const r of rows) {
      const band = String(r.band || '');
      const kind = String(r.exam_kind || '');
      const pct = Number(r.weight_pct);
      if (['6-9', '10', 'ssc'].indexOf(band) === -1) return res.status(400).json({ error: 'bad band: ' + band });
      if (!kind) return res.status(400).json({ error: 'exam_kind required' });
      if (!(pct >= 0 && pct <= 100)) return res.status(400).json({ error: 'weight_pct must be 0..100' });
      await pool.query(
        `INSERT INTO exam_catalog (band, exam_kind, weight_pct, updated_by, updated_at)
         VALUES (?,?,?,?,NOW())
         ON CONFLICT (band, exam_kind) DO UPDATE SET weight_pct=EXCLUDED.weight_pct, updated_by=EXCLUDED.updated_by, updated_at=NOW()`,
        [band, kind, pct, req.user.id]);
    }
    require('../exam_catalog').invalidate();
    await log(req.user.id, 'exam_catalog_update', `Updated ${rows.length} catalog row(s)`);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// Mandatory-pass subjects (grace cannot override these)
// =====================================================================
router.get('/mandatory-pass', async (req, res) => {
  const cid = Number(req.query.class_id);
  try {
    const [rows] = await pool.query(
      `SELECT mp.id, mp.class_id, mp.subject_id, s.name AS subject_name
         FROM mandatory_pass mp JOIN subjects s ON s.id = mp.subject_id
        ${cid ? 'WHERE mp.class_id = ?' : ''} ORDER BY mp.class_id, s.name`, cid ? [cid] : []);
    res.json({ rules: rows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/mandatory-pass', async (req, res) => {
  const classId = Number(req.body && req.body.class_id);
  const subjectIds = Array.isArray(req.body && req.body.subject_ids) ? req.body.subject_ids.map(Number).filter(Boolean) : null;
  if (!classId || subjectIds === null) return res.status(400).json({ error: 'class_id and subject_ids[] required' });
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query('DELETE FROM mandatory_pass WHERE class_id=?', [classId]);
    for (const sid of subjectIds) {
      await conn.query(
        'INSERT INTO mandatory_pass (class_id, subject_id) VALUES (?,?) ON CONFLICT (class_id, subject_id) DO NOTHING',
        [classId, sid]);
    }
    await conn.commit();
    await log(req.user.id, 'mandatory_pass_update', `Class ${classId}: ${subjectIds.length} mandatory subject(s)`);
    res.json({ ok: true, class_id: classId, count: subjectIds.length });
  } catch (err) { await conn.rollback(); console.error(err); res.status(500).json({ error: 'Server error' }); }
  finally { conn.release(); }
});

router.get('/settings', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT setting_key, setting_value FROM app_settings');
    const settings = {};
    rows.forEach(r => { settings[r.setting_key] = r.setting_value; });
    res.json(settings);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/settings', async (req, res) => {
  const entries = Object.entries(req.body || {});
  try {
    for (const [k, v] of entries) {
      await pool.query(
        'INSERT INTO app_settings (setting_key, setting_value) VALUES (?,?) ON CONFLICT (setting_key) DO UPDATE SET setting_value=EXCLUDED.setting_value',
        [k, String(v == null ? '' : v)]
      );
    }
    await log(req.user.id, 'settings_update', entries.map(e => e[0]).join(','));
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Logo upload endpoint - multipart form with 'logo' field
const logoUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (/^image\/(jpeg|png|webp)$/.test(file.mimetype)) cb(null, true);
    else cb(new Error('Only JPG/PNG/WebP images allowed'));
  }
});

router.post('/settings/logo', auth('admin'), logoUpload.single('logo'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'logo file required' });
    
    const sharp = require('sharp');
    const metadata = await sharp(req.file.buffer).metadata();
    if (!metadata.width || !metadata.height) {
      return res.status(400).json({ error: 'The selected image could not be read. Please choose a PNG, JPG, or WebP image.' });
    }
    // Normalize uploads to a compact PNG while preserving any transparent background.
    const png = await sharp(req.file.buffer)
      .rotate()
      .resize({ width: 800, height: 800, fit: 'inside', withoutEnlargement: true })
      .png({ compressionLevel: 9 })
      .toBuffer();
    const logoUrl = await uploadSchoolLogo(png);
    await pool.query(
      'INSERT INTO app_settings (setting_key, setting_value) VALUES (?,?) ON CONFLICT (setting_key) DO UPDATE SET setting_value=EXCLUDED.setting_value',
      ['school_logo_path', logoUrl]
    );
    await log(req.user.id, 'logo_upload', 'School logo updated');
    
    res.json({ ok: true, logo_url: logoUrl });
  } catch (err) {
    console.error(err);
    res.status(err.status || 500).json({ error: err.message || 'Logo upload failed' });
  }
});

router.post('/students/:id/photo', auth('admin'), photoUpload.single('photo'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'photo file required' });
    const [[stu]] = await pool.query('SELECT photo FROM students WHERE id=?', [req.params.id]);
    if (stu && stu.photo) {
      const old = path.join(uploadsDir, stu.photo);
      if (fs.existsSync(old)) fs.unlinkSync(old);
    }
    await pool.query('UPDATE students SET photo=? WHERE id=?', [req.file.filename, req.params.id]);
    await log(req.user.id, 'student_photo', 'Photo uploaded for student ' + req.params.id);
    res.json({ ok: true, photo: req.file.filename });
  } catch (err) {
    console.error(err);
    res.status(err.message.includes('images') ? 400 : 500).json({ error: err.message.includes('images') ? err.message : 'Server error' });
  }
});

router.post('/marks-bulk', async (req, res) => {
  const { exam_id, records } = req.body || {};
  if (!exam_id || !Array.isArray(records) || !records.length) {
    return res.status(400).json({ error: 'exam_id and records required' });
  }
  try {
    const [[exam]] = await pool.query(
      'SELECT e.id, e.class_id, e.exam_date, e.entry_deadline, sub.full_marks AS subject_full FROM exams e JOIN subjects sub ON e.subject_id=sub.id WHERE e.id=?',
      [exam_id]);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    if (exam.entry_deadline) {
      const dl = exam.entry_deadline instanceof Date ? exam.entry_deadline.getTime() : new Date(exam.entry_deadline).getTime();
      if (!isNaN(dl) && Date.now() > dl) {
        // Deadline পার — admin নিজে extend না করা পর্যন্ত entry বন্ধ।
        // চাইলে এখুনি নতুন deadline দিয়ে entry reopen করতে পারেন (PUT /exams/:id).
        return res.status(403).json({ error: 'Marks entry closed: deadline has passed. Admin নতুন deadline বসিয়ে reopen করতে পারেন।' });
      }
    } else if (exam.exam_date) {
      const d = ymd(exam.exam_date);
      const examDateMs = new Date(d + 'T23:59:59').getTime();
      if (Date.now() > examDateMs) {
        return res.status(403).json({
          error: 'Marks entry closed: this exam\u2019s date-limit (' + d + ') has passed.'
        });
      }
    }
    const defaultTotal = Number(exam.subject_full) || 100;
    const [classStudents] = await pool.query('SELECT id FROM students WHERE class_id=?', [exam.class_id]);
    const allowed = new Set(classStudents.map(s => String(s.id)));
    const seen = new Set();
    for (const r of records) {
      if (!allowed.has(String(r.student_id))) {
        return res.status(403).json({ error: `Student ${r.student_id} does not belong to the exam class` });
      }
      if (seen.has(String(r.student_id))) {
        return res.status(400).json({ error: `Duplicate mark entry for student ${r.student_id}` });
      }
      seen.add(String(r.student_id));
    }
    const vErrs = [];
    for (const r of records) {
      const v = validateMarksValue(r.marks, r.total !== undefined ? r.total : defaultTotal);
      if (v) vErrs.push(`Student ${r.student_id}: ${v}`);
    }
    if (vErrs.length) return res.status(400).json({ error: vErrs[0] });

    for (const r of records) {
      const total = r.total !== undefined && r.total !== null && r.total !== '' ? r.total : defaultTotal;
      await pool.query(
        `INSERT INTO marks (student_id, exam_id, marks, total, comment, recorded_by)
         VALUES (?,?,?,?,?,?)
         ON CONFLICT (student_id, exam_id) DO UPDATE SET marks=EXCLUDED.marks, total=EXCLUDED.total, comment=EXCLUDED.comment`,
        [r.student_id, exam_id, r.marks, total, r.comment || null, req.user.id]
      );
    }
    await log(req.user.id, 'marks_bulk', `Bulk marks for exam ${exam_id} (${records.length} students)`);
    res.json({ ok: true, count: records.length });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/exams/:id/publish-admin', async (req, res) => {
  try {
    const [[examRow]] = await pool.query('SELECT source FROM exams WHERE id=?', [req.params.id]);
    if (!examRow) return res.status(404).json({ error: 'Exam not found' });
    if (examRow.source === 'teacher') {
      return res.status(403).json({ error: 'Teacher-created class tests are published by the teacher app' });
    }
    await pool.query("UPDATE exams SET status='published' WHERE id=?", [req.params.id]);
    await log(req.user.id, 'exam_publish', 'Admin published exam ' + req.params.id);
    // Notify guardians of all students who have marks in this exam.
    try {
      const [marks] = await pool.query(
        `SELECT m.student_id, s.guardian_id FROM marks m JOIN students s ON m.student_id=s.id WHERE m.exam_id=?`,
        [req.params.id]
      );
      const studentIds = marks.map(m => m.student_id);
      const [[exam]] = await pool.query(
        `SELECT e.name, sub.name AS subject_name FROM exams e JOIN subjects sub ON e.subject_id=sub.id WHERE e.id=?`,
        [req.params.id]
      );
      if (studentIds.length) {
        const tokens = await getGuardianTokens(studentIds);
        await queuePush(tokens,
          'New result published for your child',
          `${exam ? exam.name : 'Result'} — ${exam ? exam.subject_name : ''} result is now available in the app`,
          { type: 'result', exam_id: String(req.params.id), exam_name: exam ? String(exam.name) : '' });
        // Bulk-insert per-student result notifications.
        const iValues = studentIds.map(() => '(?,?,?,?,?,?,?)').join(',');
        const iParams = [];
        for (const sid of studentIds) {
          iParams.push(sid, 'Exam Result Published',
           `${exam ? exam.name + ' (' + exam.subject_name + ')' : 'Exam result'} has been published`,
           'result', 'class', req.params.id, req.user.id);
        }
        await pool.query(
          `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, created_by)
           VALUES ${iValues}`,
          iParams
        );
      }
    } catch (e) { console.error('publish notify error:', e.message); }
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// --- Exam sharing (admin grants other teachers access to a teacher-created exam) ---
router.get('/exams/:id/shares', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT es.teacher_id, u.name AS teacher_name FROM exam_shares es
       JOIN users u ON u.id=es.teacher_id WHERE es.exam_id=?`,
      [req.params.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/exams/:id/shares', async (req, res) => {
  const { teacher_id } = req.body || {};
  if (!teacher_id) return res.status(400).json({ error: 'teacher_id required' });
  try {
    await pool.query(
      'INSERT INTO exam_shares (exam_id, teacher_id, created_by) VALUES (?,?,?) ON CONFLICT (exam_id, teacher_id) DO UPDATE SET created_by=?',
      [req.params.id, teacher_id, req.user.id, req.user.id]
    );
    await log(req.user.id, 'exam_share', `Shared exam ${req.params.id} with teacher ${teacher_id}`);
    res.status(201).json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/exams/:id/shares/:teacherId', async (req, res) => {
  try {
    await pool.query('DELETE FROM exam_shares WHERE exam_id=? AND teacher_id=?', [req.params.id, req.params.teacherId]);
    await log(req.user.id, 'exam_unshare', `Removed teacher ${req.params.teacherId} from exam ${req.params.id}`);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/exams/:id/unpublish', async (req, res) => {
  try {
    const [[examRow]] = await pool.query('SELECT source FROM exams WHERE id=?', [req.params.id]);
    if (!examRow) return res.status(404).json({ error: 'Exam not found' });
    if (examRow.source === 'teacher') {
      return res.status(403).json({ error: 'Teacher-created class tests are managed by the teacher app' });
    }
    await pool.query("UPDATE exams SET status='draft' WHERE id=?", [req.params.id]);
    await log(req.user.id, 'exam_unpublish', 'Admin unpublished exam ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// Promotion engine (event-based, all classes).
// The admin picks a PUBLISHED Annual (Class 6-9) or Test (Class 10) EVENT for
// a class; the engine grades it with the same grading module, counts failed
// subject families (4th subject excluded), and applies the admin-configurable
// grace rule. Promoted / conditionally-promoted (grace) students are
// pre-checked and move to the next class on execute; others stay put.
// The admin may override individual students in either direction.
// Guardians only ever see the outcome (promoted / উত্তীর্ণ নয়) on the
// result card — never the raw failure detail, except their own marks list.
// =====================================================================

// Map a source class to its promotion destination:
// Class 10 (any group) -> matching SSC Batch group row;
// Class N -> Class N+1 with the same section (6-8) or group (9).
async function promotionDestination(conn, cls) {
  const name = String(cls.name || '');
  const key = cls.group_name || cls.section || null;
  if (/class\s*10/i.test(name)) {
    const [batches] = await conn.query(
      `SELECT id, name, section, group_name FROM classes WHERE name='SSC Batch' ORDER BY id`, []);
    return batches.find(b => String(b.group_name || b.section || '') === String(key || '')) ||
      (batches.length === 1 ? batches[0] : null);
  }
  const m = name.match(/(\d+)/);
  if (!m) return null;
  const nextName = 'Class ' + (Number(m[1]) + 1);
  const [destinations] = await conn.query(
    `SELECT id, name, section, group_name FROM classes WHERE name=? ORDER BY id`, [nextName]);
  return destinations.find(d => String(d.group_name || d.section || '') === String(key || '')) ||
    (destinations.length === 1 ? destinations[0] : null);
}

// =====================================================================
// Exam approval queue (class teacher approves, admin monitors/overrides)
// =====================================================================
router.get('/approvals/pending', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT x.id, x.name, x.entry_status, x.submitted_at, x.approved_at,
              x.class_id, c.name AS class_name, c.section AS class_section,
              x.subject_id, sub.name AS subject_name,
              x.event_id, ev.name AS event_name, ev.exam_kind,
              x.submitted_by, u.name AS submitted_by_name
         FROM exams x
         JOIN classes c ON c.id = x.class_id
         JOIN subjects sub ON sub.id = x.subject_id
         LEFT JOIN exam_events ev ON ev.id = x.event_id
         LEFT JOIN users u ON u.id = x.submitted_by
        WHERE x.entry_status = 'submitted' AND x.event_id IS NOT NULL
        ORDER BY x.submitted_at DESC NULLS LAST, x.id DESC`);
    res.json({ pending: rows, count: rows.length });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/exams/:id/approve', async (req, res) => {
  try {
    const [[exam]] = await pool.query('SELECT id, entry_status FROM exams WHERE id=?', [req.params.id]);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    if (exam.entry_status !== 'submitted') {
      return res.status(400).json({ error: `entry_status is "${exam.entry_status}", only "submitted" can be approved` });
    }
    const { validateExamMarks } = require('../mark_validation');
    const v = await validateExamMarks(exam.id, { strict: true });
    if (!v.ok) return res.status(422).json({ error: 'Validation failed on approval', errors: v.errors, error_count: v.error_count });
    await pool.query(
      `UPDATE exams SET entry_status='approved', approved_at=NOW(), approved_by=?, reject_reason=NULL WHERE id=?`,
      [req.user.id, exam.id]);
    await log(req.user.id, 'exam_approve', `Approved exam ${exam.id}`);
    res.json({ ok: true, entry_status: 'approved' });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/exams/:id/reject', async (req, res) => {
  const reason = (req.body && req.body.reason) || null;
  try {
    const [[exam]] = await pool.query('SELECT id, entry_status FROM exams WHERE id=?', [req.params.id]);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    if (exam.entry_status !== 'submitted') return res.status(400).json({ error: 'Only submitted exams can be rejected' });
    await pool.query(
      `UPDATE exams SET entry_status='draft', reject_reason=? WHERE id=?`, [reason, exam.id]);
    await log(req.user.id, 'exam_reject', `Rejected exam ${exam.id}: ${reason || ''}`);
    res.json({ ok: true, entry_status: 'draft' });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Allow the admin to configure how many failed subject families a Class 10
// test-event may tolerate while still auto-promoting ("grace").
router.put('/promote/grace', async (req, res) => {
  const { class_id, exam_type, grace_failed, notes } = req.body || {};
  const cid = Number(class_id);
  const g = Number(grace_failed);
  if (!cid || g < 0 || g > 11) return res.status(400).json({ error: 'class_id and grace_failed (0..11) required' });
  try {
    await pool.query(
      `INSERT INTO promotion_grace (class_id, exam_type, grace_failed, notes)
       VALUES (?,?,?,?)
       ON CONFLICT (class_id, exam_type) DO UPDATE SET grace_failed=EXCLUDED.grace_failed, notes=EXCLUDED.notes, updated_at=NOW()`,
      [cid, exam_type || 'test', g, notes ? String(notes) : null]
    );
    await log(req.user.id, 'promote_grace', `Set grace=${g} for class ${cid}`);
    res.json({ ok: true, class_id: cid, grace_failed: g });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/promote/review', async (req, res) => {
  const { class_id, event_id } = req.body || {};
  const cid = Number(class_id);
  const eid = Number(event_id);
  if (!cid || !eid) return res.status(400).json({ error: 'class_id and event_id required (published Annual/Test event)' });
  try {
    // The event must contain at least one exam for this class.
    const [[ev]] = await pool.query(
      `SELECT e.id, e.name, e.start_date, e.exam_kind, e.year, e.promotion_linked, e.is_published FROM exam_events e
        WHERE e.id=? AND EXISTS (
          SELECT 1 FROM exams x WHERE x.event_id=e.id AND x.class_id=?
        )`, [eid, cid]);
    if (!ev) return res.status(400).json({ error: 'No exam event found for this class' });
    const [[cls]] = await pool.query('SELECT id, name, section, group_name FROM classes WHERE id=?', [cid]);
    if (!cls) return res.status(404).json({ error: 'Class not found' });
    if (/ssc/i.test(String(cls.name || ''))) {
      return res.status(400).json({ error: 'SSC Batch শেষ শিক্ষাবর্ষ; এখান থেকে আর promotion হয় না।' });
    }
    // Source rule (same as teacher review): 6–9 ← annual, 10 ← test, published.
    const isClass10 = /class\s*10/i.test(String(cls.name || ''));
    const needKind = isClass10 ? 'test' : 'annual';
    if (String(ev.exam_kind) !== needKind) {
      return res.status(400).json({ error:
        isClass10
          ? `Class 10 promotion শুধু TEST event থেকে হয় — “${ev.name}” (${ev.exam_kind}) দিয়ে promotion হবে না।`
          : `Class 6–9 promotion শুধু ANNUAL event থেকে হয় — “${ev.name}” (${ev.exam_kind}) দিয়ে promotion হবে না।` });
    }
    if (Number(ev.is_published) !== 1) {
      return res.status(400).json({ error: 'Event এখনো publish হয়নি — publish-এর পর promotion করা যাবে।' });
    }
    const kind = needKind;
    const [[grace]] = await pool.query(
      `SELECT grace_failed FROM promotion_grace WHERE class_id=? AND exam_type=?`, [cid, kind]);
    const graceFailed = grace ? Number(grace.grace_failed) : 0;
    const dest = await promotionDestination(pool, cls);

    const [students] = await pool.query(
      'SELECT id, name, student_code, roll FROM students WHERE class_id=? ORDER BY roll', [cid]);
    const review = [];
    for (const s of students) {
      const r = await computeResult(s.id, eid);
      if (!r) continue; // student has no gradable marks in this event
      // Count failed NON-4th subject families only (4th subject fail has no penalty).
      const failedNames = (r.families || [])
        .filter((f) => !f.is_optional && f.letter_grade === 'F')
        .map((f) => f.subject);
      const failCount = failedNames.length;
      const hasMarkRows = (r.families || []).length > 0;
      let decision;
      let eligible = false;
      if (r.result_status === 'ABSENT' || !hasMarkRows) {
        decision = 'retained';
      } else if (failCount === 0) {
        decision = 'promoted'; eligible = true;
      } else if (failCount <= graceFailed) {
        decision = 'grace_promoted'; eligible = true;
      } else {
        decision = 'retained';
      }
      review.push({
        id: s.id, name: s.name, student_code: s.student_code, roll: s.roll,
        group_name: s.group_name || cls.group_name,
        final_gpa: r.final_gpa, total_gpa_without_4th: r.total_gpa_without_4th,
        gpa_4th_bonus: r.gpa_4th_bonus,
        result_status: r.result_status,
        fail_count: failCount, failed_subjects: failedNames,
        decision, eligible
      });
    }
    review.sort((a, b) => Number(b.final_gpa) - Number(a.final_gpa) || a.roll - b.roll);
    await log(req.user.id, 'promote_review_v2', `Reviewed class ${cid} event ${eid} (${review.length}/${students.length} students)`);
    res.json({ event: ev, class: cls, kind, grace_failed: graceFailed, dest_class: dest,
      total: review.length, review });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/promote/execute', async (req, res) => {
  const { class_id, event_id, students } = req.body || {};
  const cid = Number(class_id);
  const eid = Number(event_id);
  if (!cid || !eid || !Array.isArray(students) || !students.length) {
    return res.status(400).json({ error: 'class_id, event_id and students[] required' });
  }
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [[cls]] = await conn.query('SELECT id, name, section, group_name FROM classes WHERE id=?', [cid]);
    if (!cls) throw new Error('Class not found');
    // Destination: next class (same section/group) or matching SSC Batch row.
    // Null when it cannot be determined (e.g. Class 8 section -> Class 9 group)
    // — promote flags for such students are treated as retained.
    const dest = await promotionDestination(conn, cls);
    const incrementRolls = (toClassId) => conn.query(
      `SELECT COALESCE(MAX(roll),0) m FROM students WHERE class_id=?`, [toClassId]);

    const promoted = [];
    const retained = [];
    // Passing-year tag: from the promotion source event (canonical year).
    const [[srcEv]] = await conn.query('SELECT id, year, exam_kind FROM exam_events WHERE id=?', [eid]);
    const srcYear = srcEv && srcEv.year ? Number(srcEv.year) : new Date().getFullYear();
    // SSC Examinee Batch tagging: Test Exam promotions carry the year the
    // student will sit for SSC (source year + 1); Annual promotions carry
    // the next academic year as their destination session year.
    const isTestPromo = srcEv && String(srcEv.exam_kind) === 'test';
    const destYear = isTestPromo ? srcYear + 1 : srcYear + 1;
    for (const st of students) {
      const sid = Number(st.id);
      if (!sid) continue;
      const promote = !!st.promote;
      const [[stu]] = await conn.query(
        'SELECT id, name, class_id FROM students WHERE id=?', [sid]);
      if (!stu || Number(stu.class_id) !== cid) continue; // only same-class students

      // Move only when a destination class is known; a promote flag without a
      // determinable destination (e.g. Class 8 section -> Class 9 group) is
      // recorded as retained so nobody is moved to a wrong class.
      const doMove = promote && !!dest;
      if (doMove) {
        const toClassId = dest.id;
        const [[maxRoll]] = await incrementRolls(toClassId);
        const newRoll = Number(maxRoll.m || maxRoll[0] || 0) + 1;
        await conn.query(
          'UPDATE students SET class_id=?, section=NULL, status=\'active\' WHERE id=?',
          [toClassId, sid]);
        const decision = st.decision === 'grace_promoted' ? 'grace_promoted'
                       : (st.decision === 'admin_override' ? 'admin_override' : 'promoted');
        await conn.query(
          `INSERT INTO promotions (student_id, event_id, class_id, group_name, from_class, to_class,
                                   promoted_roll, decision, final_gpa, recorded_by, passing_year)
           VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
          [sid, eid, cid, stu.group_name || cls.group_name, cls.name, dest ? dest.name : cls.name,
           newRoll, decision, st.final_gpa != null ? Number(st.final_gpa) : null, req.user.id,
           /class\s*10/i.test(cls.name||'') ? destYear : null]);
        await conn.query(
          `INSERT INTO promotion_history (student_id, from_class_id, to_class_id, final_gpa, decision,
                                          admin_note)
           VALUES (?,?,?,?,?,?)`,
          [sid, cid, toClassId, st.final_gpa != null ? Number(st.final_gpa) : null,
           decision === 'retained' ? 'retained' : 'promoted', st.note || null]);
        await conn.query(
          `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, created_by)
           VALUES (?,?,?,?,?,?,?)`,
          [sid, isTestPromo ? 'SSC Batch — উত্তীর্ণ' : 'Promotion — উত্তীর্ণ',
           (isTestPromo
             ? `অভিনন্দন! আপনি SSC ${destYear} ব্যাচে (${dest.name}) উত্তীর্ণ হয়েছেন। নতুন রোল: ${newRoll}`
             : `অভিনন্দন! আপনি ${dest.name} এ উত্তীর্ণ হয়েছেন। নতুন রোল: ${newRoll}`),
           'promotion', 'students', eid, req.user.id]);
        promoted.push({ id: sid, roll: newRoll, decision });
      } else {
        const [[ph]] = await conn.query(
          `SELECT id FROM promotion_history WHERE student_id=? AND decision='retained' ORDER BY id DESC LIMIT 1`, [sid]);
        await conn.query(
          `INSERT INTO promotions (student_id, event_id, class_id, group_name, from_class, to_class,
                                   decision, final_gpa, recorded_by)
           VALUES (?,?,?,?,?,?,?,?,?)`,
          [sid, eid, cid, stu.group_name || cls.group_name, cls.name, cls.name,
           'retained', st.final_gpa != null ? Number(st.final_gpa) : null, req.user.id]);
        if (!ph) {
          await conn.query(
            `INSERT INTO promotion_history (student_id, from_class_id, to_class_id, final_gpa, decision)
              VALUES (?,?,?,?,?)`,
            [sid, cid, cid, st.final_gpa != null ? Number(st.final_gpa) : null, 'retained']);
        }
        retained.push({ id: sid });
      }
    }
    // Keep roll uniqueness tidy in the destination class.
    if (dest) {
      const [dstStudents] = await conn.query(
        'SELECT id FROM students WHERE class_id=? ORDER BY roll, id', [dest.id]);
      dstStudents.forEach((s, i) => {
        conn.query('UPDATE students SET roll=? WHERE id=?', [i + 1, s.id]);
      });
    }
    await conn.commit();
    await log(req.user.id, 'promote_execute_v2', `Executed class ${cid} event ${eid}: ${promoted.length} promoted, ${retained.length} retained`);
    res.json({ ok: true, promoted, retained: retained.map(r => r.id), class_id: cid, event_id: eid });
  } catch (err) { await conn.rollback(); console.error(err); res.status(500).json({ error: 'Server error' }); }
  finally { conn.release(); }
});

// =====================================================================
// Promotion & merit engine v3 (Q9): dual merit, auto-balance, groups
// =====================================================================
const promoEngine = require('../promotion_engine');

// Master merit list for a class on an event (admin prize/merit list).
router.get('/merit-list', async (req, res) => {
  const cid = Number(req.query.class_id);
  const eid = Number(req.query.event_id);
  if (!cid || !eid) return res.status(400).json({ error: 'class_id and event_id required' });
  try {
    const merit = await promoEngine.computeMerit(cid, eid);
    res.json({ total: merit.total, rows: merit.rows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Q14: Promoted-student list for a class+event, grouped by destination
// section, ready for on-device PDF generation (admin app).
router.get('/promoted-list', async (req, res) => {
  const cid = Number(req.query.class_id);
  const eid = Number(req.query.event_id);
  if (!cid || !eid) return res.status(400).json({ error: 'class_id and event_id required' });
  try {
    const review = await promoEngine.reviewPromotion(cid, eid);
    const [[cls]] = await pool.query('SELECT id, name FROM classes WHERE id=?', [cid]);
    const dest = await promoEngine.promotionDestination(pool, cls);
    const promoted = review.review.filter(r => r.eligible).map(r => ({
      student_id: r.student_id, name: r.name, student_code: r.student_code,
      old_roll: r.old_roll, old_section: r.old_section,
      combined_rank: r.combined_rank, total_marks_obtained: r.total_marks_obtained,
      final_gpa: r.final_gpa, decision: r.decision,
      status_bn: r.decision === 'conditional' ? 'শর্তসাপেক্ষে উত্তীর্ণ' : 'উত্তীর্ণ',
    }));
    const retained = review.review.filter(r => !r.eligible).map(r => ({
      student_id: r.student_id, name: r.name, student_code: r.student_code,
      old_roll: r.old_roll, old_section: r.old_section,
      combined_rank: r.combined_rank, total_marks_obtained: r.total_marks_obtained,
      final_gpa: r.final_gpa, decision: r.decision, status_bn: 'উত্তীর্ণ নয়',
    }));
    res.json({
      class_id: cid, class_name: cls ? cls.name : '',
      event_id: eid, event_name: review.event ? review.event.name : '',
      from_class: cls, to_class: dest ? { id: dest.id, name: dest.name } : null,
      total: review.total, promoted, retained,
    });
  } catch (err) { console.error(err); res.status(err.status || 500).json({ error: err.message || 'Server error' }); }
});

// Review with mandatory-pass + grace decisions (v3 engine).
router.post('/promote/review-v3', async (req, res) => {
  const cid = Number(req.body && req.body.class_id);
  const eid = Number(req.body && req.body.event_id);
  if (!cid || !eid) return res.status(400).json({ error: 'class_id and event_id required' });
  try {
    const r = await promoEngine.reviewPromotion(cid, eid);
    await log(req.user.id, 'promote_review_v3', `Reviewed class ${cid} event ${eid}: ${r.total} students`);
    res.json(r);
  } catch (err) { console.error(err); res.status(err.status || 500).json({ error: err.message || 'Server error' }); }
});

// Preview the balanced section split (no writes to students).
router.post('/promote/balance', async (req, res) => {
  const cid = Number(req.body && req.body.class_id);
  const eid = Number(req.body && req.body.event_id);
  const algorithm = (req.body && req.body.algorithm) || 'snake';
  if (!cid || !eid) return res.status(400).json({ error: 'class_id and event_id required' });
  try {
    const r = await promoEngine.balanceRun(eid, cid, { algorithm });
    await log(req.user.id, 'promote_balance', `Balanced class ${cid} event ${eid} (${r.total_promoted} students)`);
    res.json(r);
  } catch (err) { console.error(err); res.status(err.status || 500).json({ error: err.message || 'Server error' }); }
});

// Execute a previously balanced run (moves students + writes rolls).
router.post('/promote/execute-run', async (req, res) => {
  const runId = Number(req.body && req.body.run_id);
  if (!runId) return res.status(400).json({ error: 'run_id required' });
  try {
    const r = await promoEngine.executeRun(runId, req.user.id);
    await log(req.user.id, 'promote_execute_run', `Executed run ${runId}: ${r.moved} students`);
    res.json(r);
  } catch (err) { console.error(err); res.status(err.status || 500).json({ error: err.message || 'Server error' }); }
});

// Class 8 -> Class 9 group pool.
router.get('/group-pool', async (req, res) => {
  const cid = Number(req.query.class_id);
  const eid = Number(req.query.event_id);
  if (!cid || !eid) return res.status(400).json({ error: 'class_id and event_id required' });
  try {
    const r = await promoEngine.groupPool(cid, eid);
    res.json(r);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/group-assign', async (req, res) => {
  const { student_id, class_id, group } = req.body || {};
  if (!student_id || !class_id || !group) return res.status(400).json({ error: 'student_id, class_id, group required' });
  try {
    const dest = await promoEngine.assignGroup(Number(student_id), Number(class_id), group, req.user.id);
    await log(req.user.id, 'group_assign', `Student ${student_id} -> ${group} (class ${dest.id})`);
    res.json({ ok: true, to_class_id: dest.id, group: dest.group_name || dest.section });
  } catch (err) { console.error(err); res.status(err.status || 500).json({ error: err.message || 'Server error' }); }
});

router.post('/group-transfer', async (req, res) => {
  const { student_id, to_group, reason } = req.body || {};
  if (!student_id || !to_group) return res.status(400).json({ error: 'student_id and to_group required' });
  try {
    const r = await promoEngine.transferGroup(Number(student_id), to_group, reason || null, req.user.id);
    await log(req.user.id, 'group_transfer', `Student ${student_id} -> group ${to_group}`);
    res.json(r);
  } catch (err) { console.error(err); res.status(err.status || 500).json({ error: err.message || 'Server error' }); }
});

router.put('/group-eligibility', async (req, res) => {
  const { group_name, mandatory_subjects, min_marks } = req.body || {};
  if (!group_name) return res.status(400).json({ error: 'group_name required' });
  try {
    await pool.query(
      `INSERT INTO group_eligibility_rules (group_name, mandatory_subjects, min_marks, updated_by, updated_at)
       VALUES (?,?,?,?,NOW())
       ON CONFLICT (group_name) DO UPDATE SET mandatory_subjects=EXCLUDED.mandatory_subjects,
         min_marks=EXCLUDED.min_marks, updated_by=EXCLUDED.updated_by, updated_at=NOW()`,
      [group_name, mandatory_subjects || [], JSON.stringify(min_marks || {}), req.user.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// NEW EXAM DASHBOARD & PROGRESS APIs
// =====================================================================

// Entry progress tracking
router.get('/entry-progress', getEntryProgress);

// Bulk mark import (CSV/Excel)
const csvUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, path.join(__dirname, '..', 'uploads')),
    filename: (req, file, cb) => cb(null, 'marks_import_' + Date.now() + '.csv'),
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (file.mimetype === 'text/csv' || file.originalname.endsWith('.csv')) cb(null, true);
    else cb(new Error('Only CSV files allowed'));
  }
});
router.post('/import-marks', csvUpload.single('file'), importMarks);

// Marksheet templates
router.get('/marksheet-templates', getMarksheetTemplate);
router.post('/marksheet-templates', saveMarksheetTemplate);

// Exam scheduling/calendar
router.get('/exam-calendar', getExamCalendar);
router.put('/events/:id/dates', updateExamDates);

// Analytics
router.get('/analytics', getAnalytics);

// Automated workflows
router.post('/auto-create-subject-exams', autoCreateSubjectExams);

// Conflict validation
router.get('/validate-conflicts', validateConflicts);

// =====================================================================
// PROMOTION SYSTEM APIs
// =====================================================================

// Get promotion rules for all classes (with optional class filter)
router.get('/promotion-rules', async (req, res) => {
  try {
    const { class_id } = req.query;
    let where = '';
    const params = [];
    if (class_id) {
      where = 'WHERE pr.class_id = ?';
      params.push(class_id);
    }
    const [rows] = await pool.query(
      `SELECT pr.*, c.name AS class_name, c.section, c.group_name
       FROM promotion_rules pr
       JOIN classes c ON c.id = pr.class_id
       ${where}
       ORDER BY c.name, c.section, pr.exam_type`,
      params
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Create or update promotion rule
router.put('/promotion-rules', async (req, res) => {
  try {
    const { class_id, exam_type, is_promotion_source, weight_annual, weight_test, min_passing_gpa, allow_conditional, grace_failed_subjects, mandatory_subjects } = req.body || {};
    const cid = Number(class_id);
    if (!cid || !exam_type) return res.status(400).json({ error: 'class_id and exam_type required' });

    const mandatoryArr = Array.isArray(mandatory_subjects) ? mandatory_subjects : [];
    const grace = Number(grace_failed_subjects) || 0;

    await pool.query(
      `INSERT INTO promotion_rules (class_id, exam_type, is_promotion_source, weight_annual, weight_test, min_passing_gpa, allow_conditional, grace_failed_subjects, mandatory_subjects, updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,NOW())
       ON CONFLICT (class_id, exam_type) DO UPDATE SET
         is_promotion_source=EXCLUDED.is_promotion_source,
         weight_annual=EXCLUDED.weight_annual,
         weight_test=EXCLUDED.weight_test,
         min_passing_gpa=EXCLUDED.min_passing_gpa,
         allow_conditional=EXCLUDED.allow_conditional,
         grace_failed_subjects=EXCLUDED.grace_failed_subjects,
         mandatory_subjects=EXCLUDED.mandatory_subjects,
         updated_at=NOW()`,
      [cid, exam_type, is_promotion_source ? 1 : 0, weight_annual || 1.0, weight_test || 1.0, min_passing_gpa || 2.0, allow_conditional ? 1 : 0, grace, mandatoryArr]
    );

    // Sync with promotion_grace
    if (exam_type) {
      await pool.query(
        `INSERT INTO promotion_grace (class_id, exam_type, grace_failed, notes)
         VALUES (?,?,?, 'synced from promotion_rules')
         ON CONFLICT (class_id, exam_type) DO UPDATE SET grace_failed=EXCLUDED.grace_failed, notes=EXCLUDED.notes, updated_at=NOW()`,
        [cid, exam_type, grace]
      );
    }

    await log(req.user.id, 'promotion_rule_update', `Updated rule for class ${cid} exam_type ${exam_type}`);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Get promotion rules for a specific class
router.get('/promotion-rules/class/:classId', async (req, res) => {
  try {
    const cid = Number(req.params.classId);
    const [rows] = await pool.query(
      `SELECT * FROM promotion_rules WHERE class_id=? ORDER BY exam_type`,
      [cid]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Calculate promotion eligibility for a class/event
router.post('/promotion/calculate', async (req, res) => {
  try {
    const { class_id, event_id, target_session_id } = req.body || {};
    const cid = Number(class_id);
    const eid = Number(event_id);
    const targetSessionId = Number(target_session_id);
    if (!cid || !eid || !targetSessionId) return res.status(400).json({ error: 'class_id, event_id and next academic session are required' });

    // Get class and event info
    const [[cls]] = await pool.query('SELECT id, name, section, group_name FROM classes WHERE id=?', [cid]);
    if (!cls) return res.status(404).json({ error: 'Class not found' });
    if (/ssc/i.test(String(cls.name || ''))) {
      return res.status(400).json({ error: 'SSC Batch শেষ শিক্ষাবর্ষ; এখান থেকে আর promotion হয় না।' });
    }

    const [[ev]] = await pool.query(
      `SELECT e.id, e.name, e.exam_kind, e.year, e.session_id, e.is_published, s.name AS session_name
       FROM exam_events e LEFT JOIN sessions s ON s.id=e.session_id WHERE e.id=?`, [eid]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    if (Number(ev.is_published) !== 1) return res.status(400).json({ error: 'Event must be published' });

    const sourceYear = Number(ev.year) || Number(String(ev.session_name || '').match(/(19|20)\d{2}/)?.[0]);
    const [[targetSession]] = await pool.query('SELECT id, name FROM sessions WHERE id=?', [targetSessionId]);
    const targetYear = Number(String(targetSession?.name || '').match(/(19|20)\d{2}/)?.[0]);
    if (!sourceYear || !targetSession || targetYear !== sourceYear + 1) {
      return res.status(400).json({ error: `প্রমোশনের target session অবশ্যই ${sourceYear ? sourceYear + 1 : 'পরবর্তী'} শিক্ষাবর্ষ হতে হবে।` });
    }
    if (ev.session_name && Number(String(ev.session_name).match(/(19|20)\d{2}/)?.[0]) !== Number(ev.year)) {
      return res.status(400).json({ error: `পরীক্ষার বছর ${ev.year} এবং একাডেমিক সেশন ${ev.session_name} মিলছে না। পরীক্ষা/সেশন ঠিক করে আবার চেষ্টা করুন।` });
    }

    // Determine if this event type is a promotion source for this class
    const isClass10 = /class\s*10/i.test(String(cls.name || ''));
    const needKind = isClass10 ? 'test' : 'annual';
    if (String(ev.exam_kind) !== needKind) {
      return res.status(400).json({ error: `This event type (${ev.exam_kind}) is not a promotion source for ${cls.name}` });
    }

    // Get promotion rule for this class/exam_type
    const [[rule]] = await pool.query(
      `SELECT * FROM promotion_rules WHERE class_id=? AND exam_type=?`,
      [cid, needKind]
    );

    const graceFailed = rule ? Number(rule.grace_failed_subjects) : 0;
    let configuredMandatory = rule?.mandatory_subjects || [];
    if (typeof configuredMandatory === 'string') {
      try { configuredMandatory = JSON.parse(configuredMandatory); } catch (_) { configuredMandatory = [configuredMandatory]; }
    }
    if (!Array.isArray(configuredMandatory)) configuredMandatory = [];
    const [mandatoryRows] = await pool.query(
      `SELECT sub.name FROM mandatory_pass mp JOIN subjects sub ON sub.id=mp.subject_id WHERE mp.class_id=?`, [cid]);
    const mandatorySubjects = [...new Set([...configuredMandatory, ...mandatoryRows.map(r => r.name)])];
    const minGpa = rule ? Number(rule.min_passing_gpa) : 2.0;
    const allowConditional = rule ? Number(rule.allow_conditional) === 1 : true;

// Destination class: reuse the shared resolver so this route follows the
    // exact same rule as /promote/execute (Class 10 → matching SSC Batch row,
    // Class N → Class N+1 with the same section/group). The old inline
    // "Class N+1 (group)" lookup never matched a Class 10 row, so
    // target_class_id stayed NULL and execute could not move anybody.
    const dest = await promotionDestination(pool, cls);

    // Get all students in class
    const [students] = await pool.query(
      `SELECT s.id, s.name, s.student_code, s.roll, c.group_name AS student_group_name, c.section AS student_section
       FROM students s JOIN classes c ON c.id = s.class_id
       WHERE s.class_id=? AND (s.status IS NULL OR s.status='active') ORDER BY s.roll`,
      [cid]
    );

    const review = [];
    for (const s of students) {
      const r = await computeResult(s.id, eid);
      if (!r) {
        review.push({
          student_id: s.id, name: s.name, student_code: s.student_code, roll: s.roll,
          status: 'pending_results', decision: null, eligible: false,
          final_gpa: null, failed_subjects: [], mandatory_failed: [],
          reason: 'No results in this event'
        });
        continue;
      }

      const failedNames = (r.families || [])
        .filter(f => !f.is_optional && (f.letter_grade === 'F' || f.absent === true))
        .map(f => f.subject);
      const mandatoryFailed = failedNames.filter(f => mandatorySubjects.some(m => String(m).trim().toLowerCase() === f.trim().toLowerCase()));
      const failCount = failedNames.length;

      let status, decision, eligible = false, reason = '';
      if (r.result_status === 'ABSENT' || !(r.families || []).length) {
        status = 'not_eligible'; decision = 'retained'; eligible = false; reason = 'Absent or no marks';
      } else if (mandatoryFailed.length > 0) {
        status = 'not_eligible'; decision = 'retained'; eligible = false; reason = `Mandatory subject failed: ${mandatoryFailed.join(', ')}`;
      } else if (Number(r.final_gpa || 0) < minGpa) {
        status = 'not_eligible'; decision = 'retained'; eligible = false; reason = `GPA ${r.final_gpa} below minimum ${minGpa}`;
      } else if (failCount === 0) {
        status = 'eligible'; decision = 'promoted'; eligible = true; reason = 'All subjects passed';
      } else if (failCount <= graceFailed && allowConditional) {
        status = 'conditional'; decision = 'conditional'; eligible = true; reason = `Failed ${failCount} subject(s) within grace limit`;
      } else {
        status = 'not_eligible'; decision = 'retained'; eligible = false; reason = `Failed ${failCount} subject(s) exceeds grace`;
      }

      review.push({
        student_id: s.id, name: s.name, student_code: s.student_code, roll: s.roll,
        status, decision, eligible, reason,
        final_gpa: r.final_gpa, total_marks: r.total_marks,
        failed_subjects: failedNames, mandatory_failed: mandatoryFailed,
        grace_used: failCount > 0 && eligible ? 1 : 0
      });
    }

    // Save/update student_promotion_status
    const destClassId = dest && dest.id ? dest.id : null;
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      for (const r of review) {
        await conn.query(
          `INSERT INTO student_promotion_status (student_id, from_class_id, target_class_id, target_session_id, source_event_id, status, decision, eligible, final_gpa, failed_subjects, mandatory_failed_subjects, grace_used, reviewed_by, reviewed_at, created_at, updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,NOW(),NOW(),NOW())
           ON CONFLICT (student_id, target_session_id) DO UPDATE SET
             status=EXCLUDED.status, decision=EXCLUDED.decision, eligible=EXCLUDED.eligible,
             target_class_id=EXCLUDED.target_class_id, final_gpa=EXCLUDED.final_gpa,
             failed_subjects=EXCLUDED.failed_subjects, mandatory_failed_subjects=EXCLUDED.mandatory_failed_subjects,
             grace_used=EXCLUDED.grace_used, updated_at=NOW()`,
          [r.student_id, cid, destClassId, targetSessionId, eid, r.status, r.decision, r.eligible ? true : false, r.final_gpa, r.failed_subjects, r.mandatory_failed, r.grace_used || 0, req.user.id]
        );
        await conn.query(
          `INSERT INTO promotion_audit_log (student_id, action, from_status, to_status, from_class_id, to_class_id, target_session_id, admin_id, reason, metadata, created_at)
           VALUES (?, 'eligible_calculated', NULL, ?, ?, ?, ?, ?, ?, ?, NOW())`,
          [r.student_id, r.status, cid, destClassId, targetSessionId, req.user.id, r.reason, JSON.stringify({ reason: r.reason, fail_count: r.failed_subjects?.length || 0 })]
        );
      }
      await conn.commit();
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }

    res.json({ event: ev, class: cls, target_session: targetSession, kind: needKind, dest_class: dest || null, review, summary: { total: review.length, eligible: review.filter(r => r.eligible).length, conditional: review.filter(r => r.status === 'conditional').length, not_eligible: review.filter(r => !r.eligible).length } });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Get promotion status for all students (with filters)
router.get('/promotion/status', async (req, res) => {
  try {
    const { session_id, class_id, status, target_session_id } = req.query;
    let where = 'WHERE 1=1';
    const params = [];
    if (session_id) { where += ' AND sps.target_session_id = ?'; params.push(session_id); }
    if (class_id) { where += ' AND sps.from_class_id = ?'; params.push(class_id); }
    if (status) { where += ' AND sps.status = ?'; params.push(status); }
    if (target_session_id) { where += ' AND sps.target_session_id = ?'; params.push(target_session_id); }

    const [rows] = await pool.query(
      `SELECT sps.*, s.name, s.student_code, s.roll, c.name AS from_class_name, c.section AS from_section, c.group_name AS from_group,
              tc.name AS target_class_name, tc.section AS target_section, tc.group_name AS target_group,
              ss.name AS target_session_name, ev.name AS source_event_name
       FROM student_promotion_status sps
       JOIN students s ON s.id = sps.student_id
       JOIN classes c ON c.id = sps.from_class_id
       LEFT JOIN classes tc ON tc.id = sps.target_class_id
       LEFT JOIN sessions ss ON ss.id = sps.target_session_id
       LEFT JOIN exam_events ev ON ev.id = sps.source_event_id
       ${where}
       ORDER BY c.name, c.section, s.roll`,
      params
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Update individual student promotion status (admin override)
router.put('/promotion/status/:studentId', async (req, res) => {
  try {
    const studentId = Number(req.params.studentId);
    const { status, decision, target_class_id, target_session_id, admin_note } = req.body || {};
    if (!studentId) return res.status(400).json({ error: 'studentId required' });
    if (!target_session_id) return res.status(400).json({ error: 'target_session_id required' });

    const [[sps]] = await pool.query(
      'SELECT * FROM student_promotion_status WHERE student_id=? AND target_session_id=?',
      [studentId, target_session_id]);
    if (!sps) return res.status(404).json({ error: 'Student promotion status not found' });

    const fromStatus = sps.status;
    const updates = ['updated_at = NOW()'];
    const params = [];
    if (status) { updates.push('status = ?'); params.push(status); }
    // NOTE: the decision was pushed twice before (once here, once below),
    // which produced "UPDATE ... SET decision = $1, decision = $2" and made
    // PostgreSQL reject the statement. It is now set exactly once.
    if (decision) { updates.push('decision = ?'); params.push(decision); }
    if (target_class_id) { updates.push('target_class_id = ?'); params.push(target_class_id); }
    if (target_session_id) { updates.push('target_session_id = ?'); params.push(target_session_id); }
    if (admin_note !== undefined) { updates.push('admin_note = ?'); params.push(admin_note); }
    updates.push('reviewed_by = ?'); params.push(req.user.id);
    updates.push('reviewed_at = NOW()');
    if (status === 'approved') {
      updates.push('approved_by = ?'); params.push(req.user.id);
      updates.push('approved_at = NOW()');
    }
    params.push(studentId, target_session_id);

    await pool.query(`UPDATE student_promotion_status SET ${updates.join(', ')} WHERE student_id = ? AND target_session_id = ?`, params);

    await pool.query(
      `INSERT INTO promotion_audit_log (student_id, action, from_status, to_status, from_class_id, target_session_id, admin_id, reason, metadata, created_at)
       VALUES (?, 'admin_override', ?, ?, NULL, ?, ?, ?, ?, NOW())`,
      [studentId, fromStatus, status, target_session_id, req.user.id, admin_note || 'Admin override', JSON.stringify({ decision, target_class_id })]
    );

    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Bulk approve promotions
router.post('/promotion/bulk-approve', async (req, res) => {
  try {
    const { student_ids, target_session_id } = req.body || {};
    if (!Array.isArray(student_ids) || !student_ids.length || !target_session_id) {
      return res.status(400).json({ error: 'student_ids[] and target_session_id required' });
    }

    const conn = await pool.getConnection();
    let approved = 0, skipped = 0;
    try {
      await conn.beginTransaction();
      for (const studentId of student_ids) {
        const [[sps]] = await conn.query('SELECT * FROM student_promotion_status WHERE student_id=? AND target_session_id=?', [studentId, target_session_id]);
        if (!sps || (!sps.eligible && sps.status !== 'conditional')) {
          skipped++;
          continue;
        }
        await conn.query(
          `UPDATE student_promotion_status SET status='approved', decision='promoted', approved_by=?, approved_at=NOW(), updated_at=NOW()
           WHERE student_id=? AND target_session_id=?`,
          [req.user.id, studentId, target_session_id]
        );
        await conn.query(
          `INSERT INTO promotion_audit_log (student_id, action, from_status, to_status, target_session_id, admin_id, reason, metadata, created_at)
           VALUES (?, 'bulk_approved', ?, 'approved', ?, ?, ?, ?, NOW())`,
          [studentId, sps.status, target_session_id, req.user.id, 'Bulk approval', JSON.stringify({ target_class_id: sps.target_class_id })]
        );
        approved++;
      }
      await conn.commit();
      res.json({ ok: true, approved, skipped });
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Bulk retain students
router.post('/promotion/bulk-retain', async (req, res) => {
  try {
    const { student_ids, target_session_id, reason } = req.body || {};
    if (!Array.isArray(student_ids) || !student_ids.length || !target_session_id) {
      return res.status(400).json({ error: 'student_ids[] and target_session_id required' });
    }

    const conn = await pool.getConnection();
    let retained = 0;
    try {
      await conn.beginTransaction();
      for (const studentId of student_ids) {
        const [[sps]] = await conn.query(
          'SELECT * FROM student_promotion_status WHERE student_id=? AND target_session_id=?',
          [studentId, target_session_id]
        );
        if (!sps) continue;
        // Use the SAME connection as the transaction, otherwise the UPDATE
        // runs on a different pooled connection outside the transaction.
        await conn.query(
          `UPDATE student_promotion_status SET status='retained', decision='retained', updated_at=NOW()
           WHERE student_id=? AND target_session_id=?`,
          [studentId, target_session_id]
        );
        await conn.query(
          `INSERT INTO promotion_audit_log (student_id, action, from_status, to_status, target_session_id, admin_id, reason, metadata, created_at)
           VALUES (?, 'bulk_retained', ?, 'retained', ?, ?, ?, ?, NOW())`,
          [studentId, sps.status, target_session_id, req.user.id, reason || 'Bulk retain', JSON.stringify({})]
        );
        retained++;
      }
      await conn.commit();
      res.json({ ok: true, retained });
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Execute promotion - move students to next class
router.post('/promotion/execute', async (req, res) => {
  try {
    const { target_session_id } = req.body || {};
    if (!target_session_id) return res.status(400).json({ error: 'target_session_id required' });

    // Get all approved students for this session.
    // NOTE: the join aliases matter — the old version read `p.group_name`,
    // `p.to_section` and `p.from_section`, none of which exist on
    // student_promotion_status, so the promotion row was written with an
    // empty group and the student's section was wiped.
    const [approved] = await pool.query(
      `SELECT sps.*, s.name, s.roll, s.section AS student_section,
              c.name AS from_class_name, c.section AS from_section, c.group_name AS from_group,
              tc.name AS target_class_name, tc.section AS target_section,
              tc.group_name AS target_group, tc.id AS target_class_id
       FROM student_promotion_status sps
       JOIN students s ON s.id = sps.student_id
       JOIN classes c ON c.id = sps.from_class_id
       LEFT JOIN classes tc ON tc.id = sps.target_class_id
       WHERE sps.target_session_id=? AND sps.status='approved' AND sps.decision='promoted'
       ORDER BY tc.id, s.roll`,
      [target_session_id]
    );

    if (!approved.length) return res.json({ ok: true, moved: 0, message: 'No approved students to promote' });

    // Students without a resolvable destination class must never be moved —
    // otherwise class_id would be set to NULL and the student would vanish
    // from every roster. They are recorded as retained instead.
    const movable = approved.filter(p => p.target_class_id);
    const stuck = approved.filter(p => !p.target_class_id);
    if (!movable.length) {
      return res.json({ ok: true, moved: 0, retained: stuck.length, message: 'No destination class mapped for the approved students' });
    }

    const conn = await pool.getConnection();
    let moved = 0;
    const movedRecords = [];
    try {
      await conn.beginTransaction();
      // Group by target class to assign rolls efficiently
      const byTarget = {};
      for (const p of movable) {
        const tcId = p.target_class_id;
        if (!byTarget[tcId]) byTarget[tcId] = [];
        byTarget[tcId].push(p);
      }

      for (const [tcId, students] of Object.entries(byTarget)) {
        const [[tc]] = await conn.query('SELECT id, name, section, group_name FROM classes WHERE id=?', [tcId]);
        if (!tc) continue; // destination vanished — skip this group
        const [[maxRoll]] = await conn.query('SELECT COALESCE(MAX(roll),0) AS m FROM students WHERE class_id=?', [tcId]);
        let roll = Number(maxRoll.m || 0);
        const targetSection = tc.section || tc.group_name || null;

        for (const p of students) {
          roll++;
          await conn.query(
            'UPDATE students SET class_id=?, section=?, roll=?, session_id=?, status=\'active\' WHERE id=?',
            [tcId, targetSection, roll, target_session_id, p.student_id]
          );
          // Update promotion record
          await conn.query(
            `INSERT INTO promotions (student_id, event_id, class_id, group_name, from_class, to_class,
                                     from_section, to_section, promoted_roll, decision, final_gpa,
                                     recorded_by, passing_year, destination_session_id, created_at)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,NOW())
             ON CONFLICT (event_id, student_id) DO UPDATE SET
               to_class=EXCLUDED.to_class, from_section=EXCLUDED.from_section, to_section=EXCLUDED.to_section,
               promoted_roll=EXCLUDED.promoted_roll, decision=EXCLUDED.decision,
               final_gpa=EXCLUDED.final_gpa, destination_session_id=EXCLUDED.destination_session_id,
               created_at=NOW()`,
            [p.student_id, p.source_event_id, p.from_class_id, p.from_group || p.from_section || '',
             p.from_class_name, tc.name, p.from_section || null, targetSection, roll, 'promoted',
             p.final_gpa, req.user.id, null, target_session_id]
          );
          await conn.query(
            `INSERT INTO promotion_audit_log (student_id, action, from_status, to_status, from_class_id, to_class_id, target_session_id, admin_id, reason, metadata, created_at)
             VALUES (?, 'approved', 'approved', 'promoted', ?, ?, ?, ?, ?, ?, NOW())`,
            [p.student_id, p.from_class_id, p.target_class_id, target_session_id, req.user.id, 'Promotion executed', JSON.stringify({ to_class: tc.name, roll: roll })]
          );
          // Update student_promotion_status
          await conn.query(
            `UPDATE student_promotion_status SET status='promoted', updated_at=NOW() WHERE student_id=? AND target_session_id=?`,
            [p.student_id, target_session_id]
          );
          movedRecords.push({
            student_id: p.student_id,
            source_event_id: p.source_event_id,
            from_class_id: p.from_class_id,
            target_class_id: tcId,
            target_class_name: tc.name,
            target_section: targetSection,
            old_roll: Number(p.roll || 0),
          });
          moved++;
        }
      }

      // Final roster rule: new arrivals first by source-exam merit; current
      // students who repeat the class go after them, ranked by their own exam
      // marks. Other active records keep their old order between these groups.
      const movedById = new Map(movedRecords.map(r => [Number(r.student_id), r]));
      const targetClassIds = [...new Set(movedRecords.map(r => Number(r.target_class_id)))];
      const finalRollByStudent = new Map();
      for (const targetClassId of targetClassIds) {
        const [roster] = await conn.query(
          `SELECT s.id, s.name, s.roll, s.status AS student_status,
                  sps.from_class_id, sps.status AS promotion_status, sps.decision,
                  sps.source_event_id, sps.final_gpa
             FROM students s
             LEFT JOIN student_promotion_status sps
               ON sps.student_id=s.id AND sps.target_session_id=?
            WHERE s.class_id=? ORDER BY s.roll, s.id`,
          [target_session_id, targetClassId]);
        const rankedRoster = [];
        for (const row of roster) {
          const incoming = movedById.get(Number(row.id));
          const repeats = !incoming && Number(row.from_class_id) === targetClassId &&
            (row.decision === 'retained' || row.promotion_status === 'retained' || row.promotion_status === 'not_eligible');
          const eventId = incoming?.source_event_id || row.source_event_id;
          let percentage = 0;
          let gpa = Number(row.final_gpa || 0);
          if (eventId) {
            const result = await computeResult(Number(row.id), Number(eventId));
            if (result) {
              const full = Number(result.total_full || 0);
              percentage = full > 0 ? Number(result.total_marks || 0) / full : 0;
              gpa = Number(result.final_gpa || gpa);
            }
          }
          rankedRoster.push({
            ...row,
            priority: incoming ? 0 : repeats ? 2 : (row.student_status == null || row.student_status === 'active') ? 1 : 3,
            percentage,
            gpa,
            previousRoll: Number(incoming?.old_roll ?? row.roll ?? 0),
          });
        }
        rankedRoster.sort((a, b) =>
          a.priority - b.priority ||
          ((a.priority === 0 || a.priority === 2) ? (b.percentage - a.percentage || b.gpa - a.gpa) : 0) ||
          a.previousRoll - b.previousRoll ||
          String(a.name || '').localeCompare(String(b.name || ''), 'bn') ||
          Number(a.id) - Number(b.id));

        const maxOldRoll = Math.max(0, ...rankedRoster.map(r => Number(r.roll || 0)));
        const offset = maxOldRoll + rankedRoster.length + 1000;
        await conn.query('UPDATE students SET roll=roll+? WHERE class_id=?', [offset, targetClassId]);
        let nextRoll = 0;
        for (const row of rankedRoster) {
          nextRoll++;
          await conn.query(
            `UPDATE students SET roll=?, session_id=CASE WHEN status IS NULL OR status='active' THEN ? ELSE session_id END WHERE id=?`,
            [nextRoll, target_session_id, row.id]);
          finalRollByStudent.set(Number(row.id), nextRoll);
          const incoming = movedById.get(Number(row.id));
          if (incoming) {
            await conn.query(
              `UPDATE promotions SET promoted_roll=? WHERE student_id=? AND event_id=?`,
              [nextRoll, row.id, incoming.source_event_id]);
          }
        }
      }

      // Notify guardians only after final rolls have been assigned.
      for (const p of movedRecords) {
        const roll = finalRollByStudent.get(Number(p.student_id));
        await conn.query(
          `INSERT INTO notifications (student_id, class_id, title, body, type, target_type, related_id, created_by, created_at)
           VALUES (?,?,?,?,?,?,?,?,NOW())`,
          [p.student_id, p.target_class_id, 'Promotion — উত্তীর্ণ',
           `অভিনন্দন! আপনি ${p.target_class_name}-এ উত্তীর্ণ হয়েছেন। নতুন রোল: ${roll}`,
           'promotion', 'students', p.source_event_id, req.user.id]
        );
      }

      // Students approved without a destination class: keep them in place
      // and mark them retained so the state stays consistent.
      for (const p of stuck) {
        await conn.query(
          `UPDATE student_promotion_status SET status='retained', decision='retained', admin_note=?, updated_at=NOW()
           WHERE student_id=? AND target_session_id=?`,
          ['Destination class could not be resolved', p.student_id, target_session_id]
        );
        await conn.query(
          `INSERT INTO promotion_audit_log (student_id, action, from_status, to_status, from_class_id, target_session_id, admin_id, reason, metadata, created_at)
           VALUES (?, 'retained', 'approved', 'retained', ?, ?, ?, ?, ?, NOW())`,
          [p.student_id, p.from_class_id, target_session_id, req.user.id, 'Destination class could not be resolved', JSON.stringify({})]
        );
      }

      await conn.commit();
      res.json({ ok: true, moved, retained: stuck.length });
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Get promotion history/audit log
router.get('/promotion/history', async (req, res) => {
  try {
    const { student_id, session_id, class_id, action, limit } = req.query;
    let where = 'WHERE 1=1';
    const params = [];
    if (student_id) { where += ' AND pal.student_id = ?'; params.push(student_id); }
    if (session_id) { where += ' AND pal.target_session_id = ?'; params.push(session_id); }
    if (class_id) { where += ' AND pal.from_class_id = ?'; params.push(class_id); }
    if (action) { where += ' AND pal.action = ?'; params.push(action); }

    const lim = limit ? Number(limit) : 100;
    params.push(lim);

    const [rows] = await pool.query(
      `SELECT pal.*, s.name AS student_name, s.student_code, s.roll,
              fc.name AS from_class_name, tc.name AS to_class_name,
              ss.name AS session_name, u.name AS admin_name
       FROM promotion_audit_log pal
       JOIN students s ON s.id = pal.student_id
       LEFT JOIN classes fc ON fc.id = pal.from_class_id
       LEFT JOIN classes tc ON tc.id = pal.to_class_id
       LEFT JOIN sessions ss ON ss.id = pal.target_session_id
       LEFT JOIN users u ON u.id = pal.admin_id
       ${where}
       ORDER BY pal.created_at DESC LIMIT ?`,
      params
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Get promotion report
router.get('/promotion/report', async (req, res) => {
  try {
    const { session_id, class_id, format } = req.query;
    if (!session_id) return res.status(400).json({ error: 'session_id required' });

    const [rows] = await pool.query(
      `SELECT sps.*, s.name, s.student_code, s.roll, s.name,
              c.name AS from_class_name, c.section AS from_section, c.group_name AS from_group,
              tc.name AS target_class_name, tc.section AS target_section, tc.group_name AS target_group,
              ev.name AS source_event_name
       FROM student_promotion_status sps
       JOIN students s ON s.id = sps.student_id
       JOIN classes c ON c.id = sps.from_class_id
       LEFT JOIN classes tc ON tc.id = sps.target_class_id
       LEFT JOIN exam_events ev ON ev.id = sps.source_event_id
       WHERE sps.target_session_id = ?
       ORDER BY c.name, c.section, s.roll`,
      [session_id]
    );

    if (format === 'excel') {
      // Return CSV format
      const headers = ['Student Name', 'Student Code', 'Roll', 'From Class', 'From Section', 'From Group', 'Target Class', 'Target Section', 'Target Group', 'Status', 'Decision', 'Final GPA', 'Source Event'];
      const csv = [headers.join(',')];
      for (const r of rows) {
        csv.push([r.name, r.student_code, r.roll, r.from_class_name, r.from_section, r.from_group, r.target_class_name, r.target_section, r.target_group, r.status, r.decision, r.final_gpa, r.source_event_name].map(v => `"${v ?? ''}"`).join(','));
      }
      res.setHeader('Content-Type', 'text/csv');
      res.setHeader('Content-Disposition', `attachment; filename="promotion_report_${session_id}.csv"`);
      return res.send(csv.join('\n'));
    }

    res.json({ total: rows.length, data: rows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Get next class mapping for all classes
router.get('/promotion/next-class-map', async (req, res) => {
  try {
    const [classes] = await pool.query('SELECT id, name, section, group_name FROM classes ORDER BY name, section, group_name');
    const mapping = [];
    for (const c of classes) {
      // CAST every placeholder to text: PostgreSQL cannot infer the type of
      // `$2` when it is only used inside `IS NOT NULL`, which made this
      // whole endpoint fail with "could not determine data type of parameter".
      const [[dest]] = await pool.query(
        `SELECT id, name, section, group_name FROM classes
         WHERE name = 'Class ' || (CAST(SUBSTRING(CAST($1 AS text) FROM '\d+') AS INT) + 1) ||
               CASE WHEN CAST($2 AS text) IS NOT NULL THEN ' (' || CAST($2 AS text) || ')'
                    ELSE ' (' || CAST($3 AS text) || ')' END
         ORDER BY id LIMIT 1`,
        [c.name, c.group_name, c.section]
      );
      mapping.push({
        from_class_id: c.id,
        from_class: c.name,
        from_section: c.section,
        from_group: c.group_name,
        to_class_id: dest?.id || null,
        to_class: dest?.name || null,
        to_section: dest?.section || null,
        to_group: dest?.group_name || null,
        has_destination: !!dest
      });
    }
    res.json(mapping);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Update next class mapping
router.put('/promotion/next-class-map', async (req, res) => {
  try {
    const { mappings } = req.body || {};
    if (!Array.isArray(mappings)) return res.status(400).json({ error: 'mappings[] required' });

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      for (const m of mappings) {
        if (m.from_class_id && m.to_class_id) {
          await conn.query(
            `UPDATE classes SET name = (SELECT name FROM classes WHERE id = $1) WHERE id = $2`,
            [m.to_class_id, m.from_class_id]
          );
        }
      }
      await conn.commit();
      res.json({ ok: true });
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Get promotion rules for a specific class
router.get('/admin/promotion-rules/class/:classId', async (req, res) => {
  try {
    const cid = Number(req.params.classId);
    const [rows] = await pool.query(
      `SELECT * FROM promotion_rules WHERE class_id=? ORDER BY exam_type`,
      [cid]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;
