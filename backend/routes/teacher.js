const router = require('express').Router();
const pool = require('../db');
const { auth, signToken } = require('../middleware/auth');
const { queuePush, getGuardianTokens } = require('../fcm');
const { validateMarksValue } = require('../validate');

router.use(auth('teacher'));

const TZ_OFF = 6 * 60 * 60 * 1000; // Asia/Dhaka UTC+6, no DST

// 6-digit student admission code (distinct from any existing 8-digit legacy codes)
async function genStudentCode() {
  for (let i = 0; i < 30; i++) {
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const [[row]] = await pool.query('SELECT id FROM students WHERE student_code=?', [code]);
    if (!row) return code;
  }
  throw new Error('Could not generate unique code');
}

// NCTB religion auto-allocation on registration (same subject serves Islam/Hindu via aliases)
async function autoAssignReligionSubjects(studentId, classId, religion, teacherId) {
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
        [studentId, s.id, teacherId]
      );
    }
  }
}

function bangladeshNow() {
  const shifted = Date.now() + TZ_OFF;
  const d = new Date(shifted);
  return { shifted, day: d.getUTCDay(), time: d.toISOString().slice(11, 16) };
}

router.get('/profile', async (req, res) => {
  try {
    const [subjects] = await pool.query(
      `SELECT sub.id, sub.name, sub.class_id, c.name AS class_name, c.section
       FROM subjects sub JOIN classes c ON sub.class_id = c.id
       WHERE sub.teacher_id = ? ORDER BY sub.class_id, sub.id`,
      [req.user.id]
    );
    const [classes] = await pool.query(
      `SELECT c.id, c.name, c.section, c.group_name,
        (SELECT COUNT(*) FROM students s WHERE s.class_id = c.id) AS student_count
       FROM classes c WHERE c.teacher_id = ?`,
      [req.user.id]
    );
    const [uRows] = await pool.query(
      'SELECT is_class_teacher, designation, sort_order FROM users WHERE id=?', [req.user.id]
    );
    const is_class_teacher = uRows[0]?.is_class_teacher || [];
    res.json({ teacher: { ...req.user, designation: uRows[0]?.designation || null, sort_order: uRows[0]?.sort_order ?? null }, subjects, classes, is_class_teacher });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Teacher self-edit: name + designation. Serial position (sort_order) is admin-only.
router.put('/profile', async (req, res) => {
  const { name, designation } = req.body || {};
  if (name === undefined && designation === undefined) {
    return res.status(400).json({ error: 'Nothing to update' });
  }
  let cleanName = name;
  let cleanDesignation = designation;
  if (name !== undefined) {
    cleanName = String(name).trim();
    if (cleanName.length < 3) return res.status(400).json({ error: 'Name must be at least 3 characters' });
  }
  if (designation !== undefined) {
    cleanDesignation = String(designation).trim();
    if (cleanDesignation.length < 2) return res.status(400).json({ error: 'Designation must be at least 2 characters' });
  }
  try {
    const fields = [];
    const params = [];
    if (cleanName) { fields.push('name=?'); params.push(cleanName); }
    if (cleanDesignation !== undefined) { fields.push('designation=?'); params.push(cleanDesignation); }
    if (fields.length === 0) return res.status(400).json({ error: 'Nothing to update' });
    params.push(req.user.id);
    await pool.query(`UPDATE users SET ${fields.join(', ')} WHERE id=?`, params);
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'profile_update',
       (cleanName ? 'name=' + cleanName + (cleanDesignation ? ', ' : '') : '') + (cleanDesignation ? 'designation=' + cleanDesignation : '')]);
    const [rows] = await pool.query(
      'SELECT id, role, username, name, designation, sort_order, is_class_teacher FROM users WHERE id=?', [req.user.id]);
    const u = rows[0];
    if (!u) return res.status(404).json({ error: 'User not found' });
    const token = signToken(u);
    res.json({ ok: true, token, user: u });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/subjects', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT sub.id, sub.name, sub.class_id, c.name AS class_name, c.section
       FROM subjects sub JOIN classes c ON sub.class_id = c.id
       WHERE sub.teacher_id = ? ORDER BY sub.class_id, sub.id`,
      [req.user.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/exams', async (req, res) => {
  try {
    // Admin exams: ONLY the class teacher of that class may see them
    // Teacher-created exams: creator or explicitly shared teachers
    const [rows] = await pool.query(
      `SELECT e.*, c.name AS class_name, c.section, sub.name AS subject_name,
              CASE WHEN e.created_by = ? THEN 1 ELSE 0 END AS is_mine
       FROM exams e
       JOIN classes c ON e.class_id = c.id
       JOIN subjects sub ON e.subject_id = sub.id
       WHERE (e.source = 'admin' AND c.teacher_id = ?)
          OR (e.source = 'teacher' AND (e.created_by = ? OR e.id IN (SELECT exam_id FROM exam_shares WHERE teacher_id = ?)))
       ORDER BY e.created_at DESC`,
      [req.user.id, req.user.id, req.user.id, req.user.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/exams', async (req, res) => {
  const { name, exam_type, class_id, subject_id, exam_date, total_marks } = req.body || {};
  const { event_id } = req.body || {};
  if (!name || !class_id || !subject_id) return res.status(400).json({ error: 'name, class_id, subject_id required' });
  try {
    const [[subj]] = await pool.query(
      'SELECT id, class_id, full_marks FROM subjects WHERE id=? AND teacher_id=?', [subject_id, req.user.id]
    );
    if (!subj) return res.status(403).json({ error: 'This subject is not assigned to you' });
    // Guard: the exam's class must match the subject's class
    if (Number(subj.class_id) !== Number(class_id)) {
      return res.status(400).json({ error: 'class_id does not match the subject\'s class' });
    }
    // Validate the subject full_marks so teacher-created tests get proper defaults
    const subjectFull = Number(subj.full_marks) || (exam_type === 'class_test' ? 25 : 100);
    const total = Number(total_marks) || subjectFull;
    const [result] = await pool.query(
      `INSERT INTO exams (name, exam_type, class_id, subject_id, source, created_by, exam_date, event_id)
       VALUES (?,?,?,?,?,?,?,?)`,
      [name, exam_type || 'class_test', class_id, subject_id, 'teacher', req.user.id, exam_date || null, event_id || null]
    );
    res.status(201).json({ id: result.insertId, total });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

async function teacherCanAccessExam(examId, userId) {
  const [rows] = await pool.query(
    `SELECT e.* FROM exams e
     LEFT JOIN classes cls ON e.class_id = cls.id
     WHERE e.id = ? AND (
        (e.source = 'admin' AND cls.teacher_id = ?)
        OR (e.source = 'teacher' AND (e.created_by = ? OR e.id IN (SELECT exam_id FROM exam_shares WHERE teacher_id = ?)))
     )`,
    [examId, userId, userId, userId]
  );
  return rows[0] || null;
}

router.get('/exams/:id', async (req, res) => {
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    const [students] = await pool.query(
      `SELECT s.id, s.name, s.roll
       FROM students s WHERE s.class_id = ? ORDER BY s.roll`,
      [exam.class_id]
    );
    const [marks] = await pool.query(
      `SELECT m.id, m.student_id, m.marks, m.total, m.edit_until,
        (m.edit_until IS NOT NULL AND m.edit_until > NOW()) AS editable
       FROM marks m WHERE m.exam_id = ?`,
      [req.params.id]
    );
    const [[subj]] = await pool.query('SELECT name, full_marks FROM subjects WHERE id=?', [exam.subject_id]);
    res.json({ exam: { ...exam, subject_name: subj ? subj.name : exam.subject_name, full_marks: subj ? subj.full_marks : null }, students, marks });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});


// Teacher may delete ONLY exams they created themselves (source=='teacher' && created_by==me).
router.delete('/exams/:id', async (req, res) => {
  try {
    const [[exam]] = await pool.query(
      'SELECT id, source, created_by FROM exams WHERE id=?', [req.params.id]);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    if (exam.source !== 'teacher' || Number(exam.created_by) !== Number(req.user.id)) {
      return res.status(403).json({ error: 'You may only delete exams you created' });
    }
    await pool.query('DELETE FROM exam_shares WHERE exam_id=?', [req.params.id]);
    await pool.query('DELETE FROM marks WHERE exam_id=?', [req.params.id]);
    await pool.query('DELETE FROM exams WHERE id=?', [req.params.id]);
    await log(req.user.id, 'exam_delete', 'Deleted own exam ' + req.params.id);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/exams/:id/marks', async (req, res) => {
  const { records } = req.body || {};
  if (!Array.isArray(records) || records.length === 0) {
    return res.status(400).json({ error: 'records array required' });
  }
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
    if (!exam) return res.status(404).json({ error: 'Exam not found or not your subject' });
    if (exam.status === 'published') {
      return res.status(403).json({ error: 'Result already published. Contact admin for changes.' });
    }
    // Exam date limit: marks may only be entered up to the exam date (end of that day).
    if (exam.exam_date) {
      const d = exam.exam_date instanceof Date ? exam.exam_date.toISOString().slice(0, 10) : String(exam.exam_date).slice(0, 10);
      const examDateMs = new Date(d + 'T23:59:59').getTime();
      if (Date.now() > examDateMs) {
        return res.status(403).json({
          error: 'Marks entry closed: this exam\u2019s date-limit (' + d + ') has passed. Ask the admin for an exception.'
        });
      }
    }
    // Default total = the subject's full_marks (never hardcode 100 for class tests).
    const [[subj]] = await pool.query('SELECT full_marks FROM subjects WHERE id=?', [exam.subject_id]);
    const defaultTotal = Number(subj && subj.full_marks) || 100;
    const studentIds = records.map(r => r.student_id);
    const [classStudents] = await pool.query('SELECT id FROM students WHERE class_id=?', [exam.class_id]);
    const allowed = new Set(classStudents.map(s => String(s.id)));
    for (const sid of studentIds) {
      if (!allowed.has(String(sid))) {
        return res.status(403).json({ error: `Student ${sid} does not belong to the exam class` });
      }
    }
    for (const r of records) {
      const vErr = validateMarksValue(r.marks, r.total !== undefined && r.total !== null && r.total !== '' ? r.total : defaultTotal);
      if (vErr) return res.status(400).json({ error: `Student ${r.student_id}: ${vErr}` });
      if (r.comment && String(r.comment).length > 255) {
        return res.status(400).json({ error: 'Comment too long (max 255)' });
      }
    }
    const examId = req.params.id;
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      for (const r of records) {
        const total = r.total !== undefined && r.total !== null && r.total !== '' ? r.total : defaultTotal;
        const [existing] = await conn.query('SELECT id, edit_until FROM marks WHERE student_id=? AND exam_id=?', [r.student_id, examId]);
        if (existing.length > 0) {
          const editUntil = existing[0].edit_until;
          const editable = editUntil && new Date(editUntil) > new Date();
          if (!editable) {
            throw Object.assign(new Error('Mark for student ' + r.student_id + ' is locked. Admin permission required.'), { status: 403 });
          }
          await conn.query(
            `UPDATE marks SET marks=?, total=?, comment=?, recorded_by=?, recorded_at=NOW(), edit_until=DATE_ADD(NOW(), INTERVAL 10 MINUTE) WHERE id=?`,
            [r.marks, total, r.comment || null, req.user.id, existing[0].id]
          );
        } else {
          await conn.query(
            `INSERT INTO marks (student_id, exam_id, marks, total, comment, recorded_by, recorded_at, edit_until)
             VALUES (?,?,?,?,?,?,NOW(),DATE_ADD(NOW(), INTERVAL 10 MINUTE))`,
            [r.student_id, examId, r.marks, total, r.comment || null, req.user.id]
          );
        }
      }
      await conn.commit();
      res.json({ ok: true, message: 'Marks saved. You can edit for 10 minutes only.' });
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } catch (err) {
    console.error(err);
    if (err.status) return res.status(err.status).json({ error: err.message });
    res.status(500).json({ error: 'Server error' });
  }
});

router.get('/classes/:id/students', async (req, res) => {
  try {
    const [cls] = await pool.query('SELECT id FROM classes WHERE id=? AND teacher_id=?', [req.params.id, req.user.id]);
    if (cls.length === 0) return res.status(403).json({ error: 'You are not the class teacher of this class' });
    const [rows] = await pool.query(
      'SELECT id, name, roll FROM students WHERE class_id=? ORDER BY roll', [req.params.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// New admission (class-teacher only): 6-digit code auto-generated, roll auto = MAX(roll)+1.
router.post('/students', async (req, res) => {
  const { name, dob, roll, class_id, religion, guardian_id, guardian_name, guardian_phone, guardian_email, address, father_name, mother_name, birth_cert_no } = req.body || {};
  if (!name || !class_id) return res.status(400).json({ error: 'name and class_id required' });
  try {
    const [[cls]] = await pool.query('SELECT id, name, teacher_id FROM classes WHERE id=?', [class_id]);
    if (!cls) return res.status(404).json({ error: 'Class not found' });
    if (cls.teacher_id !== req.user.id) {
      return res.status(403).json({ error: 'কেবলমাত্র নির্ধারিত ক্লাস টিচারই নতুন শিক্ষার্থী ভর্তি করতে পারবেন।' });
    }
    // Duplicate guard: same class + roll already admitted → 409 (idempotent).
    const dupRollNum = roll !== undefined && roll !== null && roll !== '' ? Number(roll) : 0;
    if (dupRollNum) {
      const [[dup]] = await pool.query(
        'SELECT id, name, roll FROM students WHERE class_id=? AND roll=? LIMIT 1',
        [class_id, dupRollNum]);
      if (dup) {
        return res.status(409).json({
          error: 'Class: ' + (cls.name || class_id) + ' — Roll ' + dup.roll + ' ইতিমধ্যে ' + dup.name + ' এর জন্য নিবন্ধিত।',
          student: dup,
        });
      }
    }
    const [[rollRow]] = await pool.query('SELECT COALESCE(MAX(roll),0)+1 AS next_roll FROM students WHERE class_id=?', [class_id]);
    const effectiveRoll = roll !== undefined && roll !== null && roll !== '' ? Number(roll) : rollRow.next_roll;
    const code = await genStudentCode();
    const [result] = await pool.query(
      `INSERT INTO students (student_code, name, dob, roll, class_id, religion, guardian_id, guardian_name, guardian_phone, guardian_email, address, father_name, mother_name, birth_cert_no)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [code, name, dob || null, effectiveRoll, class_id, religion || null, guardian_id || null, guardian_name || null, guardian_phone || null, guardian_email || null, address || null, father_name || null, mother_name || null, birth_cert_no || null]
    );
    await autoAssignReligionSubjects(result.insertId, class_id, religion, req.user.id);
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'student_register', 'Registered student ' + name + ' (' + code + ') in class ' + class_id + ' ' + (cls.name || '')]);
    res.status(201).json({ id: result.insertId, student_code: code, roll: effectiveRoll });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.code === 'ER_DUP_ENTRY' ? 'Duplicate roll in class' : 'Server error' });
  }
});

// ---- Class-teacher request workflow (teacher -> admin approval) ----
router.post('/class-teacher-request', async (req, res) => {
  const { class_id, note } = req.body || {};
  if (!class_id) return res.status(400).json({ error: 'class_id required' });
  try {
    const [[cls]] = await pool.query('SELECT id, name, section FROM classes WHERE id=?', [class_id]);
    if (!cls) return res.status(404).json({ error: 'Class not found' });
    const [[existing]] = await pool.query(
      "SELECT id, status FROM class_teacher_requests WHERE class_id=? AND teacher_id=?",
      [class_id, req.user.id]
    );
    if (existing) {
      if (existing.status === 'pending') return res.status(409).json({ error: 'Request already pending approval' });
      if (existing.status === 'approved') return res.status(409).json({ error: 'You are already the class teacher of this class' });
    }
    const [[claimed]] = await pool.query(
      "SELECT id FROM class_teacher_requests WHERE class_id=? AND teacher_id<>? AND status IN ('pending','approved') LIMIT 1",
      [class_id, req.user.id]
    );
    if (claimed) return res.status(409).json({ error: 'এই class-এ ইতিমধ্যে অন্য একজন teacher-এর class teacher অনুরোধ রয়েছে' });
    await pool.query(
      "INSERT INTO class_teacher_requests (class_id, teacher_id, note) VALUES (?,?,?)",
      [class_id, req.user.id, note || null]
    );
    await pool.query(
      `INSERT INTO notifications (title, body, type, target_type, created_by)
       VALUES (?,?,?,?,?)`,
      ['Class teacher request', `${req.user.name} requested to be class teacher of ${cls.name} (${cls.section}). Review in the Teachers page.`, 'special', 'teacher', req.user.id]
    );
    res.status(201).json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/class-teacher-requests', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT r.*, c.name AS class_name, c.section, c.group_name
       FROM class_teacher_requests r JOIN classes c ON r.class_id = c.id
       WHERE r.teacher_id = ? ORDER BY r.id DESC LIMIT 50`,
      [req.user.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ---- "Who is Free" teacher directory + status ----
router.get('/directory', async (req, res) => {
  try {
    const now = bangladeshNow();
    const schoolDay = now.day >= 0 && now.day <= 4;
    const [teachers] = await pool.query(
      "SELECT id, name, designation, phone FROM users WHERE role='teacher' AND active=1 ORDER BY sort_order NULLS LAST, name"
    );
    const [routines] = await pool.query(
      `SELECT r.teacher_id, ts.start_time, ts.end_time, ts.label AS slot_label, ts.slot_order,
              s.name AS subject_name
       FROM routines r JOIN time_slots ts ON r.time_slot_id = ts.id
       JOIN subjects s ON r.subject_id = s.id
       WHERE r.day = ? ORDER BY ts.slot_order`,
      [now.day]
    );
    const [ctRows] = await pool.query(
      'SELECT teacher_id, COUNT(*) AS cnt FROM classes WHERE teacher_id IS NOT NULL GROUP BY teacher_id'
    );
    const ctMap = new Map(ctRows.map(r => [r.teacher_id, Number(r.cnt)]));
    const toMs = t => { const [h, m] = String(t || '00:00').split(':').map(Number); return (h || 0) * 60 + (m || 0); };
    const nowMs = toMs(now.time);
    const out = teachers.map(t => {
      const mine = routines.filter(r => r.teacher_id === t.id);
      const current = mine.find(r => nowMs >= toMs(r.start_time) && nowMs < toMs(r.end_time));
      return {
        id: t.id,
        name: t.name,
        designation: t.designation || '',
        phone: t.phone || '',
        free: schoolDay ? !current : true,
        current_class: current ? { subject_name: current.subject_name, slot_label: current.slot_label } : null,
        periods_today: mine.map(r => ({ slot_order: r.slot_order, slot_label: r.slot_label, subject_name: r.subject_name })),
        class_teacher_of: ctMap.get(t.id) || 0
      };
    });
    res.json({ day: now.day, bd_time: now.time, teachers: out });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/classes/:id/guardians', async (req, res) => {
  try {
    const [cls] = await pool.query('SELECT id FROM classes WHERE id=? AND teacher_id=?', [req.params.id, req.user.id]);
    if (cls.length === 0) return res.status(403).json({ error: 'You are not the class teacher of this class' });
    const [rows] = await pool.query(
      `SELECT s.id AS student_id, s.name AS student_name, s.roll,
              s.guardian_name, s.guardian_phone,
              g.username AS guardian_login
       FROM students s
       LEFT JOIN users g ON g.role='guardian' AND g.name = s.guardian_name
       WHERE s.class_id=? ORDER BY s.roll`, [req.params.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/attendance', async (req, res) => {
  const { date, records } = req.body || {};
  if (!date || !Array.isArray(records) || records.length === 0) {
    return res.status(400).json({ error: 'date and records array required' });
  }
  try {
    // Strict class-teacher authorization: teacher may only record attendance
    // for classes where classes.teacher_id == this teacher (403 with Bengali message).
    const studentIds = records.map(r => r.student_id);
    const [classCheck] = await pool.query(
      `SELECT DISTINCT c.id AS class_id, c.name AS class_name, c.section, c.teacher_id
       FROM students s JOIN classes c ON s.class_id = c.id WHERE s.id IN (?)`,
      [studentIds]
    );
    for (const cls of classCheck) {
      if (cls.teacher_id !== req.user.id) {
        return res.status(403).json({
          error: 'কেবলমাত্র নির্ধারিত ক্লাস টিচারই এই ক্লাসের হাজিরা নিতে পারবেন।'
        });
      }
    }
    // Deduplicate (last entry wins) so a repeated student_id can't break the
    // multi-row ON CONFLICT upsert.
    const byId = new Map();
    for (const r of records) byId.set(Number(r.student_id), r);
    const unique = [...byId.values()];

    // Single bulk upsert (INSERT ... ON CONFLICT) for the whole class instead
    // of one query per student — critical when a 60+ student class is saved.
    const values = unique.map(() => '(?,?,?,?,?,?)').join(',');
    const params = [];
    for (const r of unique) {
      params.push(r.student_id, date, r.status, r.remark || null, req.user.id, r.is_escape ? 1 : 0);
    }
    await pool.query(
      `INSERT INTO attendance (student_id, date, status, remark, recorded_by, is_escape) VALUES ${values}
       ON CONFLICT (student_id, date) DO UPDATE SET status=EXCLUDED.status, remark=EXCLUDED.remark, recorded_by=EXCLUDED.recorded_by, is_escape=EXCLUDED.is_escape, escape_detected_at=EXCLUDED.escape_detected_at`,
      params
    );
    // Reply 200 immediately; the FCM push runs in the background so the
    // teacher app never waits on Firebase during peak-hours concurrency.
    const studentIdsForNotify = unique.map(r => r.student_id);
    res.json({ ok: true, count: unique.length, escapes: unique.filter(r => r.is_escape).map(r => Number(r.student_id)) });
    setImmediate(() => {
      notifyAttendanceGuardians(req.user.id, studentIdsForNotify, date, unique)
        .catch(e => console.error('attendance push error:', e && e.message));
    });
  } catch (err) {
    console.error(err);
    if (err.status) return res.status(err.status).json({ error: err.message });
    res.status(500).json({ error: 'Server error' });
  }
});

async function notifyAttendanceGuardians(teacherId, studentIds, date, records) {
  const tokens = await getGuardianTokens(studentIds);
  if (!tokens.length) return;
  const absentCount = records.filter(r => r.status !== 'present').length;
  const statusSummary = absentCount > 0
    ? `${records.length} জনের মধ্যে ${absentCount} জন অনুপস্থিত/late`
    : `সবাই present`;
  await queuePush(tokens,
    `Attendance recorded — ${date}`,
    `আজকের হাজিরা: ${statusSummary}. বিস্তারিত অ্যাপে দেখুন।`,
    { type: 'attendance', date: String(date) });
}

router.get('/attendance', async (req, res) => {
  const { date } = req.query;
  try {
    const [rows] = await pool.query(
      `SELECT a.*, s.name AS student_name, s.roll, c.id AS class_id, c.name AS class_name, c.section
       FROM attendance a JOIN students s ON a.student_id = s.id
       JOIN classes c ON s.class_id = c.id
       WHERE c.teacher_id = ? AND (? IS NULL OR a.date = ?)
       ORDER BY a.date DESC, s.roll LIMIT 500`,
      [req.user.id, date || null, date || null]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/notify', async (req, res) => {
  const { student_ids, title, body, type } = req.body || {};
  if (!Array.isArray(student_ids) || student_ids.length === 0) return res.status(400).json({ error: 'student_ids array required' });
  if (!title || !body) return res.status(400).json({ error: 'title and body required' });
  try {
    // Ownership check: teacher can only notify students in classes they teach (as class teacher or subject teacher)
    const [owned] = await pool.query(
      `SELECT s.id FROM students s JOIN classes c ON s.class_id=c.id
       WHERE s.id IN (?) AND (c.teacher_id=? OR s.class_id IN
         (SELECT class_id FROM subjects WHERE teacher_id=?))`,
      [student_ids, req.user.id, req.user.id]
    );
    const ownedIds = owned.map(r => r.id);
    if (ownedIds.length !== student_ids.length) {
      return res.status(403).json({ error: 'Some students are not in your classes' });
    }
    // Bulk-insert the notification rows (one per student) in a single query.
    const nValues = ownedIds.map(() => '(?,?,?,?,?,?,?)').join(',');
    const nParams = [];
    for (const sid of ownedIds) {
      nParams.push(sid, title, body, type || 'general', 'students', null, req.user.id);
    }
    await pool.query(
      `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, created_by)
       VALUES ${nValues}`,
      nParams
    );
    const tokens = await getGuardianTokens(ownedIds);
    const queued = await queuePush(tokens, title, body, { type: type || 'general' });
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'notify', 'Sent "' + title + '" to ' + ownedIds.length + ' guardian(s)']);
    res.status(201).json({ ok: true, count: ownedIds.length, push: queued });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/ct-marks', async (req, res) => {
  const { class_id, ct_no } = req.query;
  if (!class_id) return res.status(400).json({ error: 'class_id required' });
  try {
    const [[cls]] = await pool.query('SELECT id FROM classes WHERE id=? AND teacher_id=?', [class_id, req.user.id]);
    if (!cls) return res.status(403).json({ error: 'You are not the class teacher of this class' });
    const [students] = await pool.query(
      'SELECT id, name, roll FROM students WHERE class_id=? ORDER BY roll', [class_id]
    );
    let marks = [];
    if (ct_no) {
      [marks] = await pool.query(
        `SELECT cm.* FROM ct_marks cm JOIN students s ON cm.student_id=s.id
         WHERE s.class_id=? AND cm.ct_no=?`, [class_id, ct_no]
      );
    }
    const [subjects] = await pool.query(
      `SELECT DISTINCT sub.id, sub.name FROM subjects sub
       JOIN students s ON s.class_id=sub.class_id WHERE s.class_id=? ORDER BY sub.name`, [class_id]
    );
    res.json({ students, subjects, marks });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/ct-marks', async (req, res) => {
  const { records } = req.body || {};
  if (!Array.isArray(records) || !records.length) {
    return res.status(400).json({ error: 'records array required (student_id, subject_id, ct_no, marks)' });
  }
  for (const r of records) {
    const vErr = validateMarksValue(r.marks, r.full_marks || 25);
    if (vErr) return res.status(400).json({ error: `Student ${r.student_id}: ${vErr}` });
    const ctNo = Number(r.ct_no || 1);
    if (!Number.isInteger(ctNo) || ctNo < 1 || ctNo > 20) {
      return res.status(400).json({ error: 'ct_no must be between 1 and 20' });
    }
  }
  try {
    for (const r of records) {
      await pool.query(
        `INSERT INTO ct_marks (student_id, subject_id, ct_no, marks, full_marks, recorded_by, edit_until)
         VALUES (?,?,?,?,?,?,DATE_ADD(NOW(), INTERVAL 10 MINUTE))
         ON CONFLICT (student_id, subject_id, ct_no) DO UPDATE SET marks=EXCLUDED.marks, full_marks=EXCLUDED.full_marks,
           edit_until=CASE WHEN ct_marks.edit_until > NOW() THEN DATE_ADD(NOW(), INTERVAL 10 MINUTE) ELSE ct_marks.edit_until END`,
        [r.student_id, r.subject_id, r.ct_no || 1, r.marks, r.full_marks || 25, req.user.id]
      );
    }
    res.json({ ok: true, count: records.length, message: 'CT marks saved. Editable for 10 minutes.' });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/homework', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT h.id, h.title, h.description, h.due_date, h.created_at,
              c.name AS class_name, c.section, sub.name AS subject_name
       FROM homework h
       JOIN classes c ON h.class_id = c.id
       LEFT JOIN subjects sub ON h.subject_id = sub.id
       WHERE h.class_id IN (SELECT id FROM classes WHERE teacher_id = ?)
          OR h.subject_id IN (SELECT id FROM subjects WHERE teacher_id = ?)
       ORDER BY h.id DESC LIMIT 100`,
      [req.user.id, req.user.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/homework', async (req, res) => {
  const { class_id, subject_id, title, description, due_date } = req.body || {};
  if (!class_id || !title) return res.status(400).json({ error: 'class_id and title required' });
  try {
    let classOk = false;
    if (subject_id) {
      const [subj] = await pool.query('SELECT class_id, id FROM subjects WHERE id=? AND teacher_id=?', [subject_id, req.user.id]);
      if (subj.length === 0) return res.status(403).json({ error: 'This subject is not assigned to you' });
      if (Number(subj[0].class_id) !== Number(class_id)) {
        return res.status(400).json({ error: 'class_id does not match the subject\'s class' });
      }
      classOk = true;
    }
    const [[cls]] = await pool.query('SELECT id, teacher_id FROM classes WHERE id=?', [class_id]);
    if (!cls) return res.status(404).json({ error: 'Class not found' });
    if (!classOk && cls.teacher_id !== req.user.id) {
      return res.status(403).json({ error: 'কেবলমাত্র নির্ধারিত ক্লাস টিচারই এই ক্লাসের হোমওয়ার্ক দিতে পারবেন।' });
    }
    const [result] = await pool.query(
      `INSERT INTO homework (class_id, subject_id, title, description, due_date, created_by)
       VALUES (?,?,?,?,?,?)`,
      [class_id, subject_id || null, title, description || null, due_date || null, req.user.id]
    );
    // Notify the guardians of that class (deep-link payload: type=homework)
    const [students] = await pool.query('SELECT id FROM students WHERE class_id=?', [class_id]);
    const studentIds = students.map(s => s.id);
    await pool.query(
      'INSERT INTO notifications (class_id, title, body, type, target_type, related_id, created_by) VALUES (?,?,?,?,?,?,?)',
      [class_id, 'New homework assigned', `${title}${due_date ? ' — Due: ' + due_date : ''}`, 'homework', 'class', result.insertId, req.user.id]
    );
    const tokens = await getGuardianTokens(studentIds);
    const subjName = subject_id
      ? (await pool.query('SELECT name FROM subjects WHERE id=?', [subject_id]))[0][0]?.name
      : '';
    const queued = await queuePush(tokens,
      'New homework assigned for your child',
      `${title}${subjName ? ' (' + subjName + ')' : ''}${due_date ? ' — due ' + due_date : ''}`,
      { type: 'homework', homework_id: String(result.insertId), class_id: String(class_id) }
    );
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'homework_create', 'Homework "' + title + '" for class ' + class_id]);
    res.status(201).json({ id: result.insertId, ok: true, push: queued });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/complaints', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT n.id, n.student_id, n.title, n.body, n.type, n.created_at, s.name AS student_name, s.roll
       FROM notifications n JOIN students s ON n.student_id = s.id
       WHERE n.created_by = ? AND n.type IN ('complaint','special')
       ORDER BY n.id DESC LIMIT 100`,
      [req.user.id]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/complaints', async (req, res) => {
  const { student_id, title, body, kind } = req.body || {};
  if (!student_id || !title || !body) return res.status(400).json({ error: 'student_id, title and body required' });
  try {
    const [[stu]] = await pool.query(
      `SELECT s.id, s.guardian_id FROM students s JOIN classes c ON s.class_id = c.id
       WHERE s.id=? AND (c.teacher_id=? OR s.class_id IN (SELECT class_id FROM subjects WHERE teacher_id=?))`,
      [student_id, req.user.id, req.user.id]
    );
    if (!stu) return res.status(403).json({ error: 'This student is not in a class you teach' });
    const type = kind === 'special' ? 'special' : 'complaint';
    await pool.query(
      'INSERT INTO notifications (student_id, title, body, type, target_type, created_by) VALUES (?,?,?,?,?,?)',
      [student_id, title, body, type, 'students', req.user.id]
    );
    const tokens = await getGuardianTokens([student_id]);
    const queued = await queuePush(tokens, title, body, { type, student_id: String(student_id) });
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'complaint_send', (kind === 'special' ? 'Special notice' : 'Complaint') + ' for student ' + student_id]);
    res.status(201).json({ ok: true, push: queued });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/exams/:id/publish', async (req, res) => {
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
    if (!exam) return res.status(404).json({ error: 'Exam not found or not your subject' });
    if (exam.created_by !== req.user.id) {
      return res.status(403).json({ error: 'Only the exam creator can publish this test' });
    }
    if (exam.status === 'published') return res.status(400).json({ error: 'Already published' });

    const [marks] = await pool.query(
      `SELECT m.*, s.guardian_id FROM marks m JOIN students s ON m.student_id = s.id WHERE m.exam_id = ?`,
      [exam.id]
    );
    if (marks.length === 0) return res.status(400).json({ error: 'No marks entered yet' });

    const [[subj]] = await pool.query('SELECT name FROM subjects WHERE id=?', [exam.subject_id]);
    const subjectName = subj ? subj.name : exam.subject_name;

    await pool.query("UPDATE exams SET status='published' WHERE id=?", [exam.id]);

    const studentIds = marks.map(m => m.student_id);
    // Bulk-insert result notifications (one row per student) in a single query.
    const pValues = marks.map(() => '(?,?,?,?,?,?,?)').join(',');
    const pParams = [];
    for (const m of marks) {
      pParams.push(m.student_id, 'Class Test Result Published',
       `${exam.name} (${subjectName}) result published${m.comment ? '. Teacher comment: ' + m.comment : ''}`,
       'class_test_result', 'students', exam.id, req.user.id);
    }
    await pool.query(
      `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, created_by)
       VALUES ${pValues}`,
      pParams
    );
    const tokens = await getGuardianTokens(studentIds);
    const queued = await queuePush(tokens,
      'New result published for your child',
      `${exam.name} — ${subjectName} result is now available in the app`,
      { type: 'class_test_result', exam_id: String(exam.id), exam_name: String(exam.name) }
    );
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'result_publish', `${exam.name} published to ${studentIds.length} guardians`]);
    res.json({ ok: true, notified: studentIds.length, push: queued });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// OCR — recognize a scanned student-registration form.
// Flows:
//   1. DEMO/FALLBACK: no image -> deterministic Bengali sample fields, so the
//      teacher app plus the Guardian print/preview flow can be tested offline.
//   2. LIVE (Google Cloud Vision TEXT_DETECTION): POST { image_base64, key }
//      -> base64 -> Vision API -> raw text folded into structured fields.
//   3. OCR key never stored server-side; client passes it per-call.
router.post('/ocr/recognize', async (req, res) => {
  const VISION_ENDPOINT = 'https://vision.googleapis.com/v1/images:annotate';
  const { image_base64, key } = req.body || {};
  const fields = { name: 'Rahim Ahmed', dob: '2012-04-18', religion: 'Islam', guardian_name: 'Karim Ahmed', guardian_phone: '01712345678', father_name: 'Karimu Ahmed', mother_name: 'Sufia Begum', birth_cert_no: '201204180012345678', address: 'Nazirhat, Hathazari, Chittagong' };
  try {
    if (!image_base64) {
      return res.json({ ok: true, demo: true, fields }); // offline/demo fallback
    }
    if (!key) return res.status(400).json({ error: 'OCR requires an API key (or omit image for demo)' });
    const b64 = String(image_base64).replace(/^data:image\/[a-z]+;base64,/, '');
    const g = await fetch(VISION_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requests: [{
          image: { content: b64 },
          features: [{ type: 'TEXT_DETECTION' }],
        }],
      }) + '&key=' + encodeURIComponent(key), // <-- placeholder; replace below
    });
    // NOTE: key must be a query param, not body. Fix applied below.
    const vision = await fetch(`${VISION_ENDPOINT}?key=${encodeURIComponent(key)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requests: [{
          image: { content: b64 },
          features: [{ type: 'TEXT_DETECTION' }],
        }],
      }),
    });
    const j = await vision.json();
    const text = (j?.responses?.[0]?.fullTextAnnotation?.text || '').trim();
    if (!text) return res.json({ ok: true, demo: true, fields, note: 'Vision returned no text; demo fields used.' });
    const lines = text.split('\n').map(s => s.trim()).filter(Boolean);
    const grab = (pats) => {
      for (const l of lines) {
        for (const p of pats) {
          const i = l.toLowerCase().indexOf(p);
          if (i >= 0) return l.slice(i + p.length).trim().replace(/^[:：]\s*/, '');
        }
      }
      return null;
    };
    const out = {
      name: grab(['Name:', 'Student Name', 'নাম', 'ছাত্রীর নাম', 'ছাত্রের নাম']),
      dob: grab(['Date of Birth', 'DOB', 'জন্ম তারিখ']),
      religion: grab(['Religion', 'ধর্ম']),
      guardian_name: grab(['Guardian Name', 'Guardian', 'অভিভাবকের নাম', 'অভিভাবক']),
      guardian_phone: grab(['Guardian Phone', 'Mobile', 'ফোন', 'মোবাইল']),
      father_name: grab(['Father', 'পিতা']),
      mother_name: grab(['Mother', 'মাতা']),
      birth_cert_no: grab(['Birth Cert', 'Birth Certificate', 'জন্ম নিবন্ধন']),
      address: grab(['Address', 'Address:', 'ঠিকানা']),
    };
    for (const k of Object.keys(out)) if (out[k]) fields[k] = out[k];
    res.json({ ok: true, demo: false, fields });
  } catch (err) {
    console.error(err);
    res.json({ ok: true, demo: true, fields, note: 'Vision call failed; demo fields used.' });
  }
});

// Aggregate-only today summary: ANY teacher may see how many students were
// present per class + section + group for a given day (COUNT, never rows).
// Individual student attendance remains strictly class-teacher-scoped (see GET
// /attendance above — it filters by c.teacher_id=req.user.id).
router.patch('/attendance/:id/escape', async (req, res) => {
  const { remove } = req.body || {};
  try {
    const [rows] = await pool.query(
      `SELECT a.student_id, a.date FROM attendance a
       JOIN students s ON a.student_id=s.id JOIN classes c ON s.class_id=c.id
       WHERE a.id=? AND c.teacher_id=?`,
      [req.params.id, req.user.id]
    );
    const row = rows[0];
    if (!row) return res.status(404).json({ error: 'Attendance not found or you are not its class teacher' });
    const next = remove ? false : true;
    await pool.query('UPDATE attendance SET is_escape=?, escape_detected_at=? WHERE id=?',
      [next ? 1 : 0, next ? new Date() : null, req.params.id]);
    res.json({ ok: true, is_escape: next, lifted: next === false });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Class-teacher monthly escape/absence roll-up (own classes only).
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
       WHERE c.teacher_id=? GROUP BY c.id, c.name, c.section ORDER BY c.name, c.section`,
      [m + '-01', m + '-31', req.user.id]
    );
    res.json({ month: m, rows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/attendance/today-summary', async (req, res) => {
  const d = req.query.date || new Date().toISOString().slice(0, 10);
  try {
    const [rows] = await pool.query(
      `SELECT c.id AS class_id, c.name AS class_name, c.section, c.group_name,
              COUNT(DISTINCT a.student_id) AS present_count,
              COUNT(DISTINCT s.id) AS student_count
       FROM classes c
       JOIN students s ON s.class_id = c.id
       LEFT JOIN attendance a ON a.student_id = s.id AND a.date = ? AND a.status = 'present'
       GROUP BY c.id, c.name, c.section, c.group_name
       ORDER BY c.name, c.section, c.group_name`,
      [d]
    );
    res.json({ date: d, summary: rows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;