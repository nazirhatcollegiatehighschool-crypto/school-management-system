const router = require('express').Router();
const bcrypt = require('bcrypt');
const multer = require('multer');
const pool = require('../db');
const { auth, signToken } = require('../middleware/auth');
const { queuePush, getGuardianTokens } = require('../fcm');
const { validateMarksValue, validateMarksRecord } = require('../validate');
const { ymd, dhakaToday } = require('../dates');
const { computeResult, gradePaper, classLevelOf } = require('../grading');
const { SESSION_MORNING, SESSION_P5, FINAL, FINAL_BN, synthesize, guardWindow, currentWindow } = require('../attendance_fsm');
const PDFDocument = require('pdfkit');
const path = require('path');
const fs = require('fs');

// The MySQL->PostgreSQL translator rewrites `IN (?)` into `= ANY(?)`, which
// makes PG try to read the single value as an array literal and aborts the
// query ("malformed array literal"). A one-element IN list must therefore be
// written as a plain equality. Two or more placeholders stay untouched.
function inClause(column, ids) {
  const list = (ids || []).filter(v => v !== undefined && v !== null);
  if (!list.length) return { sql: '1=0', params: [] };
  if (list.length === 1) return { sql: `${column} = ?`, params: [list[0]] };
  return { sql: `${column} IN (${list.map(() => '?').join(',')})`, params: list };
}

router.use(auth('teacher'));

// ---- Teacher signature upload (ink-only PNG, background auto-removed)
// Rule: signature must be dark ink on light background; the server strips the
// paper background to transparent, resizes to a standard stamp size, and
// stores it under uploads/signatures/. Wherever the teacher's signature is
// needed (marksheet / result card / admit), the stored stamp auto-appears.
const sigDir = process.env.VERCEL_UPLOAD_DIR
  ? path.join(process.env.VERCEL_UPLOAD_DIR, 'signatures')
  : path.join(__dirname, '..', 'uploads', 'signatures');
if (!fs.existsSync(sigDir)) fs.mkdirSync(sigDir, { recursive: true });
const sigUpload = multer({
  storage: multer.diskStorage({
    destination: sigDir,
    filename: (req, file, cb) => {
      cb(null, 'sig_t' + req.user.id + '_' + Date.now() + '.png');
    }
  }),
  limits: { fileSize: 3 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (/^image\/(jpeg|png|webp)$/.test(file.mimetype)) cb(null, true);
    else cb(new Error('Only JPG/PNG/WebP images allowed (max 3MB)'));
  }
});

// Background removal: paper-white/near-white pixels -> transparent, dark ink
// kept opaque. Works on white notebook paper / scanned signatures without ML.
async function stripSignatureBackground(srcPath, destPath) {
  const sharp = require('sharp');
  const { data, info } = await sharp(srcPath)
    .resize({ width: 600, withoutEnlargement: true })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const px = Buffer.from(data);
  let ink = 0;
  for (let i = 0; i < px.length; i += info.channels) {
    const r = px[i], g = px[i + 1], b = px[i + 2];
    // paper test: bright AND low-saturation (white/off-white/grey paper)
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    const isPaper = mx > 200 && (mx - mn) < 40;
    if (isPaper) {
      px[i + 3] = 0; // transparent
    } else {
      ink++;
      // boost ink to solid black-ish for clean stamp look
      const k = Math.min(r, g, b);
      const dark = k < 90 ? 0 : Math.round(k * 0.4);
      px[i] = dark; px[i + 1] = dark; px[i + 2] = dark;
      px[i + 3] = 255;
    }
  }
  const inkRatio = ink / (px.length / info.channels);
  if (inkRatio < 0.005) throw new Error('স্বাক্ষর পাওয়া যায়নি — সাদা কাগজে গাঢ় কালো কালিতে সই করে আবার ছবি তুলুন।');
  if (inkRatio > 0.60) throw new Error('ছবিটা স্বাক্ষর মনে হচ্ছে না — শুধু সইয়ের অংশ ক্রপ করে দিন (ব্যাকগ্রাউন্ড সাদা রাখুন)।');
  // tight auto-crop to ink bounding box (+padding) for a compact stamp
  const W = info.width, H = info.height, ch = info.channels;
  let minX = W, minY = H, maxX = -1, maxY = -1;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      if (px[(y * W + x) * ch + 3] > 0) {
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
      }
    }
  }
  const pad = 12;
  minX = Math.max(0, minX - pad); minY = Math.max(0, minY - pad);
  maxX = Math.min(W - 1, maxX + pad); maxY = Math.min(H - 1, maxY + pad);
  await sharp(px, { raw: { width: W, height: H, channels: ch } })
    .extract({ left: minX, top: minY, width: maxX - minX + 1, height: maxY - minY + 1 })
    .png()
    .toFile(destPath);
}

// POST /teacher/signature — upload/replace own signature stamp.
router.post('/signature', sigUpload.single('signature'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'signature file required' });
    const rawPath = req.file.path;
    const finalName = 'sig_t' + req.user.id + '_' + Date.now() + '.png';
    const finalPath = path.join(sigDir, finalName);
    try {
      await stripSignatureBackground(rawPath, finalPath);
    } catch (e) {
      try { fs.unlinkSync(rawPath); } catch (_) {}
      return res.status(400).json({ error: e.message });
    }
    try { fs.unlinkSync(rawPath); } catch (_) {}
    // remove previous stamp file
    const [[prev]] = await pool.query('SELECT signature FROM users WHERE id=?', [req.user.id]);
    if (prev && prev.signature) {
      const old = path.join(sigDir, path.basename(prev.signature));
      if (fs.existsSync(old) && old !== finalPath) { try { fs.unlinkSync(old); } catch (_) {} }
    }
    await pool.query('UPDATE users SET signature=?, signature_name=? WHERE id=?',
      [finalName, (req.body && req.body.name ? String(req.body.name).slice(0, 100) : null) || req.user.name, req.user.id]);
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'signature_upload', 'Teacher uploaded signature stamp']);
    res.json({ ok: true, signature: finalName, url: '/uploads/signatures/' + finalName });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// DELETE /teacher/signature — remove own stamp.
router.delete('/signature', async (req, res) => {
  try {
    const [[u]] = await pool.query('SELECT signature FROM users WHERE id=?', [req.user.id]);
    if (u && u.signature) {
      const p = path.join(sigDir, path.basename(u.signature));
      if (fs.existsSync(p)) { try { fs.unlinkSync(p); } catch (_) {} }
    }
    await pool.query('UPDATE users SET signature=NULL, signature_name=NULL WHERE id=?', [req.user.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ---- Homework file attachments (photos of notebook pages, PDF worksheets)
// Files live under uploads/homework/ (served at /uploads, same as photos).
const hwUploadDir = process.env.VERCEL_UPLOAD_DIR
  ? path.join(process.env.VERCEL_UPLOAD_DIR, 'homework')
  : path.join(__dirname, '..', 'uploads', 'homework');
if (!fs.existsSync(hwUploadDir)) fs.mkdirSync(hwUploadDir, { recursive: true });
const hwUpload = multer({
  storage: multer.diskStorage({
    destination: hwUploadDir,
    filename: (req, file, cb) => {
      const ext = (path.extname(file.originalname) || '').toLowerCase().slice(0, 10);
      cb(null, 'hw_' + req.params.id + '_' + Date.now() + '_' + Math.floor(Math.random() * 10000) + ext);
    }
  }),
  limits: { fileSize: 8 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (/^image\/(jpeg|png|webp|gif)$/.test(file.mimetype) || file.mimetype === 'application/pdf') cb(null, true);
    else cb(new Error('Only JPG/PNG/WebP/GIF images or PDF allowed (max 8MB)'));
  }
});

// Write access: homework creator, class teacher, or the subject's teacher.
async function homeworkWriteAccess(hwId, userId) {
  const [[hw]] = await pool.query(
    `SELECT h.*, c.teacher_id AS class_teacher FROM homework h JOIN classes c ON c.id=h.class_id WHERE h.id=?`,
    [hwId]);
  if (!hw) return null;
  if (Number(hw.created_by) === Number(userId) || Number(hw.class_teacher) === Number(userId)) return hw;
  if (hw.subject_id) {
    const [[s]] = await pool.query('SELECT id FROM subjects WHERE id=? AND teacher_id=?', [hw.subject_id, userId]);
    if (s) return hw;
  }
  return false;
}

async function attachFilesTo(list, idKey) {
  const ids = (list || []).map(r => r[idKey]).filter(Boolean);
  if (!ids.length) return list;
  const [rows] = await pool.query(
    `SELECT id, homework_id, file_name, file_path, mime_type, file_size, created_at
     FROM homework_attachments WHERE homework_id IN (?) ORDER BY id`, [ids]);
  const byHw = {};
  for (const a of rows) {
    (byHw[a.homework_id] = byHw[a.homework_id] || []).push({
      ...a, url: '/uploads/homework/' + a.file_path
    });
  }
  return list.map(r => ({ ...r, attachments: byHw[r[idKey]] || [] }));
}

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
      'SELECT is_class_teacher, designation, sort_order, signature, signature_name FROM users WHERE id=?', [req.user.id]
    );
    const is_class_teacher = uRows[0]?.is_class_teacher || [];
    const sig = uRows[0]?.signature ? '/uploads/signatures/' + uRows[0].signature : null;
    res.json({ teacher: { ...req.user, designation: uRows[0]?.designation || null, sort_order: uRows[0]?.sort_order ?? null, signature_url: sig, signature_name: uRows[0]?.signature_name || null }, subjects, classes, is_class_teacher });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Teacher self-edit: name + designation. Serial position (sort_order) is admin-only.
// EXCLUSIVE designations (Head Teacher / Assistant Head Teacher) are locked:
// only ONE holder at a time — anyone else picking them gets a 409 until the
// admin removes the current holder (admin panel / designation_slots).
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
    // Exclusive posts: if another teacher currently holds it, block with 409.
    const norm = cleanDesignation.toLowerCase().replace(/\s+/g, ' ').trim();
    const exclusive = ['head teacher', 'headmaster', 'principal', 'assistant head teacher', 'assistant headmaster', 'vice principal'];
    if (exclusive.indexOf(norm) !== -1) {
      const [holders] = await pool.query(
        "SELECT id, name FROM users WHERE role='teacher' AND id<>? AND LOWER(TRIM(designation)) IN ('head teacher','headmaster','principal','assistant head teacher','assistant headmaster','vice principal')",
        [req.user.id]);
      // head-family vs assistant-family are separate locks
      const headFam = ['head teacher', 'headmaster', 'principal'];
      const wantHead = headFam.indexOf(norm) !== -1;
      const clash = holders.find(h => {
        const hn = String(h.designation || '').toLowerCase().trim();
        return wantHead ? headFam.indexOf(hn) !== -1 : headFam.indexOf(hn) === -1;
      });
      if (clash) {
        return res.status(409).json({ error: `“${cleanDesignation}” পদটি এখন ${clash.name}-এর দখলে — admin remove না করা পর্যন্ত অন্য কেউ নিতে পারবে না।` });
      }
    }
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
      'SELECT id, role, username, name, designation, sort_order, is_class_teacher, signature, signature_name FROM users WHERE id=?', [req.user.id]);
    const u = rows[0];
    if (!u) return res.status(404).json({ error: 'User not found' });
    u.signature_url = u.signature ? '/uploads/signatures/' + u.signature : null;
    const token = signToken(u);
    res.json({ ok: true, token, user: u });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Teacher self-service password change: current password verified, new one
// takes effect immediately (old stops working). Min 6 chars.
router.put('/profile/password', async (req, res) => {
  const { current_password, new_password } = req.body || {};
  if (!current_password || !new_password) {
    return res.status(400).json({ error: 'current_password and new_password required' });
  }
  if (String(new_password).length < 6) {
    return res.status(400).json({ error: 'নতুন password কমপক্ষে ৬ অক্ষরের হতে হবে।' });
  }
  try {
    const [[u]] = await pool.query('SELECT password_hash FROM users WHERE id=?', [req.user.id]);
    if (!u) return res.status(404).json({ error: 'User not found' });
    const ok = await bcrypt.compare(String(current_password), u.password_hash);
    if (!ok) return res.status(401).json({ error: 'বর্তমান password সঠিক নয়।' });
    const hash = await bcrypt.hash(String(new_password), 10);
    await pool.query('UPDATE users SET password_hash=? WHERE id=?', [hash, req.user.id]);
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'password_change', 'Teacher changed own password']);
    res.json({ ok: true });
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
    // Admin exams: the class teacher of that class AND the assigned subject
    // teacher may see/enter them (subject teachers enter their own subjects).
    // Teacher-created exams: creator or explicitly shared teachers
    const [rows] = await pool.query(
      `SELECT e.*, c.name AS class_name, c.section, sub.name AS subject_name,
              CASE WHEN e.created_by = ? THEN 1 ELSE 0 END AS is_mine,
              CASE WHEN sub.teacher_id = ? THEN 1 ELSE 0 END AS subject_mine
       FROM exams e
       JOIN classes c ON e.class_id = c.id
       JOIN subjects sub ON e.subject_id = sub.id
       WHERE (e.source = 'admin' AND (c.teacher_id = ? OR sub.teacher_id = ?))
          OR (e.source = 'teacher' AND (e.created_by = ? OR e.id IN (SELECT exam_id FROM exam_shares WHERE teacher_id = ?)))
       ORDER BY e.created_at DESC`,
      [req.user.id, req.user.id, req.user.id, req.user.id, req.user.id, req.user.id]
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
    // Guard: a teacher test may only attach to a live custom event (or none).
    // Attaching to a published event — or to a fixed core exam (half_yearly /
    // annual / pretest / test) — would pollute official results guardians see.
    if (event_id) {
      const [[ev]] = await pool.query('SELECT id, is_published, exam_kind FROM exam_events WHERE id=?', [event_id]);
      if (!ev) return res.status(404).json({ error: 'Exam event not found' });
      if (Number(ev.is_published) === 1) {
        return res.status(403).json({ error: 'Published exam-এ নিজের test যোগ করা যাবে না।' });
      }
      if (ev.exam_kind && ev.exam_kind !== 'other') {
        return res.status(403).json({ error: 'Fixed core exam-এ (Half Yearly/Annual/Pre-Test/Test) শুধু admin subject যোগ করতে পারে।' });
      }
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
    `SELECT e.*, cls.teacher_id AS class_teacher_id, sub.teacher_id AS subject_teacher_id FROM exams e
     LEFT JOIN classes cls ON e.class_id = cls.id
     LEFT JOIN subjects sub ON e.subject_id = sub.id
     WHERE e.id = ? AND (
        (e.source = 'admin' AND (sub.teacher_id = ? OR cls.teacher_id = ?))
        OR (e.source = 'teacher' AND (e.created_by = ? OR e.id IN (SELECT exam_id FROM exam_shares WHERE teacher_id = ?)))
     )`,
    [examId, userId, userId, userId, userId]
  );
  const exam = rows[0] || null;
  if (!exam) return null;
  // Scientific role split: entry right ≠ supervision right.
  // Subject teacher (or own-test creator/sharee) → can_enter=1.
  // Class teacher (non-subject) → read-only supervisor: can_enter=0.
  exam.can_enter = (exam.source === 'teacher')
    ? 1
    : (Number(exam.subject_teacher_id) === Number(userId) ? 1 : 0);
  exam.is_class_teacher = Number(exam.class_teacher_id) === Number(userId) ? 1 : 0;
  return exam;
}

router.get('/exams/:id', async (req, res) => {
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    // Subject eligibility: only students enrolled in this subject via
    // student_subjects. If NO enrollments exist for this subject yet (legacy
    // classes), fall back to all active class students so old data keeps working.
    const [[enrollCount]] = await pool.query(
      `SELECT COUNT(*) AS c FROM student_subjects ss
       JOIN students s ON s.id = ss.student_id
       WHERE ss.subject_id = ? AND s.class_id = ?`,
      [exam.subject_id, exam.class_id]
    );
    let students;
    let eligibilityEnforced = false;
    if (enrollCount && Number(enrollCount.c) > 0) {
      eligibilityEnforced = true;
      [students] = await pool.query(
        `SELECT s.id, s.name, s.roll
         FROM students s
         JOIN student_subjects ss ON ss.student_id = s.id AND ss.subject_id = ?
         WHERE s.class_id = ? AND (s.status IS NULL OR s.status = 'active')
         ORDER BY s.roll`,
        [exam.subject_id, exam.class_id]
      );
    } else {
      [students] = await pool.query(
        `SELECT s.id, s.name, s.roll
         FROM students s WHERE s.class_id = ? AND (s.status IS NULL OR s.status = 'active')
         ORDER BY s.roll`,
        [exam.class_id]
      );
    }
    const [marks] = await pool.query(
      `SELECT m.id, m.student_id, m.marks, m.total, m.cq, m.mcq, m.practical, m.written, m.ca, m.absent, m.edit_until,
        (m.edit_until IS NOT NULL AND m.edit_until > NOW()) AS editable
       FROM marks m WHERE m.exam_id = ?`,
      [req.params.id]
    );
    const [[subj]] = await pool.query('SELECT name, full_marks, teacher_id, cq_full, mcq_full, practical_full, written_full, ca_full FROM subjects WHERE id=?', [exam.subject_id]);
    const subjectMine = subj ? Number(subj.teacher_id) === Number(req.user.id) : false;
    const isClassTeacher = Number(exam.is_class_teacher) === 1;
    // App-level edit right mirrors the write rule: subject teacher only.
    const canEnter = Number(exam.can_enter) === 1;
    // NCTB mark structure for this subject (drives component-wise entry UI).
    const markStructure = subj ? {
      full_marks: subj.full_marks,
      cq_full: subj.cq_full, mcq_full: subj.mcq_full, practical_full: subj.practical_full,
      written_full: subj.written_full, ca_full: subj.ca_full,
      components: [
        ...(subj.cq_full != null ? [{ key: 'cq', label: 'CQ (সৃজনশীল)', full: Number(subj.cq_full) }] : []),
        ...(subj.mcq_full != null ? [{ key: 'mcq', label: 'MCQ (বহুনির্বাচনী)', full: Number(subj.mcq_full) }] : []),
        ...(subj.practical_full != null ? [{ key: 'practical', label: 'Practical (ব্যবহারিক)', full: Number(subj.practical_full) }] : []),
        ...(subj.written_full != null ? [{ key: 'written', label: 'Written (লিখিত)', full: Number(subj.written_full) }] : []),
        ...(subj.ca_full != null ? [{ key: 'ca', label: 'CA (ধারাবাহিক)', full: Number(subj.ca_full) }] : []),
      ],
    } : null;
    if (markStructure) markStructure.has_components = markStructure.components.length > 0;
    res.json({ exam: { ...exam, subject_name: subj ? subj.name : exam.subject_name, full_marks: subj ? subj.full_marks : null, subject_mine: subjectMine ? 1 : 0, is_class_teacher: isClassTeacher ? 1 : 0, can_enter: canEnter ? 1 : 0, mark_structure: markStructure, eligibility_enforced: eligibilityEnforced ? 1 : 0 }, students, marks, settings: await schoolSettings() });
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
    res.json(await submitExamMarks(exam, records, req.user.id));
  } catch (err) {
    console.error(err);
    if (err.status) return res.status(err.status).json({ error: err.message });
    res.status(500).json({ error: 'Server error' });
  }
});

// ------------------------------------------------------------------
// Q3/Q4/Q6 workflow: draft → submitted → approved → (admin publishes)
//
// Subject teacher submits a COMPLETE, IN-RANGE sheet. The class teacher
// of that class approves it. If the person submitting IS the class
// teacher of that class, the submission self-approves (Q6) — they own
// the academic result of their class, so no second key is required.
// ------------------------------------------------------------------
router.post('/exams/:id/submit', async (req, res) => {
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
    if (!exam) return res.status(404).json({ error: 'Exam not found or not your subject' });
    if (Number(exam.can_enter) !== 1 && Number(exam.is_class_teacher) !== 1) {
      return res.status(403).json({ error: 'শুধু subject teacher বা class teacher submit করতে পারেন।' });
    }
    if (exam.status === 'published') return res.status(409).json({ error: 'Result already published.' });
    if (exam.entry_status === 'approved') return res.status(409).json({ error: 'Already approved.' });

    const { validateExamMarks } = require('../mark_validation');
    const v = await validateExamMarks(exam.id, { strict: true });
    if (!v.ok) {
      return res.status(400).json({
        error: 'অসম্পূর্ণ/ভুল নম্বর — submit করা যায় না।',
        error_count: v.error_count, errors: v.errors,
      });
    }
    const selfApprove = Number(exam.is_class_teacher) === 1;
    if (selfApprove) {
      await pool.query(
        `UPDATE exams SET entry_status='approved', submitted_at=NOW(), submitted_by=?,
                approved_at=NOW(), approved_by=?, reject_reason=NULL WHERE id=?`,
        [req.user.id, req.user.id, exam.id]);
      await log(req.user.id, 'exam_submit_selfapprove', `Exam ${exam.id} self-approved (class teacher)`);
      return res.json({ ok: true, entry_status: 'approved', self_approved: true });
    }
    await pool.query(
      `UPDATE exams SET entry_status='submitted', submitted_at=NOW(), submitted_by=?, reject_reason=NULL WHERE id=?`,
      [req.user.id, exam.id]);
    await log(req.user.id, 'exam_submit', `Exam ${exam.id} submitted for class-teacher approval`);
    res.json({ ok: true, entry_status: 'submitted', self_approved: false });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Class teacher re-opens a locked subject so its subject teacher can edit.
router.post('/exams/:id/unlock', async (req, res) => {
  const reason = (req.body && req.body.reason) || null;
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    if (Number(exam.is_class_teacher) !== 1) {
      return res.status(403).json({ error: 'শুধু এই class-এর class teacher unlock করতে পারেন।' });
    }
    await pool.query(
      `UPDATE exams SET entry_status='draft', reject_reason=? WHERE id=?`,
      [reason, exam.id]);
    await pool.query('UPDATE exams SET approved_at=NULL, approved_by=NULL WHERE id=?', [exam.id]);
    await log(req.user.id, 'exam_unlock', `Exam ${exam.id} re-opened by class teacher`);
    res.json({ ok: true, entry_status: 'draft' });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Class teacher APPROVES a submitted subject-exam (Q3). Re-validates the
// whole sheet before locking it so nothing incomplete slips through.
router.post('/exams/:id/ct-approve', async (req, res) => {
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    if (Number(exam.is_class_teacher) !== 1) {
      return res.status(403).json({ error: 'শুধু এই class-এর class teacher approve করতে পারেন।' });
    }
    if (exam.entry_status !== 'submitted') {
      return res.status(400).json({ error: `entry_status "${exam.entry_status}" — শুধু submitted approve করা যায়।` });
    }
    const { validateExamMarks } = require('../mark_validation');
    const v = await validateExamMarks(exam.id, { strict: true });
    if (!v.ok) return res.status(422).json({ error: 'Validation failed', errors: v.errors, error_count: v.error_count });
    await pool.query(
      `UPDATE exams SET entry_status='approved', approved_at=NOW(), approved_by=?, reject_reason=NULL WHERE id=?`,
      [req.user.id, exam.id]);
    await log(req.user.id, 'exam_ct_approve', `Class teacher approved exam ${exam.id}`);
    res.json({ ok: true, entry_status: 'approved' });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/exams/:id/ct-reject', async (req, res) => {
  const reason = (req.body && req.body.reason) || null;
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    if (Number(exam.is_class_teacher) !== 1) {
      return res.status(403).json({ error: 'শুধু এই class-এর class teacher reject করতে পারেন।' });
    }
    if (exam.entry_status !== 'submitted') return res.status(400).json({ error: 'Only submitted exams can be rejected' });
    await pool.query(`UPDATE exams SET entry_status='draft', reject_reason=? WHERE id=?`, [reason, exam.id]);
    await log(req.user.id, 'exam_ct_reject', `Class teacher rejected exam ${exam.id}: ${reason || ''}`);
    res.json({ ok: true, entry_status: 'draft' });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Finalize marks: mark unentered students as absent, then submit
router.post('/exams/:id/finalize', async (req, res) => {
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
    if (!exam) return res.status(404).json({ error: 'Exam not found or not your subject' });
    if (exam.status === 'published') {
      return res.status(409).json({ error: 'Exam already published' });
    }
    if (Number(exam.can_enter) !== 1) {
      return res.status(403).json({ error: 'Only the subject teacher can finalize this exam.' });
    }
    if (Number(exam.entry_open) === 0) {
      return res.status(403).json({ error: 'Marks entry is closed by admin.' });
    }
    const examId = exam.id;
    // Get all students in the exam's class
    const [classStudents] = await pool.query('SELECT id, name, roll, student_code FROM students WHERE class_id=? AND (status IS NULL OR status=?)', [exam.class_id, 'active']);
    // Get students who already have marks
    const [markedStudents] = await pool.query('SELECT DISTINCT student_id FROM marks WHERE exam_id=?', [examId]);
    const markedIds = new Set(markedStudents.map(m => m.student_id));
    const absentStudents = classStudents.filter(s => !markedIds.has(s.id));
    if (absentStudents.length === 0) {
      return res.status(400).json({ error: 'All students already have marks entered.' });
    }
    // Return confirmation info before finalizing
    res.json({
      confirm: true,
      total_students: classStudents.length,
      marked: markedIds.size,
      to_be_marked_absent: absentStudents.length,
      absent_students: absentStudents.map(s => ({ id: s.id, name: s.name, roll: s.roll }))
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});

// Finalize confirm: actually mark absent students and publish
router.post('/exams/:id/finalize-confirm', async (req, res) => {
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    if (exam.status === 'published') {
      return res.status(409).json({ error: 'Exam already published' });
    }
    const examId = exam.id;
    const [classStudents] = await pool.query('SELECT id, name, roll, student_code FROM students WHERE class_id=? AND (status IS NULL OR status=?)', [exam.class_id, 'active']);
    const [markedStudents] = await pool.query('SELECT DISTINCT student_id FROM marks WHERE exam_id=?', [examId]);
    const markedIds = new Set(markedStudents.map(m => m.student_id));
    const absentStudents = classStudents.filter(s => !markedIds.has(s.id));
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      // Insert absent marks for students without marks
      for (const s of absentStudents) {
        await conn.query(
          `INSERT INTO marks (student_id, exam_id, marks, total, absent, recorded_by, recorded_at, edit_until)
           VALUES (?,?,?,?,?,?,NOW(),DATE_ADD(NOW(), INTERVAL 5 HOUR))`,
          [s.id, examId, 0, exam.full_marks || 100, 1, req.user.id]
        );
      }
      // Submit for class-teacher approval — the teacher NO LONGER publishes.
      // Publishing is an admin-only action (Q3).
      await conn.query(
        `UPDATE exams SET entry_status='submitted', submitted_at=NOW(), submitted_by=?, reject_reason=NULL WHERE id=?`,
        [req.user.id, examId]);
      await conn.commit();
      res.json({ ok: true, message: `Exam submitted. ${absentStudents.length} student(s) marked absent. Class teacher approval-এর অপেক্ষায়।` });
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});

// Shared marks submitter: guards + validation + upsert with the 5-hour edit
// window. Used by POST /exams/:id/marks and POST /events/:id/marks.
//
// Scientific entry rule: ONLY the assigned subject teacher (or the creator /
// an explicit sharee of a teacher-created test) may write numbers. The class
// teacher sees everything (supervision) but CANNOT enter or edit numbers —
// numbers come from one accountable hand only (single-writer principle).
async function submitExamMarks(exam, records, userId) {
  if (exam.status === 'published') {
    throw Object.assign(new Error('Result already published. Contact admin for changes.'), { status: 403 });
  }
  if (Number(exam.can_enter) !== 1) {
    throw Object.assign(new Error(
      'শুধু assigned subject teacher number দিতে পারেন। Class teacher হিসেবে আপনি দেখতে পারেন, entry করতে পারবেন না।'
    ), { status: 403 });
  }
  // Admin 1-click permission: entry_open=0 revokes teacher marks entry.
  if (Number(exam.entry_open) === 0) {
    throw Object.assign(new Error('Marks entry is closed by admin for this exam.'), { status: 403 });
  }
  // Q3 lock rule: once the class teacher approves the subject-exam, the
  // subject teacher can no longer edit. The class teacher must unlock it
  // first (or the admin re-opens it).
  if (exam.entry_status === 'approved') {
    throw Object.assign(new Error(
      'এই subject approve হয়ে গেছে — edit করতে class teacher-এর unlock দরকার।'
    ), { status: 403 });
  }
  // Entry deadline: an explicit date+time closes entry exactly then.
  // Fallback is the legacy exam_date (end of that day). No deadline set = open.
  if (exam.entry_deadline) {
    const dl = exam.entry_deadline instanceof Date ? exam.entry_deadline.getTime() : new Date(exam.entry_deadline).getTime();
    if (!isNaN(dl) && Date.now() > dl) {
      const d = exam.entry_deadline instanceof Date ? exam.entry_deadline.toISOString().slice(0, 16).replace('T', ' ') : String(exam.entry_deadline).slice(0, 16);
      throw Object.assign(new Error(
        'Marks entry closed: deadline was ' + d + '. Ask the admin for an exception.'
      ), { status: 403 });
    }
  } else if (exam.exam_date) {
    const d = ymd(exam.exam_date);
    const examDateMs = new Date(d + 'T23:59:59').getTime();
    if (Date.now() > examDateMs) {
      throw Object.assign(new Error(
        'Marks entry closed: this exam\u2019s date-limit (' + d + ') has passed. Ask the admin for an exception.'
      ), { status: 403 });
    }
  }
  // Default total = the subject's full_marks (never hardcode 100 for class tests).
  const [[subj]] = await pool.query('SELECT full_marks, cq_full, mcq_full, practical_full, written_full, ca_full FROM subjects WHERE id=?', [exam.subject_id]);
  const defaultTotal = Number(subj && subj.full_marks) || 100;
  const layout = subj ? { full_marks: defaultTotal, cq_full: subj.cq_full, mcq_full: subj.mcq_full, practical_full: subj.practical_full, written_full: subj.written_full, ca_full: subj.ca_full } : { full_marks: defaultTotal };
  const studentIds = records.map(r => r.student_id);
  const [classStudents] = await pool.query('SELECT id, status FROM students WHERE class_id=?', [exam.class_id]);
  const allowed = new Set(classStudents.filter(s => !s.status || s.status === 'active').map(s => String(s.id)));
  const inactive = new Set(classStudents.filter(s => s.status && s.status !== 'active').map(s => String(s.id)));
  for (const sid of studentIds) {
    if (inactive.has(String(sid))) {
      throw Object.assign(new Error(`Student ${sid} is inactive (dropped out) — marks entry not allowed`), { status: 403 });
    }
    if (!allowed.has(String(sid))) {
      throw Object.assign(new Error(`Student ${sid} does not belong to the exam class`), { status: 403 });
    }
  }
  for (const r of records) {
    // NCTB component-wise entry: CQ / MCQ / Practical / Written / CA.
    // Plain-total records still pass through the legacy single-value check.
    const recErrs = validateMarksRecord({ ...r, total: r.total !== undefined && r.total !== null && r.total !== '' ? r.total : defaultTotal }, layout);
    if (recErrs.length) throw Object.assign(new Error(recErrs[0]), { status: 400 });
  }
  const examId = exam.id;
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    for (const r of records) {
      const total = r.total !== undefined && r.total !== null && r.total !== '' ? r.total : defaultTotal;
      // Component values (null when the teacher left that part blank).
      const comp = (k) => (r[k] === undefined || r[k] === null || r[k] === '' ? null : Number(r[k]));
      const cq = comp('cq'), mcq = comp('mcq'), practical = comp('practical'), written = comp('written'), ca = comp('ca');
      const hasComponents = cq !== null || mcq !== null || practical !== null || written !== null || ca !== null;
      // Component-wise entry overrides the plain total: derived marks keeps
      // the grading engine in sync with the NCTB structure the admin set.
      const effectiveMarks = hasComponents
        ? (cq || 0) + (mcq || 0) + (practical || 0) + (written || 0) + (ca || 0)
        : Number(r.marks);
      const [existing] = await conn.query('SELECT id, edit_until FROM marks WHERE student_id=? AND exam_id=?', [r.student_id, examId]);
      if (existing.length > 0) {
        const editUntil = existing[0].edit_until;
        const editable = editUntil && new Date(editUntil) > new Date();
        if (!editable) {
          throw Object.assign(new Error('Mark for student ' + r.student_id + ' is locked. Admin permission required.'), { status: 403 });
        }
        await conn.query(
          `UPDATE marks SET marks=?, total=?, cq=?, mcq=?, practical=?, written=?, ca=?, comment=?, recorded_by=?, recorded_at=NOW(), edit_until=DATE_ADD(NOW(), INTERVAL 5 HOUR) WHERE id=?`,
          [effectiveMarks, total, cq, mcq, practical, written, ca, r.comment || null, userId, existing[0].id]
        );
      } else {
        await conn.query(
          `INSERT INTO marks (student_id, exam_id, marks, total, cq, mcq, practical, written, ca, comment, recorded_by, recorded_at, edit_until)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,NOW(),DATE_ADD(NOW(), INTERVAL 5 HOUR))`,
          [r.student_id, examId, effectiveMarks, total, cq, mcq, practical, written, ca, r.comment || null, userId]
        );
      }
    }
    await conn.commit();
    return { ok: true, message: 'Marks saved. You can edit for 5 hours only.' };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

// Roster of a class. Two legitimate roles:
//   - the CLASS TEACHER  -> full record (contact + guardian details),
//   - a SUBJECT TEACHER  -> mark-entry roster only (id/roll/name/code/photo).
// A subject teacher owns one subject of the class and must be able to open
// the number-entry sheet for the students of that subject, so the old
// class-teacher-only guard blocked a legitimate workflow. Non-class,
// non-subject teachers are still rejected.
router.get('/classes/:id/students', async (req, res) => {
  try {
    const [cls] = await pool.query('SELECT id, teacher_id FROM classes WHERE id=?', [req.params.id]);
    if (cls.length === 0) return res.status(404).json({ error: 'Class not found' });
    const isClassTeacher = Number(cls[0].teacher_id) === Number(req.user.id);
    let isSubjectTeacher = false;
    if (!isClassTeacher) {
      const [sub] = await pool.query(
        'SELECT id FROM subjects WHERE class_id=? AND teacher_id=? LIMIT 1',
        [req.params.id, req.user.id]);
      isSubjectTeacher = sub.length > 0;
    }
    if (!isClassTeacher && !isSubjectTeacher) {
      return res.status(403).json({ error: 'You are not the class teacher of this class' });
    }
    const fields = isClassTeacher
      ? 'id, student_code, name, roll, dob, gender, religion, blood_group, phone, email, guardian_name, guardian_phone, guardian_email, father_name, mother_name, birth_cert_no, address, optional_subject, photo'
      : 'id, student_code, name, roll, optional_subject, photo';
    const [rows] = await pool.query(
      `SELECT ${fields} FROM students WHERE class_id=? AND (status IS NULL OR status=?) ORDER BY roll`, [req.params.id, 'active']
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Live roll lookup: class teacher types a roll in the add form and instantly
// sees whether that roll is already taken (with the existing student's info).
// Returns {taken:false} when free — the form then just proceeds.
router.get('/classes/:id/roll-check', async (req, res) => {
  const roll = Number(req.query.roll);
  if (!Number.isInteger(roll) || roll <= 0) {
    return res.status(400).json({ error: 'Valid roll required' });
  }
  try {
    const [cls] = await pool.query('SELECT id, name FROM classes WHERE id=? AND teacher_id=?', [req.params.id, req.user.id]);
    if (cls.length === 0) return res.status(403).json({ error: 'You are not the class teacher of this class' });
    const [[dup]] = await pool.query(
      'SELECT id, student_code, name, roll, dob, gender, father_name, mother_name, guardian_name, guardian_phone FROM students WHERE class_id=? AND roll=? LIMIT 1',
      [req.params.id, roll]);
    if (dup) return res.json({ taken: true, student: dup, class_name: cls[0].name });
    return res.json({ taken: false, class_name: cls[0].name });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Class-teacher student edit: name, dob, gender, contact + guardian + address
// fields of students in THEIR OWN class only. Roll/code/class are immutable
// here (roll changes would break merit lists; class moves via promotion).
router.put('/students/:id', async (req, res) => {
  const { name, dob, gender, religion, blood_group, phone, email, guardian_name,
    guardian_phone, guardian_email, father_name, mother_name, birth_cert_no,
    address, optional_subject } = req.body || {};
  try {
    const [[stu]] = await pool.query(
      `SELECT s.id, s.class_id, c.teacher_id FROM students s JOIN classes c ON c.id=s.class_id WHERE s.id=?`,
      [req.params.id]);
    if (!stu) return res.status(404).json({ error: 'Student not found' });
    if (stu.teacher_id !== req.user.id) {
      return res.status(403).json({ error: 'কেবল নিজের class-এর শিক্ষার্থীর তথ্য edit করতে পারবেন।' });
    }
    const updates = [];
    const params = [];
    const set = (col, v) => { if (v !== undefined) { updates.push(col + '=?'); params.push(v === '' ? null : v); } };
    if (name !== undefined) {
      if (!String(name).trim()) return res.status(400).json({ error: 'Name cannot be empty' });
      set('name', String(name).trim().slice(0, 100));
    }
    set('dob', dob || null);
    set('gender', gender || null);
    set('religion', religion || null);
    set('blood_group', blood_group || null);
    set('phone', phone || null);
    set('email', email || null);
    set('guardian_name', guardian_name || null);
    set('guardian_phone', guardian_phone || null);
    set('guardian_email', guardian_email || null);
    set('father_name', father_name || null);
    set('mother_name', mother_name || null);
    set('birth_cert_no', birth_cert_no || null);
    set('address', address || null);
    set('optional_subject', optional_subject || null);
    if (!updates.length) return res.status(400).json({ error: 'Nothing to update' });
    params.push(req.params.id);
    await pool.query(`UPDATE students SET ${updates.join(', ')} WHERE id=?`, params);
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'student_edit', 'Class teacher edited student id ' + req.params.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// New admission (class-teacher only): 6-digit code auto-generated, roll auto = MAX(roll)+1.
router.post('/students', async (req, res) => {
  const { name, dob, roll, class_id, religion, guardian_id, guardian_name, guardian_phone, guardian_email, address, father_name, mother_name, birth_cert_no, gender, blood_group, optional_subject, phone, email } = req.body || {};
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
      `INSERT INTO students (student_code, name, dob, roll, class_id, religion, guardian_id, guardian_name, guardian_phone, guardian_email, address, father_name, mother_name, birth_cert_no, gender, blood_group, optional_subject, phone, email)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [code, name, dob || null, effectiveRoll, class_id, religion || null, guardian_id || null, guardian_name || null, guardian_phone || null, guardian_email || null, address || null, father_name || null, mother_name || null, birth_cert_no || null, gender || null, blood_group || null, optional_subject || null, phone || null, email || null]
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
      // Previously decided (e.g. rejected): revive as a fresh pending request
      // instead of crashing on the unique key.
      await pool.query(
        "UPDATE class_teacher_requests SET status='pending', note=?, decided_by=NULL, decided_at=NULL WHERE id=?",
        [note || null, existing.id]
      );
      await pool.query(
        `INSERT INTO notifications (title, body, type, target_type, created_by)
         VALUES (?,?,?,?,?)`,
        ['Class teacher request', `${req.user.name} requested to be class teacher of ${cls.name} (${cls.section}). Review in the Teachers page.`, 'special', 'teacher', req.user.id]
      );
      return res.status(201).json({ ok: true, revived: true });
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
      "SELECT id, name, designation, phone FROM users WHERE role='teacher' AND active=1 ORDER BY (sort_order IS NULL), sort_order, name"
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
  const { date, records, session, override, override_reason } = req.body || {};
  if (!date || !Array.isArray(records) || records.length === 0) {
    return res.status(400).json({ error: 'date and records array required' });
  }
  // Session defaults to morning (backward compatible with old app builds).
  const sess = (session === SESSION_P5) ? SESSION_P5 : SESSION_MORNING;
  const now = new Date(); // SERVER clock is authoritative (anti-tamper).
  // Time-window guard: hard-locked outside 10:15–11:00 / 14:00–14:40 unless
  // the teacher passes override=1 (still needs admin clearance downstream —
  // the row is flagged override_by + reason for the audit trail).
  const gate = guardWindow(sess, now, override === 1 || override === true);
  if (!gate.ok) return res.status(403).json({ error: gate.reason, window_closed: true, session: sess });
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
    // Reject dropped-out (inactive) students — they must not receive marks/attendance.
    const [stRows] = await pool.query('SELECT id, name, status FROM students WHERE id IN (?)', [studentIds]);
    const inactiveNames = stRows.filter(s => s.status && s.status !== 'active').map(s => s.name);
    if (inactiveNames.length) {
      return res.status(403).json({
        error: 'Inactive student(s) cannot take attendance: ' + inactiveNames.join(', ')
      });
    }
    // Deduplicate (last entry wins) so a repeated student_id can't break the
    // multi-row ON CONFLICT upsert.
    const byId = new Map();
    for (const r of records) byId.set(Number(r.student_id), r);
    const unique = [...byId.values()];

    // Single bulk upsert (INSERT ... ON CONFLICT) for the whole class instead
    // of one query per student — critical when a 60+ student class is saved.
    // FSM note: the UNIQUE key is (student_id, date, session), so morning and
    // P5 rows coexist; re-saving the same session overwrites that session only.
    const values = unique.map(() => '(?,?,?,?,?,?,?,?)').join(',');
    const params = [];
    for (const r of unique) {
      params.push(r.student_id, date, sess, r.status, r.remark || null, req.user.id, r.is_escape ? 1 : 0,
        (override === 1 || override === true) ? (override_reason || '').slice(0, 255) : null);
    }
    await pool.query(
      `INSERT INTO attendance (student_id, date, session, status, remark, recorded_by, is_escape, override_reason) VALUES ${values}
       ON CONFLICT (student_id, date, session) DO UPDATE SET status=EXCLUDED.status, remark=EXCLUDED.remark, recorded_by=EXCLUDED.recorded_by, is_escape=EXCLUDED.is_escape, escape_detected_at=EXCLUDED.escape_detected_at, override_reason=EXCLUDED.override_reason`,
      params
    );
    // ---- FSM synthesis: recompute final_state for each student/day ----
    const synthesis = await synthesizeDay(date, unique.map(r => Number(r.student_id)));
    // Reply 200 immediately; the FCM push runs in the background so the
    // teacher app never waits on Firebase during peak-hours concurrency.
    const studentIdsForNotify = unique.map(r => r.student_id);
    res.json({ ok: true, count: unique.length, session: sess, overridden: !!gate.overridden,
      escapes: unique.filter(r => r.is_escape).map(r => Number(r.student_id)),
      truants: synthesis.truants, finals: synthesis.finals });
    setImmediate(() => {
      notifyAttendanceGuardians(req.user.id, studentIdsForNotify, date, unique, sess, synthesis)
        .catch(e => console.error('attendance push error:', e && e.message));
    });
  } catch (err) {
    console.error(err);
    if (err.status) return res.status(err.status).json({ error: err.message });
    res.status(500).json({ error: 'Server error' });
  }
});

/**
 * FSM synthesis runner: for each (student, date), read morning + P5 rows +
 * approved leave ticket, compute the final state, persist it on BOTH rows,
 * and return truants for instant alerting.
 *
 * Pure logic lives in attendance_fsm.synthesize(); this is the DB adapter.
 */
async function synthesizeDay(date, studentIds) {
  const truants = [];
  const finals = {};
  if (!studentIds.length) return { truants, finals };
  const [rows] = await pool.query(
    `SELECT a.student_id, a.session, a.status, s.name AS student_name
     FROM attendance a JOIN students s ON s.id=a.student_id
     WHERE a.date=? AND a.student_id IN (?)`, [date, studentIds]);
  const byStudent = new Map();
  for (const r of rows) {
    if (!byStudent.has(r.student_id)) byStudent.set(r.student_id, {});
    byStudent.get(r.student_id)[r.session] = r;
  }
  // Approved leave tickets covering this date (any kind counts for synthesis).
  const [tickets] = await pool.query(
    `SELECT student_id, kind FROM leave_tickets
     WHERE leave_date=? AND student_id IN (?) AND status='approved'`, [date, studentIds]);
  const leaveBy = new Map(tickets.map(t => [t.student_id, t.kind]));
  for (const [sid, sess] of byStudent) {
    const m = sess[SESSION_MORNING];
    const p = sess[SESSION_P5];
    // Map legacy mark values into FSM inputs ('present'|'absent'|'late'|leave).
    const norm = (row) => {
      if (!row) return null;
      if (String(row.status) === 'leave' || String(row.status) === 'approved_leave') return 'leave';
      return row.status;
    };
    const final = synthesize(norm(m), norm(p), leaveBy.has(sid));
    finals[sid] = final;
    await pool.query(
      `UPDATE attendance SET final_state=? WHERE date=? AND student_id=?`, [final, date, sid]);
    if (final === FINAL.TRUANT_UNAUTHORIZED) {
      truants.push({ student_id: sid, name: (m && m.student_name) || (p && p.student_name) || ('ID ' + sid) });
    }
    if (final === FINAL.LATE_ARRIVAL_UNCHECKED) {
      // Admin exception feed: possible entry-security bypass (came without morning log).
      // dedup_key => re-saves never duplicate the row; the feed shows it ONCE.
      await pool.query(
        `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, dedup_key)
         VALUES (?,?,?,?,?,?,?) ON CONFLICT (dedup_key) DO NOTHING`,
        [sid, 'Late arrival — যাচাই বাকি',
         `${(m && m.student_name) || 'শিক্ষার্থী'} সকালে absent ছিল কিন্তু ৫ম পিরিয়ডে present — entry যাচাই করুন।`,
         'attendance', 'teacher', null, `late:${date}:${sid}`]);
    }
  }
  // Instant guardian alert for truants (the core safety promise of the FSM).
  if (truants.length) {
    try {
      const tokens = await getGuardianTokens(truants.map(t => t.student_id));
      if (tokens.length) {
        const names = truants.map(t => t.name).join(', ');
        await queuePush(tokens,
          '🚨 জরুরি — সন্তান school থেকে বেরিয়ে গেছে?',
          `Notice: ${names} সকালে present ছিল কিন্তু ৫ম পিরিয়ডে (2:00 PM) absent — কোনো ছুটির আবেদন পাওয়া যায়নি। দয়া করে school-এ যোগাযোগ করুন।`,
          { type: 'attendance', date: String(date), alert: 'truancy' });
      }
      // Admin dashboard high-priority feed: dedup_key (truant:date:student)
      // guarantees ONE row per truant per day no matter how often attendance
      // is re-saved — tapping twice shows the SAME row, never a duplicate.
      for (const t of truants) {
        await pool.query(
          `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, dedup_key)
           VALUES (?,?,?,?,?,?,?) ON CONFLICT (dedup_key) DO NOTHING`,
          [t.student_id, `TRUANT — ${t.name}`,
           `${t.name} (${date}): সকালে present → ৫ম পিরিয়ডে absent, ছুটি নেই। Guardian-কে alert পাঠানো হয়েছে।`,
           'attendance', 'teacher', null, `truant:${date}:${t.student_id}`]);
      }
    } catch (e) { console.error('truancy push error:', e && e.message); }
  }
  return { truants, finals };
}

async function notifyAttendanceGuardians(teacherId, studentIds, date, records, sess, synthesis) {
  const tokens = await getGuardianTokens(studentIds);
  if (!tokens.length) return;
  const absentCount = records.filter(r => r.status !== 'present').length;
  const statusSummary = absentCount > 0
    ? `${records.length} জনের মধ্যে ${absentCount} জন অনুপস্থিত/late`
    : `সবাই present`;
  const windowBn = sess === SESSION_P5 ? '৫ম পিরিয়ড (2:00 PM)' : 'সকাল (10:15–11:00)';
  await queuePush(tokens,
    `Attendance recorded — ${date}`,
    `${windowBn} হাজিরা: ${statusSummary}. বিস্তারিত অ্যাপে দেখুন।`,
    { type: 'attendance', date: String(date), session: String(sess || 'morning') });
}

router.get('/attendance', async (req, res) => {
  const { date, session } = req.query;
  try {
    const [rows] = await pool.query(
      `SELECT a.*, s.name AS student_name, s.roll, c.id AS class_id, c.name AS class_name, c.section
       FROM attendance a JOIN students s ON a.student_id = s.id
       JOIN classes c ON s.class_id = c.id
       WHERE c.teacher_id = ? AND (? IS NULL OR a.date = ?) AND (? IS NULL OR a.session = ?)
       ORDER BY a.date DESC, s.roll LIMIT 500`,
      [req.user.id, date || null, date || null, session || null, session || null]
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Window status: which session is open NOW (server clock) + today's synthesis
// summary for the teacher's classes. Drives the app's session tabs.
router.get('/attendance/window', async (req, res) => {
  try {
    const now = new Date();
    const open = currentWindow(now);
    const today = dhakaToday(now);
    const { FINAL_BN: bn } = require('../attendance_fsm');
    const [rows] = await pool.query(
      `SELECT a.final_state, COUNT(*) AS c FROM attendance a
       JOIN students s ON s.id=a.student_id JOIN classes c ON c.id=s.class_id
       WHERE c.teacher_id=? AND a.date=? AND a.final_state IS NOT NULL
       GROUP BY a.final_state`, [req.user.id, req.query.date || today]);
    res.json({ now: now.toISOString(), open_session: open, date: req.query.date || today,
      finals: rows.map(r => ({ state: r.final_state, bn: bn[r.final_state] || r.final_state, count: Number(r.c) })) });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ---- Leave tickets: class-teacher inbox (approve/reject) + history ----
router.get('/leave-tickets', async (req, res) => {
  const status = req.query.status || 'pending';
  try {
    const [rows] = await pool.query(
      `SELECT t.*, s.name AS student_name, s.roll, c.name AS class_name, c.section
       FROM leave_tickets t JOIN students s ON s.id=t.student_id
       JOIN classes c ON c.id=s.class_id
       WHERE c.teacher_id=? AND t.status=? ORDER BY t.leave_date DESC, t.id DESC LIMIT 200`,
      [req.user.id, status]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/leave-tickets/:id/approve', async (req, res) => {
  try {
    const [[t]] = await pool.query(
      `SELECT t.* FROM leave_tickets t JOIN students s ON s.id=t.student_id
       JOIN classes c ON c.id=s.class_id WHERE t.id=? AND c.teacher_id=?`,
      [req.params.id, req.user.id]);
    if (!t) return res.status(404).json({ error: 'Ticket not found' });
    if (t.status !== 'pending') return res.status(400).json({ error: 'Ticket already ' + t.status });
    await pool.query(`UPDATE leave_tickets SET status='approved', decided_by=?, decided_at=NOW() WHERE id=?`,
      [req.user.id, req.params.id]);
    // Re-synthesize that day so an approved leave instantly clears truancy.
    await synthesizeDay(ymd(t.leave_date), [t.student_id]);
    await pool.query(
      `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, dedup_key)
       VALUES (?,?,?,?,?,?,?) ON CONFLICT (dedup_key) DO NOTHING`,
      [t.student_id, 'ছুটি অনুমোদিত', `আপনার ${t.leave_date} তারিখের ছুটির আবেদন approve হয়েছে।`, 'general', 'students', null, `leave:${t.id}:approved`]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/leave-tickets/:id/reject', async (req, res) => {
  try {
    const [[t]] = await pool.query(
      `SELECT t.* FROM leave_tickets t JOIN students s ON s.id=t.student_id
       JOIN classes c ON c.id=s.class_id WHERE t.id=? AND c.teacher_id=?`,
      [req.params.id, req.user.id]);
    if (!t) return res.status(404).json({ error: 'Ticket not found' });
    if (t.status !== 'pending') return res.status(400).json({ error: 'Ticket already ' + t.status });
    await pool.query(`UPDATE leave_tickets SET status='rejected', decided_by=?, decided_at=NOW() WHERE id=?`,
      [req.user.id, req.params.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/notify', async (req, res) => {
  const { student_ids, title, body, type, exam_id } = req.body || {};
  if (!Array.isArray(student_ids) || student_ids.length === 0) return res.status(400).json({ error: 'student_ids array required' });
  if (!title || !body) return res.status(400).json({ error: 'title and body required' });
  try {
    // Exam-linked notifications: ONLY the teacher's OWN exams (source='teacher',
    // created by me). Admin-এর exam নিয়ে class teacher guardian-কে notify
    // করতে পারবে না — সেটা শুধু admin publish-এর সময় হয়।
    let examName = null;
    if (exam_id) {
      const [[ex]] = await pool.query('SELECT id, name, source, created_by FROM exams WHERE id=?', [exam_id]);
      if (!ex) return res.status(404).json({ error: 'Exam not found' });
      if (ex.source !== 'teacher' || Number(ex.created_by) !== Number(req.user.id)) {
        return res.status(403).json({ error: 'Admin exam-এর guardian notification শুধু admin পাঠাতে পারে। নিজের নেওয়া exam-এর ক্ষেত্রেই পাঠানো যাবে।' });
      }
      examName = ex.name;
    }
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
    // Idempotent re-send: the caller passes idempotency_key (e.g. attendance
    // date+session, or exam id); same key => ON CONFLICT DO NOTHING, so the
    // SECOND tap reports "already sent" instead of duplicating the inbox.
    const idem = String((req.body && req.body.idempotency_key) || '').slice(0, 120) || null;
    const nValues = ownedIds.map(() => '(?,?,?,?,?,?,?,?)').join(',');
    const nParams = [];
    for (const sid of ownedIds) {
      nParams.push(sid, title, body, type || 'general', 'students', exam_id ? Number(exam_id) : null, req.user.id,
        idem ? `${idem}:${sid}` : null);
    }
    const before = idem
      ? (await pool.query(`SELECT COUNT(*) AS c FROM notifications WHERE dedup_key LIKE ?`, [`${idem}:%`]))[0][0].c
      : 0;
    await pool.query(
      `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, created_by, dedup_key)
       VALUES ${nValues} ON CONFLICT (dedup_key) DO NOTHING`,
      nParams
    );
    const after = idem
      ? (await pool.query(`SELECT COUNT(*) AS c FROM notifications WHERE dedup_key LIKE ?`, [`${idem}:%`]))[0][0].c
      : ownedIds.length;
    const already = idem ? Number(after) <= Number(before) && Number(before) > 0 : false;
    const tokens = await getGuardianTokens(ownedIds);
    // Same rule for the push itself: already-sent => skip the push, report it.
    const queued = already ? { skipped: 'already_sent' } : await queuePush(tokens, title, body, { type: type || 'general' });
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'notify', 'Sent "' + title + '" to ' + ownedIds.length + ' guardian(s)' + (already ? ' (already sent — deduped)' : '')]);
    res.status(201).json({ ok: true, count: ownedIds.length, already_sent: already, push: queued });
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
         VALUES (?,?,?,?,?,?,DATE_ADD(NOW(), INTERVAL 5 HOUR))
         ON CONFLICT (student_id, subject_id, ct_no) DO UPDATE SET marks=EXCLUDED.marks, full_marks=EXCLUDED.full_marks,
           edit_until=CASE WHEN ct_marks.edit_until > NOW() THEN DATE_ADD(NOW(), INTERVAL 5 HOUR) ELSE ct_marks.edit_until END`,
        [r.student_id, r.subject_id, r.ct_no || 1, r.marks, r.full_marks || 25, req.user.id]
      );
    }
    res.json({ ok: true, count: records.length, message: 'CT marks saved. Editable for 5 hours.' });
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
    res.json(await attachFilesTo(rows, 'id'));
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

router.get('/homework/:id/attachments', async (req, res) => {
  try {
    const hw = await homeworkWriteAccess(req.params.id, req.user.id);
    if (hw === null) return res.status(404).json({ error: 'Homework not found' });
    if (hw === false) {
      // read-only: visible in own class/subject list?
      const [mine] = await pool.query(
        `SELECT h.id FROM homework h WHERE h.id=? AND (h.class_id IN (SELECT id FROM classes WHERE teacher_id=?)
          OR h.subject_id IN (SELECT id FROM subjects WHERE teacher_id=?))`,
        [req.params.id, req.user.id, req.user.id]);
      if (!mine.length) return res.status(403).json({ error: 'Not your homework' });
    }
    const [rows] = await pool.query(
      `SELECT id, homework_id, file_name, file_path, mime_type, file_size, created_at
       FROM homework_attachments WHERE homework_id=? ORDER BY id`, [req.params.id]);
    res.json(rows.map(a => ({ ...a, url: '/uploads/homework/' + a.file_path })));
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/homework/:id/attachments', (req, res) => {
  (async () => {
    const hw = await homeworkWriteAccess(req.params.id, req.user.id);
    if (hw === null) return res.status(404).json({ error: 'Homework not found' });
    if (hw === false) return res.status(403).json({ error: 'Only the homework owner / class teacher can attach files' });
    hwUpload.single('file')(req, res, async (err) => {
      if (err) return res.status(400).json({ error: err.message || 'Upload failed' });
      if (!req.file) return res.status(400).json({ error: 'file field required (image or PDF, max 8MB)' });
      try {
        const [ins] = await pool.query(
          `INSERT INTO homework_attachments (homework_id, file_name, file_path, mime_type, file_size, uploaded_by)
           VALUES (?,?,?,?,?,?)`,
          [req.params.id, req.file.originalname.slice(0, 255), req.file.filename,
           req.file.mimetype, req.file.size, req.user.id]);
        await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
          [req.user.id, 'homework_attach', `File ${req.file.originalname} on homework ${req.params.id}`]);
        res.status(201).json({ id: ins.insertId, url: '/uploads/homework/' + req.file.filename });
      } catch (e) { console.error(e); res.status(500).json({ error: 'Server error' }); }
    });
  })().catch(err => { console.error(err); res.status(500).json({ error: 'Server error' }); });
});

router.delete('/homework/attachments/:aid', async (req, res) => {
  try {
    const [[a]] = await pool.query(
      `SELECT ha.*, h.created_by, c.teacher_id AS class_teacher
       FROM homework_attachments ha JOIN homework h ON h.id=ha.homework_id
       JOIN classes c ON c.id=h.class_id WHERE ha.id=?`, [req.params.aid]);
    if (!a) return res.status(404).json({ error: 'Attachment not found' });
    if (Number(a.created_by) !== Number(req.user.id) && Number(a.class_teacher) !== Number(req.user.id)) {
      return res.status(403).json({ error: 'Only the homework owner / class teacher can delete files' });
    }
    await pool.query('DELETE FROM homework_attachments WHERE id=?', [req.params.aid]);
    try {
      const fp = path.join(hwUploadDir, path.basename(a.file_path));
      if (fs.existsSync(fp)) fs.unlinkSync(fp);
    } catch (_) {}
    res.json({ ok: true });
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
  const d = req.query.date || dhakaToday();
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

// Promotion review (READ-ONLY) for the CLASS TEACHER of the class.
// Scientific rule enforced: ONLY the class teacher may drive promotions —
// a subject teacher of the class sees nothing here. The class teacher sets
// the grace limit (PUT /promotion/grace-limit, 0..11 failed subjects) and
// reviews the auto-decisions; EXECUTION stays admin-only (2-key rule).
router.get('/promotion/review', async (req, res) => {
  const cid = Number(req.query.class_id);
  const eid = Number(req.query.event_id);
  if (!cid || !eid) return res.status(400).json({ error: 'class_id and event_id required' });
  try {
    // Class-teacher gate (NOT subject-teacher): classes.teacher_id must be me.
    const [[mine]] = await pool.query(
      'SELECT id, name FROM classes WHERE id=? AND teacher_id=?', [cid, req.user.id]);
    if (!mine) {
      return res.status(403).json({ error: 'শুধু ওই class-এর class teacher promotion review দেখতে পারেন।' });
    }
    // Promotion source rule: Class 6–9 ← published ANNUAL event;
    // Class 10 ← published TEST event. Anything else is rejected with the
    // reason (prevents promoting off a Half-Yearly / Pre-Test by mistake).
    const [[ev]] = await pool.query(
      `SELECT e.id, e.name, e.year, e.exam_kind, e.is_published FROM exam_events e
        WHERE e.id=? AND EXISTS (
          SELECT 1 FROM exams x WHERE x.event_id=e.id AND x.class_id=?
        )`, [eid, cid]);
    if (!ev) return res.status(404).json({ error: 'No exam event found for this class/event' });
    const clsName = String(mine.name || '');
    const isClass10 = /class\s*10/i.test(clsName);
    const needKind = isClass10 ? 'test' : 'annual';
    if (String(ev.exam_kind) !== needKind) {
      return res.status(400).json({ error:
        isClass10
          ? `Class 10 promotion শুধু TEST event থেকে হয় — “${ev.name}” (${ev.exam_kind}) দিয়ে promotion হবে না।`
          : `Class 6–9 promotion শুধু ANNUAL event থেকে হয় — “${ev.name}” (${ev.exam_kind}) দিয়ে promotion হবে না।` });
    }
    if (Number(ev.is_published) !== 1) {
      return res.status(400).json({ error: 'Event এখনো publish হয়নি — publish-এর পর promotion review করা যাবে।' });
    }
    const [[cls]] = await pool.query('SELECT id, name, group_name FROM classes WHERE id=?', [cid]);
    // The review endpoint already gated class-teacher + annual/test + published;
    // grace reads/writes the SAME rule the admin engine uses (shared key).
    const graceKey = isClass10 ? 'test' : 'annual';
    const [[grace]] = await pool.query(
      'SELECT grace_failed FROM promotion_grace WHERE class_id=? AND exam_type=?', [cid, graceKey]);
    const graceFailed = grace ? Number(grace.grace_failed) : 0;
    const [students] = await pool.query(
      'SELECT id, name, student_code, roll FROM students WHERE class_id=? ORDER BY roll', [cid]);
    const [promos] = await pool.query(
      `SELECT student_id, decision, promoted_roll FROM promotions WHERE event_id=? AND class_id=?`,
      [eid, cid]);
    const promoByStudent = {};
    promos.forEach(p => { promoByStudent[p.student_id] = p; });

    const review = [];
    for (const s of students) {
      const r = await computeResult(s.id, eid);
      if (!r) continue;
      const failedNames = (r.families || [])
        .filter((f) => !f.is_optional && f.letter_grade === 'F')
        .map((f) => f.subject);
      const failCount = failedNames.length;
      let decision = 'retained';
      if (r.result_status !== 'ABSENT' && failCount === 0) decision = 'promoted';
      else if (r.result_status !== 'ABSENT' && failCount <= graceFailed) decision = 'grace_promoted';
      const done = promoByStudent[s.id];
      review.push({
        id: s.id, name: s.name, student_code: s.student_code, roll: s.roll,
        final_gpa: r.final_gpa, result_status: r.result_status,
        fail_count: failCount, failed_subjects: failedNames, decision,
        executed: done ? done.decision : null,
        promoted_roll: done ? done.promoted_roll : null,
      });
    }
    review.sort((a, b) => Number(b.final_gpa) - Number(a.final_gpa) || a.roll - b.roll);
    res.json({ event: ev, class: cls, grace_failed: graceFailed, total: review.length, review });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Class-teacher grace control: "কত বিষয় পর্যন্ত fail হলেও শর্তসাপেক্ষে
// promotion" — 0..11. Same shared rule the admin engine reads, so both panels
// can never disagree (single source of truth). Class-teacher-only.
router.put('/promotion/grace-limit', async (req, res) => {
  const cid = Number(req.body && req.body.class_id);
  const g = Number(req.body && req.body.grace_failed);
  if (!cid || !Number.isInteger(g) || g < 0 || g > 11) {
    return res.status(400).json({ error: 'class_id and grace_failed (0..11) required' });
  }
  try {
    const [[mine]] = await pool.query(
      'SELECT id, name FROM classes WHERE id=? AND teacher_id=?', [cid, req.user.id]);
    if (!mine) {
      return res.status(403).json({ error: 'শুধু ওই class-এর class teacher grace limit বসাতে পারেন।' });
    }
    const needKind = /class\s*10/i.test(String(mine.name || '')) ? 'test' : 'annual';
    await pool.query(
      `INSERT INTO promotion_grace (class_id, exam_type, grace_failed, notes)
       VALUES (?,?,?,?)
       ON CONFLICT (class_id, exam_type) DO UPDATE SET grace_failed=EXCLUDED.grace_failed, notes=EXCLUDED.notes, updated_at=NOW()`,
      [cid, needKind, g, `set by class teacher ${req.user.name || req.user.id}`]);
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'promote_grace_ct', `Class teacher set grace=${g} for class ${cid} (${needKind})`]);
    res.json({ ok: true, class_id: cid, exam_type: needKind, grace_failed: g });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// =====================================================================
// EXAM COVERAGE + MARK EDIT REQUESTS + EVENT RESULTS + SEAT/ADMIT PDFs
// - Coverage: কতজন student-এর number entry হয়েছে / কত subject-এর number
//   add হয়েছে — class teacher teacher-app থেকে দেখে।
// - ৫ ঘণ্টা পার হলে re-edit শুধু admin অনুমতিতে: teacher request পাঠায়।
// - Event result: নিজের class-এর student-wise result (admin-created বা
//   self-created — উভয় exam-এর)।
// - Seat plan + admit card PDF: admin-created exam-এর জন্য class teacher
//   দেখতে/download করতে পারে।
// =====================================================================

// Per-exam coverage (own accessible exams only).
router.get('/exams/:id/coverage', async (req, res) => {
  try {
    const exam = await teacherCanAccessExam(req.params.id, req.user.id);
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
      exam_id: exam.id, student_count: rows.length,
      entered_count: entered.length, pending_count: rows.length - entered.length,
      entered, pending: rows.filter(r => r.mark_id == null)
    });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Admin inbox notification when one of THEIR classes' events just became
// fully covered (all syllabus subjects + all students have marks): the green
// light for review → tabulation/merit → publish.
async function notifyAdminsEventReady(eventId, classId) {
  try {
    const [[ev]] = await pool.query('SELECT id, name FROM exam_events WHERE id=?', [eventId]);
    const [[cls]] = await pool.query('SELECT id, name, section, group_name FROM classes WHERE id=?', [classId]);
    if (!ev || !cls) return;
    const label = `${cls.name}${cls.group_name ? ' (' + cls.group_name + ')' : (cls.section ? ' — ' + cls.section : '')}`;
    const title = 'Result Ready — ' + ev.name;
    const body = `${label}-এ সব subject-এর number entry সম্পূর্ণ (100%)। Admin review → Tabulation/Merit → Publish করুন।`;
    const [[exists]] = await pool.query(
      `SELECT id FROM notifications WHERE related_id=? AND class_id=? AND type='general'
        AND title=? AND created_at > DATE_SUB(NOW(), INTERVAL 1 DAY) LIMIT 1`,
      [eventId, classId, title]);
    if (exists) return; // already pinged today
    await pool.query(
      `INSERT INTO notifications (class_id, title, body, type, target_type, related_id)
       VALUES (?,?,?,?,?,?)`,
      [classId, title, body, 'general', 'guardians', eventId]);
  } catch (e) { /* never block the marks save */ }
}

// Check whether a class+event just hit 100% coverage and, if so, send the
// admin inbox ping. Called after every successful mark submit.
async function maybeNotifyEventReady(eventId, classId) {
  try {
    const [[stu]] = await pool.query('SELECT COUNT(*) AS c FROM students WHERE class_id=?', [classId]);
    const [[wm]] = await pool.query(
      `SELECT COUNT(DISTINCT m.student_id) AS c FROM marks m JOIN exams x ON x.id=m.exam_id
        WHERE x.event_id=? AND x.class_id=?`, [eventId, classId]);
    const [[asg]] = await pool.query('SELECT COUNT(*) AS c FROM subjects WHERE class_id=?', [classId]);
    const [[swm]] = await pool.query(
      `SELECT COUNT(DISTINCT x.subject_id) AS c FROM exams x JOIN marks m ON m.exam_id=x.id
        WHERE x.event_id=? AND x.class_id=?`, [eventId, classId]);
    const subjTotal = Math.max(Number(asg.c || 0), 0);
    if (subjTotal > 0 && Number(swm.c) >= subjTotal && Number(stu.c) > 0 && Number(wm.c) >= Number(stu.c)) {
      await notifyAdminsEventReady(eventId, classId);
    }
  } catch (e) { /* never block the marks save */ }
}

// Scientific auto-result: as soon as the LAST subject of a class gets its
// marks, the full GPA/grades are computed and cached into `results` (final),
// and admins are pinged. Until then the app shows a live PARTIAL preview
// (computeResult on the fly) — so marks entry works standalone with no manual
// "compute" step, yet the persisted final result only appears when complete.
async function autoFinalizeClassResults(eventId, classId) {
  try {
    const [[stu]] = await pool.query('SELECT COUNT(*) AS c FROM students WHERE class_id=?', [classId]);
    if (Number(stu.c) === 0) return { complete: false };
    const [[asg]] = await pool.query('SELECT COUNT(*) AS c FROM subjects WHERE class_id=?', [classId]);
    const [[swm]] = await pool.query(
      `SELECT COUNT(DISTINCT x.subject_id) AS c FROM exams x JOIN marks m ON m.exam_id=x.id
        WHERE x.event_id=? AND x.class_id=?`, [eventId, classId]);
    const subjTotal = Number(asg.c || 0);
    if (!(subjTotal > 0 && Number(swm.c) >= subjTotal)) return { complete: false };
    const [students] = await pool.query('SELECT id FROM students WHERE class_id=?', [classId]);
    let computed = 0;
    for (const s of students) {
      const r = await computeResult(s.id, eventId);
      if (!r) continue;
      await pool.query(
        `INSERT INTO results (student_id, exam_id, total_gpa_without_4th, gpa_4th_bonus, final_gpa, result_status)
         VALUES (?,?,?,?,?,?)
         ON CONFLICT (student_id, exam_id) DO UPDATE SET total_gpa_without_4th=EXCLUDED.total_gpa_without_4th,
           gpa_4th_bonus=EXCLUDED.gpa_4th_bonus, final_gpa=EXCLUDED.final_gpa,
           result_status=EXCLUDED.result_status, computed_at=NOW()`,
        [s.id, eventId, r.total_gpa_without_4th, r.gpa_4th_bonus, r.final_gpa, r.result_status]);
      computed++;
    }
    await notifyAdminsEventReady(eventId, classId);
    return { complete: true, computed };
  } catch (e) { return { complete: false, error: e.message }; }
}

// Teacher asks admin for re-edit permission (locked mark only).
// Rule: only the mark's OWNER (assigned subject teacher) may request.
// A class teacher can ENDORSE (see below) but never request for others.
router.post('/marks/:id/request-unlock', async (req, res) => {
  const { reason } = req.body || {};
  try {
    const [[m]] = await pool.query('SELECT id, exam_id, student_id, edit_until, recorded_by FROM marks WHERE id=?', [req.params.id]);
    if (!m) return res.status(404).json({ error: 'Mark not found' });
    const exam = await teacherCanAccessExam(m.exam_id, req.user.id);
    if (!exam) return res.status(403).json({ error: 'Not your exam' });
    if (Number(exam.can_enter) !== 1) {
      return res.status(403).json({ error: 'শুধু ওই subject-এর assigned teacher re-edit request পাঠাতে পারেন।' });
    }
    if (m.recorded_by && Number(m.recorded_by) !== Number(req.user.id) && exam.source === 'admin') {
      return res.status(403).json({ error: 'এই number অন্য teacher দিয়েছেন — শুধু তিনিই request পাঠাতে পারেন।' });
    }
    if (m.edit_until && new Date(m.edit_until) > new Date()) {
      return res.status(400).json({ error: 'এই number এখনো editable আছে — সরাসরি edit করুন।' });
    }
    try {
      const [r] = await pool.query(
        `INSERT INTO mark_edit_requests (mark_id, student_id, exam_id, teacher_id, reason)
         VALUES (?,?,?,?,?)`,
        [m.id, m.student_id, m.exam_id, req.user.id, (reason || '').slice(0, 500) || null]);
      res.status(201).json({ ok: true, id: r.insertId });
    } catch (e) {
      // 23505 = PG unique violation, ER_DUP_ENTRY/1062 = MySQL/MariaDB.
      if (e.code === '23505' || e.code === 'ER_DUP_ENTRY' || e.errno === 1062) {
        return res.status(409).json({ error: 'এই mark-এর জন্য ইতিমধ্যে একটি pending request আছে।' });
      }
      throw e;
    }
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/mark-edit-requests', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT r.*, s.name AS student_name, s.roll, e.name AS exam_name, sub.name AS subject_name,
              (SELECT COUNT(*) FROM mark_edit_endorsements en WHERE en.request_id=r.id) AS endorsements
       FROM mark_edit_requests r
       JOIN students s ON s.id=r.student_id
       JOIN exams e ON e.id=r.exam_id
       JOIN subjects sub ON sub.id=e.subject_id
       WHERE r.teacher_id=? ORDER BY r.id DESC LIMIT 100`,
      [req.user.id]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ---- Class-teacher endorsement: "আমি দেখেছি, admin-কে approve করতে বলছি"
// The class teacher of the exam's class may endorse (or withdraw) another
// teacher's pending re-edit request. This is a SIGNAL only — it never edits
// numbers and never replaces admin approval (2-key rule stays: admin decides).
router.post('/mark-edit-requests/:id/endorse', async (req, res) => {
  try {
    const [[r]] = await pool.query(
      `SELECT r.*, e.class_id, c.teacher_id AS class_teacher_id
       FROM mark_edit_requests r JOIN exams e ON e.id=r.exam_id
       JOIN classes c ON c.id=e.class_id WHERE r.id=?`, [req.params.id]);
    if (!r) return res.status(404).json({ error: 'Request not found' });
    if (Number(r.class_teacher_id) !== Number(req.user.id)) {
      return res.status(403).json({ error: 'শুধু ওই class-এর class teacher endorse করতে পারেন।' });
    }
    if (Number(r.teacher_id) === Number(req.user.id)) {
      return res.status(400).json({ error: 'নিজের request-এ endorse দরকার নেই।' });
    }
    if (r.status !== 'pending') return res.status(400).json({ error: 'Request already ' + r.status });
    await pool.query(
      `INSERT INTO mark_edit_endorsements (request_id, class_teacher_id)
       VALUES (?,?) ON CONFLICT (request_id, class_teacher_id) DO NOTHING`,
      [r.id, req.user.id]);
    await pool.query(
      `INSERT INTO notifications (title, body, type, target_type, related_id)
       VALUES (?,?,?,?,?)`,
      ['Endorsement — re-edit request',
       `${req.user.name} (class teacher) request #${r.id}-কে endorse করেছেন — admin review করুন।`,
       'special', 'teacher', r.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/mark-edit-requests/:id/endorse', async (req, res) => {
  try {
    const [[r]] = await pool.query(
      `SELECT r.*, e.class_id, c.teacher_id AS class_teacher_id
       FROM mark_edit_requests r JOIN exams e ON e.id=r.exam_id
       JOIN classes c ON c.id=e.class_id WHERE r.id=?`, [req.params.id]);
    if (!r) return res.status(404).json({ error: 'Request not found' });
    if (Number(r.class_teacher_id) !== Number(req.user.id)) {
      return res.status(403).json({ error: 'শুধু ওই class-এর class teacher প্রত্যাহার করতে পারেন।' });
    }
    await pool.query('DELETE FROM mark_edit_endorsements WHERE request_id=? AND class_teacher_id=?',
      [r.id, req.user.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Events visible to this teacher: class-teacher classes or own created exams.
// Component spec shared by current-exam / entry-subjects: non-null component
// totals define the NCTB entry columns (empty = single-total entry).
function examComponents(s) {
  return [
    ...(s.cq_full != null ? [{ key: 'cq', label: 'CQ', full: Number(s.cq_full) }] : []),
    ...(s.mcq_full != null ? [{ key: 'mcq', label: 'MCQ', full: Number(s.mcq_full) }] : []),
    ...(s.practical_full != null ? [{ key: 'practical', label: 'Practical', full: Number(s.practical_full) }] : []),
    ...(s.written_full != null ? [{ key: 'written', label: 'Written', full: Number(s.written_full) }] : []),
    ...(s.ca_full != null ? [{ key: 'ca', label: 'CA', full: Number(s.ca_full) }] : []),
  ];
}

// The CURRENT exam (test-kind, live session, not yet published) + this
// teacher's classes with per-subject live entry status. Powers the redesigned
// Exam tab: one current exam → my-subjects view OR all-subjects (admin) view.
router.get('/current-exam', async (req, res) => {
  try {
    const [[sess]] = await pool.query(
      'SELECT id, name FROM sessions WHERE is_active=1 ORDER BY id LIMIT 1');
    let [[ev]] = await pool.query(
      "SELECT * FROM exam_events WHERE exam_kind='test' AND session_id=? AND is_published=0 ORDER BY id LIMIT 1",
      [sess ? sess.id : 0]);
    if (!ev) {
      [[ev]] = await pool.query(
        "SELECT * FROM exam_events WHERE exam_kind='test' AND session_id=? ORDER BY id LIMIT 1",
        [sess ? sess.id : 0]);
    }
    if (!ev) {
      [[ev]] = await pool.query(
        "SELECT * FROM exam_events WHERE exam_kind='test' ORDER BY id DESC LIMIT 1");
    }
    if (!ev) return res.json({ event: null, session: sess || null, classes: [] });
    const [classes] = await pool.query(
      `SELECT DISTINCT c.id AS class_id, c.name AS class_name, c.section, c.group_name,
              CASE WHEN c.teacher_id=? THEN 1 ELSE 0 END AS is_class_teacher,
              (SELECT COUNT(*) FROM students st WHERE st.class_id=c.id) AS student_count
       FROM classes c
       JOIN exams x ON x.event_id=? AND x.class_id=c.id
       WHERE (c.teacher_id=? OR x.created_by=? OR EXISTS(SELECT 1 FROM subjects sub WHERE sub.id=x.subject_id AND sub.teacher_id=?))
       ORDER BY c.name, c.section, c.group_name`,
      [req.user.id, ev.id, req.user.id, req.user.id, req.user.id]);
    for (const c of classes) {
      const [subs] = await pool.query(
        `SELECT sub.id AS subject_id, sub.name AS subject_name, sub.teacher_id, sub.full_marks,
                sub.cq_full, sub.mcq_full, sub.practical_full, sub.written_full, sub.ca_full,
                u.name AS subject_teacher_name,
                (sub.teacher_id = ?) AS is_mine,
                (SELECT x.id FROM exams x WHERE x.event_id=? AND x.class_id=? AND x.subject_id=sub.id LIMIT 1) AS exam_id,
                (SELECT x.status FROM exams x WHERE x.event_id=? AND x.class_id=? AND x.subject_id=sub.id LIMIT 1) AS exam_status,
                (SELECT x.entry_open FROM exams x WHERE x.event_id=? AND x.class_id=? AND x.subject_id=sub.id LIMIT 1) AS exam_entry_open,
                (SELECT x.entry_deadline FROM exams x WHERE x.event_id=? AND x.class_id=? AND x.subject_id=sub.id LIMIT 1) AS exam_entry_deadline,
                (SELECT COUNT(*) FROM marks m JOIN exams x ON x.id=m.exam_id
                  WHERE x.event_id=? AND x.class_id=? AND x.subject_id=sub.id) AS entered_count
         FROM subjects sub LEFT JOIN users u ON u.id=sub.teacher_id
         WHERE sub.class_id=? ORDER BY sub.name`,
        [req.user.id, ev.id, c.class_id, ev.id, c.class_id, ev.id, c.class_id, ev.id, c.class_id, ev.id, c.class_id, c.class_id]);
      c.subjects = subs.map(s => ({
        ...s,
        is_mine: Number(s.is_mine) === 1,
        entered_count: Number(s.entered_count),
        student_count: Number(c.student_count),
        submitted: Number(s.entered_count) > 0,
        exam_published: s.exam_status === 'published',
        entry_open: (s.exam_entry_open == null) ? 1 : Number(s.exam_entry_open),
        components: examComponents(s),
      }));
      c.my_subjects = c.subjects.filter(s => s.is_mine).length;
      c.done_subjects = c.subjects.filter(s => s.submitted).length;
      c.total_subjects = c.subjects.length;
    }
    res.json({ event: ev, session: sess || null, classes });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/events', async (req, res) => {
  try {
    const [events] = await pool.query(
      `SELECT DISTINCT e.*, s.name AS session_name FROM exam_events e
       LEFT JOIN sessions s ON s.id=e.session_id
       JOIN exams x ON x.event_id=e.id
       LEFT JOIN classes c ON c.id=x.class_id
       WHERE (c.teacher_id=? OR x.created_by=? OR EXISTS(SELECT 1 FROM subjects sub WHERE sub.class_id=c.id AND sub.teacher_id=?))
         AND (e.is_published = 1
              OR (e.entry_open = 1 AND EXISTS(
                  SELECT 1 FROM exams ex
                  WHERE ex.event_id = e.id
                    AND ex.status <> 'published'
                    AND (
                        ex.created_by = ?
                        OR c.teacher_id = ?
                        OR ex.subject_id IN (SELECT id FROM subjects WHERE class_id=c.id AND teacher_id=?)
                    )
                  AND ex.entry_open = 1
              ))
             )
       ORDER BY e.is_published ASC, e.id DESC`,
      [req.user.id, req.user.id, req.user.id, req.user.id, req.user.id, req.user.id]);
    for (const ev of events) {
      // If event has class_ids specified, only show those classes that teacher has access to
      let classFilter = '';
      const params = [ev.id, ev.id, ev.id, ev.id, req.user.id, req.user.id];
      try {
        if (ev.class_ids) {
          let cids = typeof ev.class_ids === 'string' ? JSON.parse(ev.class_ids) : ev.class_ids;
          if (Array.isArray(cids) && cids.length) {
            classFilter = `AND c.id IN (${cids.map(()=>'?').join(',')})`;
            for (const cid of cids) params.push(cid);
          }
        }
      } catch(e){}
      const [cls] = await pool.query(
        `SELECT DISTINCT c.id AS class_id, c.name AS class_name, c.section, c.group_name,
          (SELECT COUNT(*) FROM students st WHERE st.class_id=c.id) AS student_count,
          (SELECT COUNT(DISTINCT m.student_id) FROM marks m JOIN exams xx ON xx.id=m.exam_id WHERE xx.event_id=? AND xx.class_id=c.id) AS students_with_marks,
          (SELECT COUNT(DISTINCT xx.subject_id) FROM exams xx JOIN marks m ON m.exam_id=xx.id WHERE xx.event_id=? AND xx.class_id=c.id) AS subjects_with_marks,
          (SELECT COUNT(*) FROM exams xx WHERE xx.event_id=? AND xx.class_id=c.id) AS subject_count
         FROM exams x JOIN classes c ON c.id=x.class_id
         WHERE x.event_id=? AND (c.teacher_id=? OR x.created_by=? OR EXISTS(SELECT 1 FROM subjects sub WHERE sub.class_id=c.id AND sub.teacher_id=?)) ${classFilter}
         ORDER BY c.name, c.section, c.group_name`,
        [ev.id, ev.id, ev.id, ev.id, req.user.id, req.user.id, req.user.id, ...params.slice(6)]);
      for (const c of cls) {
        const [subs] = await pool.query(
          `SELECT sub.name AS subject_name, sub.full_marks, sub.teacher_id,
                  (u.name) AS subject_teacher_name, x.id AS exam_id, x.status,
                  (SELECT COUNT(*) FROM marks m WHERE m.exam_id=x.id) AS entered_count
           FROM exams x JOIN subjects sub ON sub.id=x.subject_id
           LEFT JOIN users u ON u.id=sub.teacher_id
           WHERE x.event_id=? AND x.class_id=? ORDER BY sub.name`,
          [ev.id, c.class_id]);
        c.subjects = subs.map(s => ({
          ...s,
          is_mine: Number(s.teacher_id) === Number(req.user.id),
        }));
      }
      ev.my_classes = cls;
    }
    res.json(events.filter(e => e.my_classes && e.my_classes.length));
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Access gate for one class inside one exam event.
//   - class teacher        -> full result scope (supervisor)
//   - creator of an exam   -> full result scope (their own test)
//   - subject teacher      -> SCOPED: only the subjects they teach
// A subject teacher is a legitimate participant: they own one subject of the
// class. Without this branch the whole event screen 403'd for them and the
// number-entry sheet could never open.
async function teacherEventClassAccess(eventId, classId, userId) {
  const [[ev]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [eventId]);
  if (!ev) return { error: 'Event not found', status: 404 };
  const [[cls]] = await pool.query('SELECT id, name, section, group_name, teacher_id FROM classes WHERE id=?', [classId]);
  if (!cls) return { error: 'Class not found', status: 404 };
  const [[mine]] = await pool.query('SELECT id FROM classes WHERE id=? AND teacher_id=?', [classId, userId]);
  const [[created]] = await pool.query(
    'SELECT id FROM exams WHERE event_id=? AND class_id=? AND created_by=? LIMIT 1', [eventId, classId, userId]);
  const [teaches] = await pool.query(
    'SELECT id FROM subjects WHERE class_id=? AND teacher_id=? ORDER BY id', [classId, userId]);
  const subjectIds = teaches.map(t => Number(t.id));
  if (!mine && !created && subjectIds.length === 0) {
    return { error: 'এই class-এর result দেখার অনুমতি নেই', status: 403 };
  }
  const scoped = !mine && !created && subjectIds.length > 0;
  return { ev, cls, isClassTeacher: !!mine, isCreator: !!created, scoped, subjectIds };
}

// Marks of ONE event limited to the given subjects, keyed by student id.
// Used for the subject-scoped result view (no other subject's marks leak).
async function marksForSubjects(classId, eventId, subjectIds) {
  const out = new Map();
  if (!subjectIds || !subjectIds.length) return out;
  const scope = inClause('sub.id', subjectIds);
  const [rows] = await pool.query(
    `SELECT m.student_id, m.marks, m.total, m.cq, m.mcq, m.practical, m.written, m.ca,
            m.absent, m.comment, sub.name AS subject_name, sub.full_marks,
            sub.cq_full, sub.mcq_full, sub.practical_full, sub.written_full, sub.ca_full
     FROM marks m
     JOIN exams e ON m.exam_id = e.id
     JOIN subjects sub ON e.subject_id = sub.id
     WHERE e.event_id = ? AND e.class_id = ?
       AND ${scope.sql}
     ORDER BY m.student_id`,
    [eventId, classId, ...scope.params]);
  for (const r of rows) {
    if (!out.has(Number(r.student_id))) out.set(Number(r.student_id), []);
    out.get(Number(r.student_id)).push(r);
  }
  return out;
}

// Student-wise result of one class in an event (admin-created or self).
router.get('/events/:id/result', async (req, res) => {
  const classId = Number(req.query.class_id);
  if (!classId) return res.status(400).json({ error: 'class_id required' });
  try {
    const acc = await teacherEventClassAccess(req.params.id, classId, req.user.id);
    if (acc.error) return res.status(acc.status).json({ error: acc.error });
    const [students] = await pool.query(
      'SELECT id, name, roll, student_code FROM students WHERE class_id=? ORDER BY roll', [classId]);
    // Subject teachers only ever see their own subject(s).
    const subjScope = inClause('x.subject_id', acc.scoped ? acc.subjectIds : []);
    const [subjRows] = await pool.query(
      `SELECT x.id AS exam_id, sub.name AS subject_name,
        (SELECT COUNT(*) FROM marks m WHERE m.exam_id=x.id) AS entered_count
       FROM exams x JOIN subjects sub ON sub.id=x.subject_id
       WHERE x.event_id=? AND x.class_id=?${acc.scoped ? ' AND ' + subjScope.sql : ''} ORDER BY sub.name`,
      [req.params.id, classId, ...(acc.scoped ? subjScope.params : [])]);
    const rows = [];
    const famSet = new Set();
    if (acc.scoped) {
      // ---- Subject-scoped view: one column per OWN subject, no class GPA,
      // no merit list, no other subject's marks.
      const myMarks = await marksForSubjects(classId, Number(req.params.id), acc.subjectIds);
      const level = classLevelOf(acc.cls.name);
      for (const stu of students) {
        const famMap = {};
        for (const m of (myMarks.get(Number(stu.id)) || [])) {
          const key = m.subject_name;
          famSet.add(key);
          if (m.absent) {
            famMap[key] = { subject: key, total: 0, full: Number(m.total || m.full_marks || 100),
              scaled: 0, letter_grade: 'Absent', grade_point: 0, absent: true, is_optional: false,
              papers: [key], paper_details: [] };
            continue;
          }
          const g = gradePaper(level, m, { name: key, full_marks: m.full_marks },
            { cq_full: m.cq_full, mcq_full: m.mcq_full, practical_full: m.practical_full,
              written_full: m.written_full, ca_full: m.ca_full });
          famMap[key] = { subject: key, total: g.total, full: g.full, scaled: g.scaled,
            letter_grade: g.letter_grade, grade_point: g.grade_point, absent: false,
            is_optional: false, papers: [key],
            paper_details: [{ subject_name: key, marks: m.marks, cq: m.cq, mcq: m.mcq,
              practical: m.practical, written: m.written, ca: m.ca, absent: false,
              letter_grade: g.letter_grade, grade_point: g.grade_point }] };
        }
        rows.push({ ...stu, families: famMap,
          total_marks: null, total_full: null, fourth_score: null,
          gpa_4th_bonus: null, final_gpa: null, result_status: null, scoped: true });
      }
    } else {
      for (const stu of students) {
        const r = await computeResult(stu.id, Number(req.params.id));
        const famMap = {};
        if (r) r.families.forEach(f => { famSet.add(f.subject); famMap[f.subject] = f; });
        rows.push({ ...stu, families: famMap,
          total_marks: r ? r.total_marks : null,
          total_full: r ? r.total_full : null,
          fourth_score: r ? r.fourth_score : null,
          gpa_4th_bonus: r ? r.gpa_4th_bonus : null,
          final_gpa: r ? r.final_gpa : null,
          result_status: r ? r.result_status : null });
      }
    }
    const subjects = Array.from(famSet);
    rows.forEach(row => { row._families = subjects.map(s => row.families[s] || null); });
    // Merit ranking with NCTB tie-breakers: GPA -> 4th-subject bonus ->
    // total marks -> 4th score -> roll. (Class-scoped view only.)
    if (!acc.scoped) {
      [...rows].filter(r => r.final_gpa != null && r.result_status === 'PASSED')
        .sort((a, b) =>
          (Number(b.final_gpa) - Number(a.final_gpa)) ||
          (Number(b.gpa_4th_bonus || 0) - Number(a.gpa_4th_bonus || 0)) ||
          (Number(b.total_marks || 0) - Number(a.total_marks || 0)) ||
          (Number(b.fourth_score || 0) - Number(a.fourth_score || 0)) ||
          (Number(a.roll) - Number(b.roll)))
        .forEach((r, i) => { r.position = i + 1; });
    }
    const withResult = acc.scoped
      ? rows.filter(r => Object.keys(r.families || {}).length > 0).length
      : rows.filter(r => r.final_gpa != null).length;
    res.json({
      event: acc.ev, class: acc.cls,
      coverage: {
        student_count: students.length, with_result: withResult,
        subject_count: subjRows.length,
        subjects_with_marks: subjRows.filter(s => Number(s.entered_count) > 0).length,
        subjects: subjRows
      },
      subjects, rows
    });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Event coverage for one class (numbers for the teacher dashboard chips).
router.get('/events/:id/coverage', async (req, res) => {
  const classId = Number(req.query.class_id);
  if (!classId) return res.status(400).json({ error: 'class_id required' });
  try {
    const acc = await teacherEventClassAccess(req.params.id, classId, req.user.id);
    if (acc.error) return res.status(acc.status).json({ error: acc.error });
    const [[st]] = await pool.query('SELECT COUNT(*) AS c FROM students WHERE class_id=?', [classId]);
    const covScope = inClause('x.subject_id', acc.scoped ? acc.subjectIds : []);
    const covSql = acc.scoped ? ' AND ' + covScope.sql : '';
    const covParams = acc.scoped ? covScope.params : [];
    const [[wm]] = await pool.query(
      `SELECT COUNT(DISTINCT m.student_id) AS c FROM marks m JOIN exams x ON x.id=m.exam_id WHERE x.event_id=? AND x.class_id=?${covSql}`,
      [req.params.id, classId, ...covParams]);
    const [subj] = await pool.query(
      `SELECT x.id AS exam_id, sub.name AS subject_name, x.status, x.source,
        (SELECT COUNT(*) FROM marks m WHERE m.exam_id=x.id) AS entered_count
       FROM exams x JOIN subjects sub ON sub.id=x.subject_id
       WHERE x.event_id=? AND x.class_id=?${covSql} ORDER BY sub.name`,
      [req.params.id, classId, ...covParams]);
    res.json({
      event: acc.ev, class: acc.cls,
      student_count: Number(st.c), students_with_marks: Number(wm.c),
      subject_count: subj.length, subjects_with_marks: subj.filter(s => Number(s.entered_count) > 0).length,
      subjects: subj
    });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Syllabus subjects of a class inside an event, with live entry status.
// No pre-created exam row needed — the row materializes on first marks submit.
router.get('/events/:id/entry-subjects', async (req, res) => {
  const classId = Number(req.query.class_id);
  if (!classId) return res.status(400).json({ error: 'class_id required' });
  try {
    const [[ev]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [req.params.id]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    const [[cls]] = await pool.query('SELECT id, name, section, group_name, teacher_id FROM classes WHERE id=?', [classId]);
    if (!cls) return res.status(404).json({ error: 'Class not found' });
    const [[mine]] = await pool.query('SELECT id FROM classes WHERE id=? AND teacher_id=?', [classId, req.user.id]);
    const [[teaches]] = await pool.query('SELECT id FROM subjects WHERE class_id=? AND teacher_id=? LIMIT 1', [classId, req.user.id]);
    if (!mine && !teaches) return res.status(403).json({ error: 'এই class আপনার নয়' });
    const [subs] = await pool.query(
      `SELECT sub.id AS subject_id, sub.name AS subject_name, sub.full_marks, sub.teacher_id,
              sub.cq_full, sub.mcq_full, sub.practical_full, sub.written_full, sub.ca_full,
              u.name AS subject_teacher_name,
              (sub.teacher_id = ?) AS is_mine,
              (SELECT x.id FROM exams x WHERE x.event_id=? AND x.class_id=? AND x.subject_id=sub.id LIMIT 1) AS exam_id,
              (SELECT x.status FROM exams x WHERE x.event_id=? AND x.class_id=? AND x.subject_id=sub.id LIMIT 1) AS exam_status,
              (SELECT x.entry_open FROM exams x WHERE x.event_id=? AND x.class_id=? AND x.subject_id=sub.id LIMIT 1) AS exam_entry_open,
              (SELECT x.entry_deadline FROM exams x WHERE x.event_id=? AND x.class_id=? AND x.subject_id=sub.id LIMIT 1) AS exam_entry_deadline,
              (SELECT COUNT(*) FROM marks m JOIN exams x ON x.id=m.exam_id
                WHERE x.event_id=? AND x.class_id=? AND x.subject_id=sub.id) AS entered_count,
              (SELECT COUNT(*) FROM students s WHERE s.class_id=?) AS student_count
       FROM subjects sub LEFT JOIN users u ON u.id=sub.teacher_id
       WHERE sub.class_id=? ORDER BY sub.name`,
      [req.user.id, req.params.id, classId, req.params.id, classId, req.params.id, classId, req.params.id, classId, req.params.id, classId, classId, classId]);
    const rows = subs.map(s => ({
      ...s,
      is_mine: Number(s.is_mine) === 1,
      entered_count: Number(s.entered_count),
      student_count: Number(s.student_count),
      pending_count: Number(s.student_count) - Number(s.entered_count),
      submitted: Number(s.entered_count) > 0,
      exam_published: s.exam_status === 'published',
      entry_open: s.exam_entry_open == null || s.exam_entry_open === undefined ? 1 : Number(s.exam_entry_open),
      // NCTB component-wise structure (empty array = single-total entry).
      components: [
        ...(s.cq_full != null ? [{ key: 'cq', label: 'CQ', full: Number(s.cq_full) }] : []),
        ...(s.mcq_full != null ? [{ key: 'mcq', label: 'MCQ', full: Number(s.mcq_full) }] : []),
        ...(s.practical_full != null ? [{ key: 'practical', label: 'Practical', full: Number(s.practical_full) }] : []),
        ...(s.written_full != null ? [{ key: 'written', label: 'Written', full: Number(s.written_full) }] : []),
        ...(s.ca_full != null ? [{ key: 'ca', label: 'CA', full: Number(s.ca_full) }] : []),
      ],
    }));
    const assigned = rows.length;
    const submitted = rows.filter(r => r.submitted).length;
    res.json({ event: ev, class: cls, assigned_subjects: assigned, submitted_subjects: submitted,
      pending_subjects: assigned - submitted, subjects: rows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

const KIND_TO_EXAM_TYPE = { half_yearly: 'half_yearly', annual: 'annual', pretest: 'pretest', test: 'test' };

// Teacher-driven auto-population: submit marks for a syllabus subject; the
// subject-exam row is created on the fly for fixed core events (no manual
// "+ Subject Exam" needed). Custom/other events still use pre-created rows.
router.post('/events/:id/marks', async (req, res) => {
  const { class_id, subject_id, records } = req.body || {};
  if (!class_id || !subject_id) return res.status(400).json({ error: 'class_id and subject_id required' });
  if (!Array.isArray(records) || records.length === 0) {
    return res.status(400).json({ error: 'records array required' });
  }
  try {
    const [[ev]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [req.params.id]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    if (ev.is_published) {
      return res.status(403).json({ error: 'Result already published. Contact admin for changes.' });
    }
    const [[sub]] = await pool.query(
      'SELECT id, name, class_id, full_marks, teacher_id, cq_full, mcq_full, practical_full, written_full, ca_full FROM subjects WHERE id=?',
      [subject_id]);
    if (!sub || Number(sub.class_id) !== Number(class_id)) {
      return res.status(400).json({ error: 'subject does not belong to the class' });
    }
    const [[cls]] = await pool.query('SELECT id, teacher_id FROM classes WHERE id=?', [class_id]);
    if (!cls) return res.status(404).json({ error: 'Class not found' });
    const isSubjectTeacher = Number(sub.teacher_id) === Number(req.user.id);
    const isClassTeacher = Number(cls.teacher_id) === Number(req.user.id);
    if (!isSubjectTeacher && !isClassTeacher) {
      return res.status(403).json({ error: 'এই subject আপনার নয়' });
    }
    // find-or-create the subject-exam row
    let [[exam]] = await pool.query(
      'SELECT * FROM exams WHERE event_id=? AND class_id=? AND subject_id=? LIMIT 1',
      [req.params.id, class_id, subject_id]);
    if (!exam) {
      const examType = KIND_TO_EXAM_TYPE[ev.exam_kind] || 'class_test';
      const [ins] = await pool.query(
        `INSERT INTO exams (name, exam_type, class_id, subject_id, source, created_by, event_id, status)
         VALUES (?,?,?,?,?,?,?,?)`,
        [`${ev.name} - ${sub.name}`, examType, class_id, subject_id, 'admin', req.user.id, req.params.id, 'draft']);
      [[exam]] = await pool.query('SELECT * FROM exams WHERE id=?', [ins.insertId]);
    }
    // The raw exam row carries no `can_enter` flag — that is derived by
    // teacherCanAccessExam (the assigned subject teacher may write numbers;
    // the class teacher may only supervise). Passing the raw row made every
    // event-scoped save fail with "only the assigned subject teacher may
    // enter numbers", even for the actual subject teacher.
    const authorized = await teacherCanAccessExam(exam.id, req.user.id);
    if (!authorized) return res.status(403).json({ error: 'এই subject আপনার নয়' });
    res.json({ ...(await submitExamMarks(authorized, records, req.user.id)), exam_id: exam.id });
    // Fire-and-forget: when every syllabus subject of the class has marks, the
    // final GPA/grades are auto-computed & cached and admins are pinged.
    autoFinalizeClassResults(exam.event_id, class_id).catch(() => {});
  } catch (err) {
    console.error(err);
    if (err.status) return res.status(err.status).json({ error: err.message });
    res.status(500).json({ error: 'Server error' });
  }
});

// ---- Seat plan (admin-created exams): class teacher only ----
async function seatPlanData(eventId, classId, rooms, userId) {
  const [[ev]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [eventId]);
  if (!ev) return { error: 'Event not found', status: 404 };
  const [[cls]] = await pool.query(
    'SELECT id, name, section, group_name FROM classes WHERE id=? AND teacher_id=?', [classId, userId]);
  if (!cls) return { error: 'কেবল নির্ধারিত class teacher seat plan দেখতে পারেন', status: 403 };
  const [[adm]] = await pool.query(
    `SELECT id FROM exams WHERE event_id=? AND class_id=? AND source='admin' LIMIT 1`, [eventId, classId]);
  if (!adm) return { error: 'এই event-এ এই class-এর কোনো admin exam নেই', status: 404 };
  const [students] = await pool.query(
    'SELECT id, name, roll, student_code FROM students WHERE class_id=? ORDER BY roll', [classId]);
  const nRooms = Math.min(20, Math.max(1, Number(rooms) || 1));
  const perRoom = Math.max(1, Math.ceil(students.length / nRooms));
  const roomsArr = [];
  let idx = 0;
  for (let r = 0; r < nRooms && idx < students.length; r++) {
    const chunk = students.slice(idx, idx + perRoom);
    idx += perRoom;
    const seats = [];
    for (let i = 0; i < chunk.length; i += 2) seats.push([chunk[i], chunk[i + 1] || null]);
    roomsArr.push({ room: `Room ${r + 1}`, seats });
  }
  return { ev, cls, students, rooms: roomsArr };
}

router.get('/events/:id/seat-plan', async (req, res) => {
  const classId = Number(req.query.class_id);
  if (!classId) return res.status(400).json({ error: 'class_id required' });
  try {
    const d = await seatPlanData(req.params.id, classId, req.query.rooms || 2, req.user.id);
    if (d.error) return res.status(d.status).json({ error: d.error });
    res.json({ event: d.ev, class: d.cls, total: d.students.length, rooms: d.rooms,
      settings: await schoolSettings() });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/events/:id/seat-plan.pdf', async (req, res) => {
  const classId = Number(req.query.class_id);
  if (!classId) return res.status(400).json({ error: 'class_id required' });
  try {
    const d = await seatPlanData(req.params.id, classId, req.query.rooms || 2, req.user.id);
    if (d.error) return res.status(d.status).json({ error: d.error });
    const settings = await schoolSettings();
    const doc = new PDFDocument({ size: 'A4', margin: 40 });
    const bufPromise = bufferPdfDoc(doc);
    const F = pdfFont(doc);
    const CW = doc.page.width - 80;
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename=seatplan_event${d.ev.id}_class${classId}.pdf`);
    const school = settings.school_name || settings.school || 'School';
    const schoolAddr = settings.school_address || settings.address || '';
    const logoPath = settings.school_logo_path ? path.join(__dirname, '..', 'uploads', 'logos', path.basename(settings.school_logo_path)) : null;

    // Draw frame, watermark, rosette on first page
    drawFrame(doc, 40);
    drawWatermark(doc, logoPath, doc.page.width, doc.page.height);
    drawRosette(doc, doc.page.width / 2, doc.page.height / 2);

    doc.font(F.B).fontSize(15).fillColor('#0b3d91').text(String(school), 40, 44, { align: 'center', width: CW });
    doc.font(F.B).fontSize(12).fillColor('#111').text('Seat Plan — ' + d.ev.name, 40, 66, { align: 'center', width: CW });
    if (schoolAddr) {
      doc.font(F.N).fontSize(9).fillColor('#555').text(String(schoolAddr), 40, 84, { align: 'center', width: CW });
      doc.font(F.N).fontSize(10).fillColor('#333')
        .text(`${d.cls.name}${d.cls.group_name ? ' (' + d.cls.group_name + ')' : ' (' + d.cls.section + ')'}  •  মোট ${d.students.length} জন`, 40, 100, { align: 'center', width: CW });
    } else {
      doc.font(F.N).fontSize(10).fillColor('#333')
        .text(`${d.cls.name}${d.cls.group_name ? ' (' + d.cls.group_name + ')' : ' (' + d.cls.section + ')'}  •  মোট ${d.students.length} জন`, 40, 84, { align: 'center', width: CW });
    }
    let y = 120;
    for (const rm of d.rooms) {
      if (y > doc.page.height - 120) { 
        doc.addPage(); 
        y = 44;
        drawFrame(doc, 40);
        drawWatermark(doc, logoPath, doc.page.width, doc.page.height);
      }
      const count = rm.seats.reduce((s, p) => s + (p[1] ? 2 : 1), 0);
      doc.font(F.B).fontSize(11).fillColor('#0b5394').text(`${rm.room} (${count} students)`, 40, y);
      y += 18;
      const cols = [{ w: 50, t: 'Desk' }, { w: (CW - 50) / 2, t: 'Left Seat' }, { w: (CW - 50) / 2, t: 'Right Seat' }];
      doc.fillColor('#0b5394').rect(40, y, CW, 18).fill();
      doc.fillColor('#fff').font(F.B).fontSize(9);
      let cx = 40;
      cols.forEach(c => { doc.text(c.t, cx + 5, y + 5, { width: c.w - 10 }); cx += c.w; });
      y += 18;
      doc.fillColor('#111').font(F.N);
      rm.seats.forEach((p, i) => {
        if (y > doc.page.height - 50) { 
          doc.addPage(); 
          y = 44;
          drawFrame(doc, 40);
          drawWatermark(doc, logoPath, doc.page.width, doc.page.height);
        }
        if (i % 2 === 0) { doc.fillColor('#eef3f9').rect(40, y, CW, 17).fill(); }
        doc.fillColor('#111').fontSize(9);
        cx = 40;
        const cells = [String(i + 1), p[0] ? `${p[0].roll}. ${p[0].name}` : '', p[1] ? `${p[1].roll}. ${p[1].name}` : '—'];
        cells.forEach((t, ci) => { doc.text(t, cx + 5, y + 4, { width: cols[ci].w - 10 }); cx += cols[ci].w; });
        y += 17;
      });
      y += 14;
    }
    doc.end();
    const buf = await bufPromise;
    res.setHeader('Content-Length', buf.length);
    res.end(buf);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

function pdfFont(doc) {
  const fontPath = path.join(__dirname, '..', 'assets', 'fonts', 'Kalpurush.ttf');
  if (fs.existsSync(fontPath)) {
    doc.registerFont('Kalpurush', fontPath);
    return { B: 'Kalpurush', N: 'Kalpurush' };
  }
  return { B: 'Helvetica-Bold', N: 'Helvetica' };
}

// Draw decorative frame border
function drawFrame(doc, margin) {
  const pw = doc.page.width;
  const ph = doc.page.height;
  const m = margin;
  doc.save()
    .lineWidth(2)
    .strokeColor('#0b3d91')
    .rect(m, m, pw - 2*m, ph - 2*m)
    .stroke()
    .lineWidth(0.5)
    .strokeColor('#cbd5e1')
    .rect(m + 4, m + 4, pw - 2*m - 8, ph - 2*m - 8)
    .stroke()
    .restore();
}

// Draw watermark logo
function drawWatermark(doc, logoPath, pageWidth, pageHeight) {
  if (!logoPath || !fs.existsSync(logoPath)) return;
  try {
    const img = doc.openImage(logoPath);
    const maxDim = Math.min(pageWidth, pageHeight) * 0.6;
    const scale = Math.min(maxDim / img.width, maxDim / img.height);
    const w = img.width * scale;
    const h = img.height * scale;
    const x = (pageWidth - w) / 2;
    const y = (pageHeight - h) / 2;
    doc.save()
      .opacity(0.04)
      .image(logoPath, x, y, { width: w, height: h })
      .restore();
  } catch (_) {}
}

// Draw rosette decoration
function drawRosette(doc, cx, cy) {
  doc.save()
    .strokeColor('#444')
    .lineWidth(0.6)
    .opacity(0.5);
  for (let r = 30; r <= 180; r += 30) {
    doc.circle(cx, cy, r).stroke();
  }
  doc.moveTo(cx, 20).lineTo(cx, 380).stroke();
  doc.moveTo(20, cy).lineTo(380, cy).stroke();
  doc.moveTo(73, 73).lineTo(327, 327).stroke();
  doc.moveTo(327, 73).lineTo(73, 327).stroke();
  doc.restore();
}

async function schoolSettings() {
  const [rows] = await pool.query('SELECT setting_key, setting_value FROM app_settings').catch(() => [[], null]);
  const s = {};
  (rows || []).forEach(r => { s[r.setting_key] = r.setting_value; });
  return s;
}

// Buffer a pdfkit doc in memory so we can send Content-Length.
// (Lets the mobile app show real download % instead of an endless spinner.)
function bufferPdfDoc(doc) {
  const chunks = [];
  doc.on('data', c => chunks.push(c));
  return new Promise((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
  });
}

// ---- Admit cards (admin-created exams): class teacher only ----
async function admitData(eventId, classId, userId) {
  const [[ev]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [eventId]);
  if (!ev) return { error: 'Event not found', status: 404 };
  const [[cls]] = await pool.query(
    'SELECT id, name, section, group_name FROM classes WHERE id=? AND teacher_id=?', [classId, userId]);
  if (!cls) return { error: 'কেবল নির্ধারিত class teacher admit card দেখতে পারেন', status: 403 };
  const [[adm]] = await pool.query(
    `SELECT id FROM exams WHERE event_id=? AND class_id=? AND source='admin' LIMIT 1`, [eventId, classId]);
  if (!adm) return { error: 'এই event-এ এই class-এর কোনো admin exam নেই', status: 404 };
  const [students] = await pool.query(
    'SELECT id, name, roll, student_code, dob FROM students WHERE class_id=? ORDER BY roll', [classId]);
  const [subjects] = await pool.query(
    `SELECT sub.name AS subject_name, x.exam_date FROM exams x JOIN subjects sub ON sub.id=x.subject_id
     WHERE x.event_id=? AND x.class_id=? ORDER BY (x.exam_date IS NULL), x.exam_date, sub.name`,
    [eventId, classId]);
  return { ev, cls, students, subjects };
}

router.get('/events/:id/admit-cards', async (req, res) => {
  const classId = Number(req.query.class_id);
  if (!classId) return res.status(400).json({ error: 'class_id required' });
  try {
    const d = await admitData(req.params.id, classId, req.user.id);
    if (d.error) return res.status(d.status).json({ error: d.error });
    res.json({ event: d.ev, class: d.cls, subjects: d.subjects, students: d.students,
      settings: await schoolSettings() });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/events/:id/admit-cards.pdf', async (req, res) => {
  const classId = Number(req.query.class_id);
  if (!classId) return res.status(400).json({ error: 'class_id required' });
  try {
    const d = await admitData(req.params.id, classId, req.user.id);
    if (d.error) return res.status(d.status).json({ error: d.error });
    const settings = await schoolSettings();
    const school = settings.school_name || settings.school || 'School';
    const schoolAddr = settings.school_address || settings.address || '';
    const logoPath = settings.school_logo_path ? path.join(__dirname, '..', 'uploads', 'logos', path.basename(settings.school_logo_path)) : null;
    const doc = new PDFDocument({ size: 'A4', margin: 36 });
    const bufPromise = bufferPdfDoc(doc);
    const F = pdfFont(doc);
    const CW = doc.page.width - 72;
    const cardH = 330;
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename=admitcards_event${d.ev.id}_class${classId}.pdf`);
    const clsLabel = `${d.cls.name}${d.cls.group_name ? ' (' + d.cls.group_name + ')' : ' (' + d.cls.section + ')'}`;
    
    // Draw frame, watermark, rosette on first page
    drawFrame(doc, 36);
    drawWatermark(doc, logoPath, doc.page.width, doc.page.height);
    drawRosette(doc, doc.page.width / 2, doc.page.height / 2);
    
    d.students.forEach((s, si) => {
      const slot = si % 2;
      const top = slot === 0 ? 40 : 40 + cardH + 24;
      if (si > 0 && slot === 0) {
        doc.addPage();
        drawFrame(doc, 36);
        drawWatermark(doc, logoPath, doc.page.width, doc.page.height);
      }
      let y = top;
      doc.roundedRect(36, y, CW, cardH, 8).stroke('#0b5394');
      y += 10;
      doc.font(F.B).fontSize(12).fillColor('#0b3d91').text(String(school), 46, y, { align: 'center', width: CW - 20 });
      y += 17;
      if (schoolAddr) {
        doc.font(F.N).fontSize(8).fillColor('#555').text(String(schoolAddr), 46, y, { align: 'center', width: CW - 20 });
        y += 12;
      }
      doc.font(F.B).fontSize(10).fillColor('#111').text('ADMIT CARD — ' + d.ev.name, 46, y, { align: 'center', width: CW - 20 });
      y += 16;
      const info = [
        ['Name', s.name], ['Student ID', String(s.student_code)],
        ['Class', clsLabel], ['Roll', String(s.roll)],
        ['DOB', s.dob ? String(s.dob).slice(0, 10) : '-'],
      ];
      doc.font(F.N).fontSize(9).fillColor('#111');
      info.forEach(([k, v]) => {
        doc.text(k + ':', 52, y, { width: 90 });
        doc.font(F.B).text(String(v), 145, y, { width: CW - 115 });
        doc.font(F.N);
        y += 13;
      });
      y += 4;
      if (d.subjects.length) {
        doc.font(F.B).fontSize(8.5).fillColor('#0b5394').text('Subjects:', 52, y);
        y += 12;
        doc.font(F.N).fontSize(8).fillColor('#333');
        d.subjects.slice(0, 8).forEach(sb => {
          const dt = sb.exam_date ? ymd(sb.exam_date) : '';
          doc.text(`• ${sb.subject_name}${dt ? '  (' + dt + ')' : ''}`, 60, y, { width: CW - 40 });
          y += 11;
        });
      }
      const sigY = top + cardH - 30;
      doc.font(F.N).fontSize(8.5).fillColor('#111');
      doc.text("Guardian's Signature", 60, sigY, { width: 160, align: 'center' });
      doc.text('Headmaster', doc.page.width - 220, sigY, { width: 160, align: 'center' });
    });
    doc.end();
    const buf = await bufPromise;
    res.setHeader('Content-Length', buf.length);
    res.end(buf);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;