const router = require('express').Router();
const bcrypt = require('bcryptjs');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const pool = require('../db');
const { auth } = require('../middleware/auth');
const { queuePush, getAllGuardianTokens, getGuardianTokens } = require('../fcm');
const { validateStudent, validateMarksValue } = require('../validate');

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
  const { name, dob, roll, class_id, religion, guardian_id, guardian_name, guardian_phone, guardian_email, address, father_name, mother_name, birth_cert_no } = req.body || {};
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
      `INSERT INTO students (student_code, name, dob, roll, class_id, religion, guardian_id, guardian_name, guardian_phone, guardian_email, address, father_name, mother_name, birth_cert_no)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [String(student_code).trim(), name, dob || null, roll, class_id, religion || null, guardian_id || null, guardian_name || null, guardian_phone || null, guardian_email || null, address || null, father_name || null, mother_name || null, birth_cert_no || null]
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
  const { student_code, name, dob, roll, class_id, religion, guardian_id, guardian_name, guardian_phone, guardian_email, address, father_name, mother_name, birth_cert_no } = req.body || {};
  try {
    const [[cur]] = await pool.query('SELECT student_code, class_id FROM students WHERE id=?', [req.params.id]);
    if (!cur) return res.status(404).json({ error: 'Student not found' });
    const code = student_code !== undefined && student_code !== '' ? String(student_code).trim() : cur.student_code;
    await pool.query(
      `UPDATE students SET student_code=?, name=?, dob=?, roll=?, class_id=?, religion=?, guardian_id=?, guardian_name=?, guardian_phone=?, guardian_email=?, address=?, father_name=?, mother_name=?, birth_cert_no=? WHERE id=?`,
      [code, name, dob || null, roll, class_id, religion || null, guardian_id || null, guardian_name || null, guardian_phone || null, guardian_email || null, address || null, father_name || null, mother_name || null, birth_cert_no || null, req.params.id]
    );
    await autoAssignReligionSubjects(req.params.id, class_id, religion, req.user.id);
    await log(req.user.id, 'student_update', 'Updated student id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/students/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM students WHERE id=?', [req.params.id]);
    await log(req.user.id, 'student_delete', 'Deleted student id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
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
       ORDER BY sub.sort_order NULLS LAST, sub.name`,
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
       WHERE ss.student_id=? ORDER BY sub.sort_order NULLS LAST, sub.name`,
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
      "SELECT id, username, name, email, phone, active, is_class_teacher, designation, sort_order FROM users WHERE role='teacher' ORDER BY sort_order ASC, name"
    );
    for (const t of rows) {
      const [cls] = await pool.query(
        'SELECT id FROM classes WHERE teacher_id = ?', [t.id]
      );
      t.class_teacher_ids = cls.map(c => c.id);
      t.class_teacher = typeof t.is_class_teacher === 'string'
        ? JSON.parse(t.is_class_teacher || '[]')
        : (t.is_class_teacher || []);
    }
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
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
    if (prev[0]?.teacher_id) await refreshClassTeacher(prev[0].teacher_id);
    await log(req.user.id, 'class_delete', 'Deleted class id ' + req.params.id);
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
  const { name, class_id, teacher_id, full_marks, pass_marks, group_name, is_optional, excluded_from_gpa, cq_full, mcq_full, practical_full, subject_code, is_fourth_subject, is_elective, sort_order } = req.body || {};
  if (!name || !class_id) return res.status(400).json({ error: 'name and class_id required' });
  try {
    const [result] = await pool.query(
      `INSERT INTO subjects (name, class_id, teacher_id, full_marks, pass_marks, group_name, is_optional, excluded_from_gpa, cq_full, mcq_full, practical_full, subject_code, is_fourth_subject, is_elective, sort_order)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [name, class_id, teacher_id || null, full_marks || 100, pass_marks || null, group_name || 'Compulsory',
       is_optional ? 1 : 0, excluded_from_gpa ? 1 : 0, cq_full || null, mcq_full || null, practical_full || null, subject_code || null,
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
  const { name, class_id, teacher_id, full_marks, pass_marks, group_name, is_optional, excluded_from_gpa, cq_full, mcq_full, practical_full, subject_code, is_fourth_subject, is_elective, sort_order } = req.body || {};
  try {
    await pool.query(
      `UPDATE subjects SET name=?, class_id=?, teacher_id=?, full_marks=?, pass_marks=?, group_name=?, is_optional=?, excluded_from_gpa=?, cq_full=?, mcq_full=?, practical_full=?, subject_code=?, is_fourth_subject=?, is_elective=?, sort_order=? WHERE id=?`,
      [name, class_id, teacher_id || null, full_marks || 100, pass_marks || null, group_name || 'Compulsory',
       is_optional ? 1 : 0, excluded_from_gpa ? 1 : 0, cq_full || null, mcq_full || null, practical_full || null, subject_code || null,
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

router.post('/exams', async (req, res) => {
  const { name, exam_type, class_id, subject_id, exam_date, event_id } = req.body || {};
  if (!name || !class_id || !subject_id) return res.status(400).json({ error: 'name, class_id, subject_id required' });
  try {
    const [[subj]] = await pool.query('SELECT id, class_id FROM subjects WHERE id=?', [subject_id]);
    if (!subj) return res.status(404).json({ error: 'Subject not found' });
    if (Number(subj.class_id) !== Number(class_id)) {
      return res.status(400).json({ error: 'subject_id does not belong to the selected class' });
    }
    const [result] = await pool.query(
      'INSERT INTO exams (name, exam_type, class_id, subject_id, source, created_by, exam_date, event_id) VALUES (?,?,?,?,?,?,?,?)',
      [name, exam_type || 'class_test', class_id, subject_id, 'admin', req.user.id, exam_date || null, event_id || null]
    );
    await log(req.user.id, 'exam_create', 'Created exam ' + name);
    res.status(201).json({ id: result.insertId });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/exams/:id', async (req, res) => {
  const { name, exam_type, class_id, subject_id, exam_date, event_id } = req.body || {};
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
    if (event_id !== undefined) { updates.push('event_id=?'); params.push(event_id ? Number(event_id) : null); }
    if (updates.length === 0) return res.status(400).json({ error: 'Nothing to update' });
    params.push(req.params.id);
    await pool.query(`UPDATE exams SET ${updates.join(', ')} WHERE id=?`, params);
    await log(req.user.id, 'exam_edit', 'Edited exam ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/exams/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM exams WHERE id=?', [req.params.id]);
    res.json({ ok: true });
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
  const { marks, total } = req.body || {};
  if (marks === undefined) return res.status(400).json({ error: 'marks required' });
  try {
    // Preserve the existing total when not explicitly provided (never silently reset to 100).
    const [[mark]] = await pool.query('SELECT total FROM marks WHERE id=?', [req.params.id]);
    if (!mark) return res.status(404).json({ error: 'Mark not found' });
    const effectiveTotal = total !== undefined ? total : mark.total;
    const vErr = validateMarksValue(marks, effectiveTotal);
    if (vErr) return res.status(400).json({ error: vErr });
    await pool.query('UPDATE marks SET marks=?, total=?, edit_until=NULL WHERE id=?', [Number(marks), effectiveTotal, req.params.id]);
    await log(req.user.id, 'mark_edit', 'Admin edited mark id ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/marks/:id/unlock', async (req, res) => {
  try {
    await pool.query('UPDATE marks SET edit_until = DATE_ADD(NOW(), INTERVAL 10 MINUTE) WHERE id=?', [req.params.id]);
    await log(req.user.id, 'mark_unlock', 'Unlocked mark id ' + req.params.id);
    res.json({ ok: true });
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
  const { date, class_id } = req.query;
  try {
    let query = `
      SELECT a.id, a.student_id, s.name AS student_name, s.roll, a.status, a.remark, a.date,
             c.id AS class_id, c.name AS class_name, c.section
      FROM attendance a JOIN students s ON a.student_id = s.id JOIN classes c ON s.class_id = c.id
      WHERE 1=1`;
    const params = [];
    if (date) { query += ' AND a.date = ?'; params.push(date); }
    if (class_id) { query += ' AND c.id = ?'; params.push(class_id); }
    query += ' ORDER BY a.date DESC, s.roll';
    const [rows] = await pool.query(query, params);
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
      'SELECT e.id, e.class_id, e.exam_date, sub.full_marks AS subject_full FROM exams e JOIN subjects sub ON e.subject_id=sub.id WHERE e.id=?',
      [exam_id]);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    if (exam.exam_date) {
      const d = exam.exam_date instanceof Date ? exam.exam_date.toISOString().slice(0, 10) : String(exam.exam_date).slice(0, 10);
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

router.post('/promote/review', async (req, res) => {
  const { class_id, session_id } = req.body || {};
  if (!class_id) return res.status(400).json({ error: 'class_id is required' });
  const conn = await pool.getConnection();
  try {
    const examClause = session_id ? 'AND e.session_id=?' : '';
    const examParams = session_id ? [class_id, session_id] : [class_id];
    const [exams] = await conn.query(
      `SELECT e.id, e.subject_id FROM exams e
        WHERE e.class_id=? AND e.exam_type IN ('midterm','final') ${examClause}`,
      examParams
    );
    if (!exams.length) return res.status(400).json({ error: 'No promotion exams found for this class' });
    const examIds = exams.map(e => e.id);
    const ph = examIds.map(() => '?').join(',');
    const [students] = await conn.query(
      `SELECT s.id, s.student_code, s.name, s.roll,
              ROUND(SUM(m.marks), 2) AS total_marks,
              SUM(CASE WHEN m.marks < COALESCE(sub.pass_marks, m.total * 0.5, 33) THEN 1 ELSE 0 END) AS fail_count,
              ROUND(SUM(m.marks) / COUNT(DISTINCT m.subject_id), 2) AS avg_per_subject
         FROM students s
         JOIN marks m ON m.student_id = s.id
         JOIN exams e ON e.id = m.exam_id
         JOIN subjects sub ON sub.id = e.subject_id
        WHERE s.class_id=? AND e.id IN (${ph})
        GROUP BY s.id, s.student_code, s.name, s.roll
        ORDER BY total_marks DESC`,
      [class_id, ...examIds]
    );
    const direct = students.filter(x => x.fail_count === 0);
    const conditional = students.filter(x => x.fail_count >= 1 && x.fail_count <= 2);
    const retained = students.filter(x => x.fail_count >= 3);
    await log(req.user.id, 'promote_review', `Reviewed promotion for class ${class_id} (${students.length} students)`);
    res.json({ total: students.length, direct, conditional, retained, exam_ids: examIds });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
  finally { conn.release(); }
});

router.post('/promote/execute', async (req, res) => {
  const { class_id, session_id, students } = req.body || {};
  if (!class_id || !Array.isArray(students) || !students.length) {
    return res.status(400).json({ error: 'class_id and students[] are required' });
  }
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    let promoted = 0, conditional = 0, noteCount = 0;
    for (const st of students) {
      if (!st || !st.id) continue;
      const decision = st.decision === 'conditional' ? 'promoted' : (st.decision === 'retained' ? 'retained' : 'promoted');
      const admin_note = (st.admin_note || '').trim();
      const [nextClass] = await conn.query(
        `SELECT id FROM classes WHERE session_id=? AND name=(SELECT name FROM classes WHERE id=?) AND id > ? ORDER BY id LIMIT 1`,
        [session_id || null, class_id, class_id]
      );
      const to_class_id = nextClass.length ? nextClass[0].id : null;
      await conn.query(
        `INSERT INTO promotion_history
           (student_id, from_class_id, to_class_id, final_gpa, decision, session_from, session_to, admin_note)
         VALUES (?,?,?,?,?,?,?,?)`,
        [st.id, class_id, to_class_id, st.final_gpa ? Number(st.final_gpa) : null, decision,
         String(session_id || ''), String(session_id || ''), admin_note || null]
      );
      if (to_class_id && decision === 'promoted') {
        await conn.query('UPDATE students SET class_id=?, section=NULL WHERE id=?', [to_class_id, st.id]);
        promoted++;
      } else if (decision === 'retained') {
        conditional++;
      }
      if (admin_note) noteCount++;
    }
    if (promoted > 0) {
      const [nextClass] = await conn.query(
        `SELECT id FROM classes WHERE name=(SELECT name FROM classes WHERE id=? ) AND id > ? ORDER BY id LIMIT 1`,
        [class_id, class_id]
      );
      if (nextClass.length) {
        const tid = nextClass[0].id;
        const [rows] = await conn.query(
          `SELECT s.id, COALESCE(SUM(m.marks), 0) AS total
             FROM students s
             LEFT JOIN marks m ON m.student_id = s.id AND m.exam_id IN (
               SELECT id FROM exams WHERE class_id=? AND exam_type IN ('midterm','final')
             )
            WHERE s.class_id=?
            GROUP BY s.id ORDER BY total DESC, s.roll ASC`,
          [tid, tid]
        );
        for (let i = 0; i < rows.length; i++) {
          await conn.query('UPDATE students SET roll=? WHERE id=?', [i + 1, rows[i].id]);
        }
      }
    }
    await conn.commit();
    await log(req.user.id, 'promote_execute', `Promoted ${promoted} students from class ${class_id} (${conditional} retained, ${noteCount} notes)`);
    res.json({ ok: true, promoted, retained: conditional, notes: noteCount });
  } catch (err) { await conn.rollback(); console.error(err); res.status(500).json({ error: 'Server error' }); }
  finally { conn.release(); }
});

module.exports = router;