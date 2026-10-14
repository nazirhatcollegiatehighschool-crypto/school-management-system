const router = require('express').Router();
const pool = require('../db');
const { auth } = require('../middleware/auth');
const { computeResult } = require('../grading');
const { queuePush, getGuardianTokens } = require('../fcm');
const PDFDocument = require('pdfkit');

// Result computation, tabulation and marksheets are school-wide admin operations.
// Teachers enter marks through /api/teacher — they must NOT compute/tabulate
// arbitrary classes or read arbitrary student marksheets.
router.use(auth('admin'));

// =====================================================================
// EXAM EVENT LIFECYCLE — canonical kinds, session auto-create, publish flow.
// kinds: half_yearly (no promotion), annual (promotion), pretest (no
// promotion), test (promotion), other (free-form: First Terminal etc).
// Rule: ONE live event per (kind, year) for canonical kinds — enforced by a
// partial unique index + app-level 409. Deleting an event cascade-removes its
// exams/marks/results/promotions and frees the (kind, year) slot, so the exam
// "session" for that year comes back and can be created again.
// =====================================================================
const CANON = {
  half_yearly: { label: 'Half Yearly Examination', promotion_linked: 0 },
  annual: { label: 'Annual Examination', promotion_linked: 1 },
  pretest: { label: 'Pre-Test Examination', promotion_linked: 0 },
  test: { label: 'Test Examination', promotion_linked: 1 },
};
const CANON_KINDS = Object.keys(CANON);
const isCanon = k => CANON_KINDS.indexOf(k) !== -1;

function sessionYear(name) {
  const m = String(name || '').match(/(19|20)\d{2}/);
  if (m) return Number(m[0]);
  return new Date().getFullYear();
}

// Create the 4 canonical event shells for a session when missing. Legacy
// same-name events are adopted (kind/year stamped) instead of duplicated.
async function ensureSessionExams(sessionId) {
  const [[sess]] = await pool.query('SELECT id, name FROM sessions WHERE id=?', [sessionId]);
  if (!sess) throw Object.assign(new Error('Session not found'), { status: 404 });
  const year = sessionYear(sess.name);
  const created = [], adopted = [], skipped = [];
  for (const kind of CANON_KINDS) {
    const name = `${CANON[kind].label} ${year}`;
    const [same] = await pool.query(
      'SELECT id, exam_kind FROM exam_events WHERE session_id=? AND exam_kind=? AND year=?', [sessionId, kind, year]);
    if (same.length) { skipped.push({ kind, id: same[0].id, name }); continue; }
    const [byName] = await pool.query(
      'SELECT id FROM exam_events WHERE session_id=? AND name=?', [sessionId, name]);
    if (byName.length) {
      await pool.query('UPDATE exam_events SET exam_kind=?, year=?, promotion_linked=? WHERE id=?',
        [kind, year, CANON[kind].promotion_linked, byName[0].id]);
      adopted.push({ kind, id: byName[0].id, name });
      continue;
    }
    try {
      const [r] = await pool.query(
        'INSERT INTO exam_events (name, session_id, exam_kind, year, promotion_linked) VALUES (?,?,?,?,?)',
        [name, sessionId, kind, year, CANON[kind].promotion_linked]);
      created.push({ kind, id: r.insertId, name });
    } catch (e) {
      if (e.code === '23505') skipped.push({ kind, name, note: 'already exists for year' });
      else throw e;
    }
  }
  return { session: sess, year, created, adopted, skipped };
}

async function findOrCreateSessionByYear(year) {
  const [rows] = await pool.query('SELECT id, name FROM sessions WHERE name=?', [String(year)]);
  if (rows.length) return rows[0];
  const [r] = await pool.query('INSERT INTO sessions (name, is_active) VALUES (?,0)', [String(year)]);
  return { id: r.insertId, name: String(year) };
}

router.get('/events', async (req, res) => {
  try {
    let pub = '';
    const params = [];
    if (req.query.published === '1' || req.query.published === '0') {
      pub = 'WHERE e.is_published=?';
      params.push(Number(req.query.published));
    }
    const [rows] = await pool.query(
      `SELECT e.*, s.name AS session_name,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id = e.id) AS exam_count,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id = e.id AND x.status='published') AS published_count,
        (SELECT COUNT(DISTINCT m.student_id) FROM marks m JOIN exams x ON x.id=m.exam_id WHERE x.event_id=e.id) AS students_with_marks,
        (SELECT COUNT(*) FROM results r WHERE r.exam_id = e.id) AS results_cached,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id = e.id AND x.entry_open=1 AND x.status<>'published') AS entry_open_count,
        (SELECT MAX(x.entry_deadline) FROM exams x WHERE x.event_id = e.id) AS entry_deadline
       FROM exam_events e LEFT JOIN sessions s ON e.session_id = s.id
       ${pub}
       ORDER BY e.is_published ASC, (e.year IS NULL), e.year DESC, e.id DESC`,
      params
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/events', async (req, res) => {
  const { name, session_id, start_date, exam_date, result_date, exam_kind, year, promotion_linked } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name required' });
  const kind = exam_kind || 'other';
  const yr = year != null && year !== '' ? Number(year) : null;
  if (isCanon(kind) && !yr) return res.status(400).json({ error: 'year required for ' + kind });
  try {
    if (isCanon(kind)) {
      const [dup] = await pool.query(
        'SELECT id, name FROM exam_events WHERE exam_kind=? AND year=?', [kind, yr]);
      if (dup.length) {
        return res.status(409).json({
          error: `এই বছরের (${yr}) ${CANON[kind].label} ইতিমধ্যে আছে ("${dup[0].name}")। Delete না করা পর্যন্ত নতুন করে create করা যাবে না।`,
          existing: dup[0]
        });
      }
    }
    const [result] = await pool.query(
      'INSERT INTO exam_events (name, session_id, start_date, exam_date, result_date, created_by, exam_kind, year, promotion_linked) VALUES (?,?,?,?,?,?,?,?,?)',
      [name, session_id || 1, start_date || null, exam_date || null, result_date || null, req.user.id, kind,
       yr, promotion_linked != null ? Number(promotion_linked) : (isCanon(kind) ? CANON[kind].promotion_linked : 0)]
    );
    res.status(201).json({ id: result.insertId });
  } catch (err) {
    console.error(err);
    if (err.code === '23505') return res.status(409).json({ error: 'এই kind+year-এর exam ইতিমধ্যে আছে। আগে delete করুন।' });
    res.status(500).json({ error: 'Server error' });
  }
});

// Cascade delete: removes the event's exams + marks + cached results +
// promotions + per-student result notifications, then the event itself.
// This frees the (kind, year) slot so the exam can be created again.
router.delete('/events/:id', async (req, res) => {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [exams] = await conn.query('SELECT id FROM exams WHERE event_id=?', [req.params.id]);
    const examIds = exams.map(e => e.id);
    let marks = 0, shares = 0, results = 0, promotions = 0;
    if (examIds.length) {
      const [m] = await conn.query('DELETE FROM marks WHERE exam_id IN (?)', [examIds]);
      marks = m.affectedRows || 0;
      const [sh] = await conn.query('DELETE FROM exam_shares WHERE exam_id IN (?)', [examIds]);
      shares = sh.affectedRows || 0;
      await conn.query(
        `DELETE FROM notifications WHERE related_id IN (?) AND type IN ('result','class_test_result')`, [examIds]);
      await conn.query('DELETE FROM exams WHERE event_id=?', [req.params.id]);
    }
    const [rs] = await conn.query('DELETE FROM results WHERE exam_id=?', [req.params.id]);
    results = rs.affectedRows || 0;
    const [pr] = await conn.query('DELETE FROM promotions WHERE event_id=?', [req.params.id]);
    promotions = pr.affectedRows || 0;
    await conn.query(`DELETE FROM notifications WHERE related_id=? AND type IN ('result','promotion')`, [req.params.id]);
    const [ev] = await conn.query('DELETE FROM exam_events WHERE id=?', [req.params.id]);
    if (!ev.affectedRows) { await conn.rollback(); return res.status(404).json({ error: 'Event not found' }); }
    await conn.commit();
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'event_delete', `Deleted event ${req.params.id} (+${examIds.length} exams, ${marks} marks)`]).catch(() => {});
    res.json({ ok: true, deleted_event: Number(req.params.id), exams: examIds.length, marks, results, promotions });
  } catch (err) { try { await conn.rollback(); } catch (e) {} console.error(err); res.status(500).json({ error: 'Server error' }); }
  finally { conn.release(); }
});

router.put('/events/:id', async (req, res) => {
  const { name, session_id, start_date, exam_date, result_date, exam_kind, year, promotion_linked } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name required' });
  try {
    const [[ev]] = await pool.query('SELECT id FROM exam_events WHERE id=?', [req.params.id]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    const kind = exam_kind !== undefined ? (exam_kind || 'other') : undefined;
    const yr = year !== undefined ? (year === '' || year == null ? null : Number(year)) : undefined;
    if (kind !== undefined && isCanon(kind) && (yr === undefined || yr == null)) {
      const [[cur]] = await pool.query('SELECT year FROM exam_events WHERE id=?', [req.params.id]);
      if (!cur.year) return res.status(400).json({ error: 'year required for ' + kind });
    }
    const effKind = kind !== undefined ? kind : null;
    const effYear = yr !== undefined ? yr : null;
    if (effKind && isCanon(effKind) && effYear) {
      const [dup] = await pool.query(
        'SELECT id FROM exam_events WHERE exam_kind=? AND year=? AND id<>?', [effKind, effYear, req.params.id]);
      if (dup.length) return res.status(409).json({ error: 'এই kind+year-এর exam ইতিমধ্যে আছে। আগে delete করুন।' });
    }
    const updates = ['name=?'];
    const params = [name];
    if (session_id !== undefined) { updates.push('session_id=?'); params.push(session_id || 1); }
    if (start_date !== undefined) { updates.push('start_date=?'); params.push(start_date || null); }
    if (exam_date !== undefined) { updates.push('exam_date=?'); params.push(exam_date || null); }
    if (result_date !== undefined) { updates.push('result_date=?'); params.push(result_date || null); }
    if (kind !== undefined) { updates.push('exam_kind=?'); params.push(kind); }
    if (yr !== undefined) { updates.push('year=?'); params.push(yr); }
    if (promotion_linked !== undefined) { updates.push('promotion_linked=?'); params.push(Number(promotion_linked)); }
    params.push(req.params.id);
    await pool.query(`UPDATE exam_events SET ${updates.join(', ')} WHERE id=?`, params);
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    if (err.code === '23505') return res.status(409).json({ error: 'এই kind+year-এর exam ইতিমধ্যে আছে।' });
    res.status(500).json({ error: 'Server error' });
  }
});

// Publish an event: marks it published (Published Exams list), publishes all
// its subject exams (guardian gating), optionally notifies guardians (ADMIN
// decides), and auto-creates the next year's same-kind shell.
// Running-vs-Published rule (scientific single-gate):
// - teacher mark entry is open ONLY while the EVENT is unpublished AND at
//   least one of its subject exams has entry_open=1 AND (no deadline OR now
//   <= entry_deadline). The moment the event publishes, entry closes for ALL
//   its exams at once — teachers can no longer write, guardians can read.
// - publish REQUIRES coverage: every class in the event must have every
//   syllabus subject with marks (subjects_with_marks >= assigned) and every
//   enrolled student with at least one mark row. Otherwise 422 + missing list.
async function eventPublishGate(eventId) {
  const missing = [];
  const [classes] = await pool.query(
    `SELECT c.id, c.name, c.section,
      (SELECT COUNT(*) FROM students s WHERE s.class_id=c.id) AS students,
      (SELECT COUNT(DISTINCT m.student_id) FROM marks m JOIN exams x ON x.id=m.exam_id
        WHERE x.event_id=? AND x.class_id=c.id) AS students_done,
      (SELECT COUNT(*) FROM subjects sub WHERE sub.class_id=c.id) AS subjects,
      (SELECT COUNT(DISTINCT x.subject_id) FROM exams x JOIN marks m ON m.exam_id=x.id
        WHERE x.event_id=? AND x.class_id=c.id) AS subjects_done
     FROM classes c WHERE c.id IN (SELECT DISTINCT class_id FROM exams WHERE event_id=?)`,
    [eventId, eventId, eventId]);
  for (const c of classes) {
    const gaps = [];
    if (Number(c.subjects_done || 0) < Number(c.subjects || 0)) {
      gaps.push(`${Number(c.subjects) - Number(c.subjects_done)} subject-এর marks বাকি`);
    }
    if (Number(c.students_done || 0) < Number(c.students || 0)) {
      gaps.push(`${Number(c.students) - Number(c.students_done)} জন student-এর marks বাকি`);
    }
    if (gaps.length) missing.push({ class_id: c.id, class_name: `${c.name} (${c.section})`, gaps });
  }
  return missing;
}

router.post('/events/:id/publish', async (req, res) => {
  const notify = req.body ? !!req.body.notify_guardians : false;
  try {
    const [[ev]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [req.params.id]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    if (Number(ev.is_published) === 1) {
      return res.status(409).json({ error: 'Event already published — unpublish করে আবার publish করা যাবে।' });
    }
    const missing = await eventPublishGate(req.params.id);
    if (missing.length) {
      return res.status(422).json({
        error: 'সব subject/student-এর marks entry শেষ না হওয়া পর্যন্ত publish করা যাবে না।',
        missing,
      });
    }
    await pool.query(
      `UPDATE exam_events SET is_published=1, published_at=NOW(), notify_guardians=?, notified_at=CASE WHEN ?=1 THEN NOW() ELSE notified_at END WHERE id=?`,
      [notify ? 1 : 0, notify ? 1 : 0, req.params.id]);
    await pool.query(`UPDATE exams SET status='published', entry_open=0 WHERE event_id=?`, [req.params.id]);
    // Auto result generation: compute totals/GPA/grades for every class in
    // the event the moment it is published.
    let autoComputed = [];
    try {
      const [clsRows] = await pool.query('SELECT DISTINCT class_id FROM exams WHERE event_id=?', [req.params.id]);
      for (const c of clsRows) {
        const r = await computeEventResults(req.params.id, c.class_id);
        autoComputed.push({ class_id: c.class_id, ...r });
      }
    } catch (e) { console.error('auto-compute on publish failed:', e.message); }
    let notified = 0, push = null, already_notified = false;
    if (notify) {
      // Idempotent publish-notify: same event notifies guardians EXACTLY ONCE.
      // A second tap with notify=1 returns already_notified=true + the first
      // notified_at — no duplicate push, no duplicate inbox rows (dedup_key).
      const [[sent]] = await pool.query(
        `SELECT notified_at FROM exam_events WHERE id=? AND notify_guardians=1 AND notified_at IS NOT NULL`,
        [req.params.id]);
      if (sent && sent.notified_at) {
        already_notified = true;
      } else {
        const [rows] = await pool.query(
          `SELECT DISTINCT m.student_id FROM marks m JOIN exams x ON x.id=m.exam_id WHERE x.event_id=?`,
          [req.params.id]);
        const studentIds = rows.map(r => r.student_id);
        if (studentIds.length) {
          const tokens = await getGuardianTokens(studentIds);
          push = await queuePush(tokens, 'পরীক্ষার ফলাফল প্রকাশিত',
            `${ev.name}-এর ফলাফল প্রকাশিত হয়েছে। অ্যাপে দেখুন।`,
            { type: 'result', event_id: String(ev.id), event_name: ev.name });
          const vals = studentIds.map(() => '(?,?,?,?,?,?,?,?)').join(',');
          const params = [];
          for (const sid of studentIds) {
            params.push(sid, 'Exam Result Published', `${ev.name}-এর ফলাফল প্রকাশিত হয়েছে`, 'result', 'students', ev.id, req.user.id, `result:${ev.id}:${sid}`);
          }
          // dedup_key makes re-publish inserts no-ops (same event+student can
          // never create a second inbox row, even under double-click races).
          await pool.query(
            `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, created_by, dedup_key)
             VALUES ${vals} ON CONFLICT (dedup_key) DO NOTHING`, params);
          const [[cnt]] = await pool.query(
            `SELECT COUNT(*) AS c FROM notifications WHERE dedup_key LIKE ?`, [`result:${ev.id}:%`]);
          notified = cnt ? Number(cnt.c) : studentIds.length;
        }
      }
    }
    // Next-year shell: same kind for year+1 (creates the Y+1 session if missing).
    let nextYear = null;
    if (isCanon(ev.exam_kind) && ev.year) {
      const sess = await findOrCreateSessionByYear(Number(ev.year) + 1);
      await ensureSessionExams(sess.id);
      nextYear = sess.name;
    }
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'event_publish', `Published event ${ev.name} (notify=${notify ? 1 : 0}, notified=${notified}, already=${already_notified ? 1 : 0})`]).catch(() => {});
    res.json({ ok: true, notified, already_notified, push, next_year_session: nextYear, auto_computed: autoComputed });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/events/:id/unpublish', async (req, res) => {
  try {
    const [[ev]] = await pool.query('SELECT id FROM exam_events WHERE id=?', [req.params.id]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    await pool.query(`UPDATE exam_events SET is_published=0 WHERE id=?`, [req.params.id]);
    await pool.query(`UPDATE exams SET status='draft' WHERE event_id=?`, [req.params.id]);
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'event_unpublish', `Unpublished event ${req.params.id}`]).catch(() => {});
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Per-class coverage for an event: how many students / subjects have marks.
// `ready` = every syllabus subject has at least partial mark rows AND every
// student of the class has at least one mark row — the admin's green light to
// review & publish (auto-publish only happens inside the publish flow).
router.get('/events/:id/coverage', async (req, res) => {
  try {
    const [classes] = await pool.query(
      `SELECT c.id AS class_id, c.name AS class_name, c.section, c.group_name,
        (SELECT COUNT(*) FROM students s WHERE s.class_id=c.id) AS student_count,
        (SELECT COUNT(DISTINCT m.student_id) FROM marks m JOIN exams x ON x.id=m.exam_id WHERE x.event_id=? AND x.class_id=c.id) AS students_with_marks,
        (SELECT COUNT(*) FROM marks m JOIN exams x ON x.id=m.exam_id WHERE x.event_id=? AND x.class_id=c.id) AS marks_count,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id=? AND x.class_id=c.id) AS subject_count,
        (SELECT COUNT(DISTINCT x.subject_id) FROM exams x JOIN marks m ON m.exam_id=x.id WHERE x.event_id=? AND x.class_id=c.id) AS subjects_with_marks,
        (SELECT COUNT(*) FROM subjects sub WHERE sub.class_id=c.id) AS assigned_subjects,
        (SELECT COUNT(*) FROM subjects sub WHERE sub.class_id=c.id
           AND NOT EXISTS (SELECT 1 FROM exams x JOIN marks m ON m.exam_id=x.id
                           WHERE x.event_id=? AND x.class_id=c.id AND x.subject_id=sub.id)) AS pending_subjects
       FROM classes c
       ORDER BY c.name, c.section, c.group_name`,
      [req.params.id, req.params.id, req.params.id, req.params.id, req.params.id]
    );
    const [subjects] = await pool.query(
      `SELECT x.class_id, x.id AS exam_id, sub.name AS subject_name, x.status,
        (SELECT COUNT(*) FROM marks m WHERE m.exam_id=x.id) AS entered_count,
        (SELECT COUNT(*) FROM students s WHERE s.class_id=x.class_id) AS student_count
       FROM exams x JOIN subjects sub ON sub.id=x.subject_id
       WHERE x.event_id=? ORDER BY x.class_id, sub.name`,
      [req.params.id]
    );
    classes.forEach(c => {
      const subjTotal = Math.max(Number(c.assigned_subjects || 0), Number(c.subject_count || 0));
      const subjDone = Number(c.subjects_with_marks || 0);
      const stuTotal = Number(c.student_count || 0);
      const stuDone = Number(c.students_with_marks || 0);
      c.subject_progress = subjTotal ? `${subjDone}/${subjTotal} Subject Marks Submitted` : '0/0';
      c.student_progress = stuTotal ? `${stuDone}/${stuTotal} Students Have Marks` : '0/0';
      c.subject_pct = subjTotal ? Math.round(subjDone / subjTotal * 100) : 0;
      c.ready = subjTotal > 0 && subjDone >= subjTotal && stuTotal > 0 && stuDone >= stuTotal;
    });
    const eventReady = classes.some(c => c.ready) && classes
      .filter(c => Number(c.student_count || 0) > 0).every(c => c.ready);
    res.json({ classes, subjects, event_ready: eventReady });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Ensure the 4 canonical shells for a session (called on session create,
// publish rollover, and by an explicit admin button).
router.post('/events/ensure-session', async (req, res) => {
  const { session_id } = req.body || {};
  if (!session_id) return res.status(400).json({ error: 'session_id required' });
  try {
    const out = await ensureSessionExams(Number(session_id));
    res.json({ ok: true, ...out });
  } catch (err) {
    console.error(err);
    if (err.status) return res.status(err.status).json({ error: err.message });
    res.status(500).json({ error: 'Server error' });
  }
});

router.post('/results/compute', async (req, res) => {
  const { event_id, class_id } = req.body || {};
  if (!event_id || !class_id) return res.status(400).json({ error: 'event_id and class_id required' });
  try {
    res.json(await computeEventResults(event_id, class_id));
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Shared result engine: totals, GPA (with 4th-subject bonus), percentages and
// grades per student, cached into `results`. Used by manual compute,
// publish flow (auto for every class in the event) and permission changes.
async function computeEventResults(event_id, class_id) {
  const [students] = await pool.query('SELECT id FROM students WHERE class_id=?', [class_id]);
  let computed = 0, withMarks = 0;
  for (const s of students) {
    const r = await computeResult(s.id, event_id);
    if (!r) continue;
    withMarks++;
    await pool.query(
      `INSERT INTO results (student_id, exam_id, total_gpa_without_4th, gpa_4th_bonus, final_gpa, result_status)
       VALUES (?,?,?,?,?,?)
       ON CONFLICT (student_id, exam_id) DO UPDATE SET total_gpa_without_4th=EXCLUDED.total_gpa_without_4th,
         gpa_4th_bonus=EXCLUDED.gpa_4th_bonus, final_gpa=EXCLUDED.final_gpa,
         result_status=EXCLUDED.result_status, computed_at=NOW()`,
      [s.id, event_id, r.total_gpa_without_4th, r.gpa_4th_bonus, r.final_gpa, r.result_status]
    );
    computed++;
  }
  return { ok: true, students: students.length, computed, with_marks: withMarks };
}

router.get('/tabulation', async (req, res) => {
  const { event_id, class_id } = req.query;
  if (!event_id || !class_id) return res.status(400).json({ error: 'event_id and class_id required' });
  try {
    const [students] = await pool.query(
      `SELECT s.id, s.name, s.roll, s.student_code, r.final_gpa, r.total_gpa_without_4th,
              r.gpa_4th_bonus, r.result_status
       FROM students s
       LEFT JOIN results r ON r.student_id = s.id AND r.exam_id = ?
       WHERE s.class_id = ? ORDER BY s.roll`,
      [event_id, class_id]
    );
    const famSet = new Set();
    const rows = [];
    for (const stu of students) {
      const r = await computeResult(stu.id, event_id);
      const famMap = {};
      if (r) {
        r.families.forEach(f => { famSet.add(f.subject); famMap[f.subject] = f; });
      }
      rows.push({
        ...stu,
        families: famMap,
        total_marks: r ? r.total_marks : null,
        total_full: r ? r.total_full : null,
        fourth_score: r ? r.fourth_score : null,
        final_gpa: r ? r.final_gpa : stu.final_gpa,
        result_status: r ? r.result_status : stu.result_status
      });
    }
    const subjects = Array.from(famSet);
    rows.forEach((row, i) => { row._families = subjects.map(s => row.families[s] || null); });
    // Merit ranking with NCTB tie-breakers: GPA desc -> 4th-subject bonus desc
    // -> total marks desc -> 4th-subject scaled score desc -> roll asc.
    rows.forEach(row => { row.position = null; });
    const sortedForRank = [...rows].filter(r => r.final_gpa != null && r.result_status === 'PASSED')
      .sort((a, b) =>
        (Number(b.final_gpa) - Number(a.final_gpa)) ||
        (Number(b.gpa_4th_bonus || 0) - Number(a.gpa_4th_bonus || 0)) ||
        (Number(b.total_marks || 0) - Number(a.total_marks || 0)) ||
        (Number(b.fourth_score || 0) - Number(a.fourth_score || 0)) ||
        (Number(a.roll) - Number(b.roll)));
    sortedForRank.forEach((r, i) => { r.position = i + 1; });
    res.json({ subjects, rows });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Whole-class result cards as ONE pdf: one A4 page per student (same
// result-card engine the guardian sees), streamed as a single download.
// Scientific rule: the class PDF is just N individual cards concatenated —
// no separate renderer, so admin PDF and guardian PDF can never disagree.
// Requires the event to be published (same gate as the single card).
router.get('/class-pdf', async (req, res) => {
  const eventId = Number(req.query.event_id);
  const classId = Number(req.query.class_id);
  if (!eventId || !classId) return res.status(400).json({ error: 'event_id and class_id required' });
  try {
    const [[pub]] = await pool.query(
      `SELECT COUNT(*) AS cnt FROM exams WHERE event_id=? AND class_id=? AND status='published'`,
      [eventId, classId]);
    if (!pub || pub.cnt === 0) {
      return res.status(403).json({ error: 'Result not yet published for this class' });
    }
    const [[event]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [eventId]);
    const [[cls]] = await pool.query('SELECT * FROM classes WHERE id=?', [classId]);
    const [students] = await pool.query(
      'SELECT id, name, roll, student_code FROM students WHERE class_id=? ORDER BY roll', [classId]);
    if (!students.length) return res.status(404).json({ error: 'No students in this class' });
    const [settingsRows] = await pool.query('SELECT setting_key, setting_value FROM app_settings');
    const settings = {};
    settingsRows.forEach(s => { settings[s.setting_key] = s.setting_value; });

    const doc = new PDFDocument({ size: 'A4', margin: 40, autoFirstPage: false, bufferPages: true });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition',
      `attachment; filename=result_cards_${(cls.name || 'class').replace(/\s+/g, '')}_${(cls.group_name || cls.section || '').replace(/\s+/g, '')}_event${eventId}.pdf`);
    doc.pipe(res);
    const CW = doc.page.width - 80;

    for (const st of students) {
      const result = await computeResult(st.id, eventId);
      doc.addPage();
      let y = 50;
      const schoolName = settings.school_name || settings.school || settings.school_name_en || 'School';
      const schoolAddr = settings.school_address || settings.address || '';
      doc.font('Helvetica-Bold').fontSize(15).fillColor('#0b3d91').text(String(schoolName), 40, y, { align: 'center', width: CW });
      y += 20;
      if (schoolAddr) {
        doc.font('Helvetica').fontSize(9).fillColor('#555555').text(String(schoolAddr), 40, y, { align: 'center', width: CW });
        y += 14;
      }
      doc.fillColor('#111111').font('Helvetica-Bold').fontSize(12).text('ফলাফল কার্ড / Result Card', 40, y, { align: 'center', width: CW });
      y += 12;
      doc.font('Helvetica').fontSize(9.5).fillColor('#333')
        .text(`${event ? event.name : ''}  •  ${cls.name}${cls.group_name ? ' (' + cls.group_name + ')' : ''}`, 40, y, { align: 'center', width: CW });
      y += 22;
      doc.font('Helvetica').fontSize(9.5).fillColor('#111111');
      [['নাম / Name', st.name], ['রোল / Roll', String(st.roll)],
       ['আইডি / ID', String(st.student_code || '')],
      ].forEach(([k, v]) => {
        doc.font('Helvetica').fontSize(9.5).text(k + ':', 40, y, { width: 130 });
        doc.font('Helvetica-Bold').text(String(v), 175, y, { width: CW - 135 });
        y += 13;
      });
      y += 10;
      if (!result) {
        doc.font('Helvetica').fontSize(10).fillColor('#888').text('No result data', 40, y);
        continue;
      }
      doc.font('Helvetica-Bold').fontSize(9.5).fillColor('#0b5394').text(
        `GPA (without 4th): ${result.total_gpa_without_4th.toFixed(2)}    4th bonus: ${result.gpa_4th_bonus.toFixed(2)}    Final GPA: ${result.final_gpa.toFixed(2)}`,
        40, y, { width: CW });
      y += 16;
      doc.fillColor(result.result_status === 'PASSED' ? '#1e7d32' : '#c62828').font('Helvetica-Bold').fontSize(11)
        .text('Result: ' + result.result_status, 40, y);
      y += 20;
      doc.fillColor('#111111');
      const cols = [{ w: 235, t: 'Subject' }, { w: 70, t: 'Total' }, { w: 100, t: 'Grade' }, { w: 80, t: 'GPA' }];
      const rowH = 18, tableX = 40;
      doc.fillColor('#0b5394').rect(tableX, y, CW, rowH).fill();
      doc.fillColor('#ffffff').font('Helvetica-Bold').fontSize(9);
      let cx = tableX;
      cols.forEach(c => { doc.text(c.t, cx + 5, y + 5, { width: c.w - 10, align: cx === tableX ? 'left' : 'center' }); cx += c.w; });
      y += rowH;
      doc.fillColor('#111111');
      result.families.forEach((f, i) => {
        if (y > doc.page.height - 70) { doc.addPage(); y = 40; }
        if (i % 2 === 0) { doc.fillColor('#eef3f9').rect(tableX, y, CW, rowH).fill(); }
        doc.fillColor('#111111').font('Helvetica').fontSize(9);
        const display = (f.is_optional ? '(4th) ' : '') + f.subject;
        cx = tableX;
        doc.text(display, cx + 5, y + 5, { width: cols[0].w - 10 }); cx += cols[0].w;
        doc.text(f.absent ? 'Absent' : `${f.total}/${f.full}`, cx + 5, y + 5, { width: cols[1].w - 10, align: 'center' }); cx += cols[1].w;
        doc.text(f.absent ? '—' : f.letter_grade, cx + 5, y + 5, { width: cols[2].w - 10, align: 'center' }); cx += cols[2].w;
        doc.text(f.absent ? '—' : f.grade_point.toFixed(1), cx + 5, y + 5, { width: cols[3].w - 10, align: 'center' });
        y += rowH;
      });
      doc.strokeColor('#0b5394').lineWidth(1).rect(tableX, y - rowH * result.families.length, CW, rowH * result.families.length).stroke();
    }
    doc.end();
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/marksheet/:studentId/:eventId', async (req, res) => {
  try {
    const [[student]] = await pool.query(
      `SELECT s.*, c.name AS class_name, c.section, c.group_name
       FROM students s JOIN classes c ON s.class_id = c.id WHERE s.id = ?`,
      [req.params.studentId]
    );
    if (!student) return res.status(404).json({ error: 'Student not found' });
    const [[event]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [req.params.eventId]);
    const result = await computeResult(student.id, Number(req.params.eventId));
    const [[saved]] = await pool.query(
      'SELECT id, teacher_remarks FROM results WHERE student_id=? AND exam_id=?',
      [student.id, req.params.eventId]
    );
    const [[hi]] = await pool.query(
      `SELECT MAX(r.final_gpa) AS gpa FROM results r JOIN students s ON s.id=r.student_id
       WHERE r.exam_id=? AND s.class_id=?`, [req.params.eventId, student.class_id]);
    const [att] = await pool.query(
      `SELECT status, COUNT(*) AS c FROM attendance WHERE student_id=? GROUP BY status`,
      [student.id]);
    const [settingsRows] = await pool.query('SELECT setting_key, setting_value FROM app_settings');
    const settings = {};
    settingsRows.forEach(s => { settings[s.setting_key] = s.setting_value; });
    res.json({ student, event, result, remarks: saved ? saved.teacher_remarks : null, settings,
      serial_no: saved ? 'MS-' + req.params.eventId + '-' + String(saved.id).padStart(4, '0') : '—',
      class_highest_gpa: hi && hi.gpa != null ? Number(hi.gpa) : null,
      attendance: att });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Multi-page PDF marksheet: page 1 = transcript summary incl. 4th-subject bonus GPA;
// later pages = per-subject breakdown, attendance, subject comments and complaints/remarks.
router.get('/marksheet-pdf/:studentId/:eventId', async (req, res) => {
  try {
    const [[student]] = await pool.query(
      `SELECT s.*, c.name AS class_name, c.section, c.group_name
       FROM students s JOIN classes c ON s.class_id = c.id WHERE s.id = ?`,
      [req.params.studentId]
    );
    if (!student) return res.status(404).json({ error: 'Student not found' });
    const [[event]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [req.params.eventId]);
    if (!event) return res.status(404).json({ error: 'Event not found' });
    const result = await computeResult(student.id, Number(req.params.eventId));
    if (!result) return res.status(404).json({ error: 'No marksheet available for this student/event' });
    const [[saved]] = await pool.query(
      'SELECT teacher_remarks FROM results WHERE student_id=? AND exam_id=?',
      [student.id, req.params.eventId]
    );
    const [settingsRows] = await pool.query('SELECT setting_key, setting_value FROM app_settings');
    const settings = {};
    settingsRows.forEach(s => { settings[s.setting_key] = s.setting_value; });

    const [attRows] = await pool.query(
      'SELECT status, COUNT(*) AS cnt FROM attendance WHERE student_id=? GROUP BY status', [student.id]
    );
    const [complaints] = await pool.query(
      `SELECT n.title, n.body, n.type, n.created_at FROM notifications n
       WHERE n.student_id=? AND n.type IN ('complaint','special') ORDER BY n.id DESC LIMIT 10`, [student.id]
    );
    const [comments] = await pool.query(
      `SELECT sub.name AS subject_name, e.name AS exam_name, m.comment
       FROM marks m JOIN exams e ON m.exam_id = e.id JOIN subjects sub ON e.subject_id = sub.id
       WHERE m.student_id=? AND e.event_id=? AND m.comment IS NOT NULL AND m.comment <> ''
       ORDER BY m.id`, [student.id, req.params.eventId]
    );

    const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename=marksheet_${student.student_code}_event${req.params.eventId}.pdf`);
    doc.pipe(res);

    const CW = doc.page.width - 80;
    let y = 0;
    const pageGap = () => {
      if (y > doc.page.height - 60) { doc.addPage(); y = 40; return true; }
      return false;
    };

    // -------- Page 1: transcript summary --------
    const schoolName = settings.school_name || settings.school || settings.school_name_en || 'School';
    const schoolAddr = settings.school_address || settings.address || settings.school_phone || '';
    doc.font('Helvetica-Bold').fontSize(16).fillColor('#0b3d91').text(String(schoolName), 40, 50, { align: 'center', width: CW });
    y = 80;
    if (schoolAddr) {
      doc.font('Helvetica').fontSize(9).fillColor('#555555').text(String(schoolAddr), 40, y, { align: 'center', width: CW });
      y += 14;
    }
    doc.fillColor('#111111').font('Helvetica-Bold').fontSize(11).text('Academic Transcript — ' + String(event.name), 40, y, { align: 'center', width: CW });
    y += 26;

    doc.font('Helvetica-Bold').fontSize(10).fillColor('#0b3d91').text('Student Information', 40, y);
    y += 16;
    doc.fillColor('#111111');
    const infoLines = [
      ['Student Name', student.name],
      ['Student Code', String(student.student_code)],
      ['Roll', String(student.roll)],
      ['Class', `${student.class_name}${student.group_name ? ' (' + student.group_name + ')' : ' (' + student.section + ')'}`],
      ['Religion', student.religion || '—']
    ];
    infoLines.forEach(([k, v]) => {
      doc.font('Helvetica').fontSize(9.5);
      doc.text(k + ':', 40, y, { width: 130 });
      doc.font('Helvetica-Bold').text(String(v), 175, y, { width: CW - 135 });
      y += 13;
    });

    y += 12;
    doc.font('Helvetica-Bold').fontSize(9.5).fillColor('#0b5394').text(
      `GPA (without 4th subject): ${result.total_gpa_without_4th.toFixed(2)}    4th-subject bonus: ${result.gpa_4th_bonus.toFixed(2)}    Final GPA: ${result.final_gpa.toFixed(2)}`,
      40, y, { width: CW });
    y += 16;
    doc.fillColor(result.result_status === 'PASSED' ? '#1e7d32' : '#c62828').font('Helvetica-Bold').fontSize(12)
      .text('Result: ' + result.result_status, 40, y);
    y += 20;
    doc.fillColor('#111111');

    // grading table
    const cols = [{ w: 215, t: 'Subject' }, { w: 60, t: 'Total' }, { w: 65, t: 'Scaled %' }, { w: 90, t: 'Grade' }, { w: 85, t: 'GPA' }];
    const rowH = 18;
    const tableX = 40;
    doc.fillColor('#0b5394').rect(tableX, y, CW, rowH).fill();
    doc.fillColor('#ffffff').font('Helvetica-Bold').fontSize(9);
    let cx = tableX;
    cols.forEach(c => { doc.text(c.t, cx + 5, y + 5, { width: c.w - 10, align: cx === tableX ? 'left' : 'center' }); cx += c.w; });
    y += rowH;
    doc.fillColor('#111111');
    result.families.forEach((f, i) => {
      pageGap();
      if (i % 2 === 0) { doc.fillColor('#eef3f9').rect(tableX, y, CW, rowH).fill(); }
      doc.fillColor('#111111').font('Helvetica').fontSize(9);
      const display = (f.is_optional ? '(4th) ' : '') + f.subject;
      cx = tableX;
      doc.text(display, cx + 5, y + 5, { width: cols[0].w - 10 }); cx += cols[0].w;
      doc.text(f.absent ? 'Absent' : `${f.total}/${f.full}`, cx + 5, y + 5, { width: cols[1].w - 10, align: 'center' }); cx += cols[1].w;
      doc.text(f.absent ? '—' : f.scaled.toFixed(2), cx + 5, y + 5, { width: cols[2].w - 10, align: 'center' }); cx += cols[2].w;
      doc.text(f.absent ? '—' : f.letter_grade, cx + 5, y + 5, { width: cols[3].w - 10, align: 'center' }); cx += cols[3].w;
      doc.text(f.absent ? '—' : f.grade_point.toFixed(1), cx + 5, y + 5, { width: cols[4].w - 10, align: 'center' });
      y += rowH;
    });
    doc.strokeColor('#0b5394').lineWidth(1).rect(tableX, y - rowH * result.families.length, CW, rowH * result.families.length).stroke();
    y += 12;
    if (saved && saved.teacher_remarks) {
      pageGap();
      doc.font('Helvetica-Bold').fontSize(9.5).fillColor('#111111').text('Teacher Remarks:', 40, y);
      y += 14;
      doc.font('Helvetica-Oblique').fontSize(9.5).text(String(saved.teacher_remarks), 40, y, { width: CW });
      y += 20;
    }

    // -------- Later pages: detail --------
    doc.addPage();
    y = 40;
    doc.font('Helvetica-Bold').fontSize(12).fillColor('#0b5394').text('Subject-wise Marks', 40, y);
    y += 20;
    for (const f of result.families) {
      pageGap();
      doc.fillColor('#111111').font('Helvetica-Bold').fontSize(9.5)
        .text(`${f.is_optional ? '(4th Subject) ' : ''}${f.subject} — ${f.letter_grade} (GPA ${f.grade_point.toFixed(1)}, ${f.scaled.toFixed(2)}%)`, 40, y);
      y += 15;
      const pd0 = f.paper_details && f.paper_details[0];
      const detail = f.paper_details && f.paper_details.length > 1
        ? f.paper_details.map(pd => {
            const comps = [
              pd.cq != null ? 'CQ ' + pd.cq : '',
              pd.mcq != null ? 'MCQ ' + pd.mcq : '',
              pd.practical != null ? 'Practical ' + pd.practical : '',
              pd.written != null ? 'Written ' + pd.written : '',
              pd.marks != null ? 'Total ' + pd.marks : ''
            ].filter(Boolean).join('  ');
            return `${pd.subject_name}${comps ? '  ›  ' + comps : ''}  [${pd.letter_grade}]`;
          })
        : [pd0 ? `${pd0.subject_name}${pd0.marks != null ? '  ›  Total ' + pd0.marks : ''}  [${pd0.letter_grade}]` : '—'];
      doc.font('Helvetica').fontSize(9);
      detail.forEach(line => {
        if (pageGap()) {}
        doc.text('• ' + line, 55, y, { width: CW - 15 });
        y += 13;
      });
      y += 4;
    }

    y += 8;
    pageGap();
    doc.font('Helvetica-Bold').fontSize(12).fillColor('#0b5394').text('Attendance Summary', 40, y);
    y += 16;
    doc.font('Helvetica').fontSize(9.5).fillColor('#111111')
      .text(attRows.length ? `Total recorded: ${attRows.reduce((s, r) => s + Number(r.cnt), 0)}  |  ${attRows.map(r => r.status + ': ' + r.cnt).join(', ')}` : 'No attendance records', 40, y, { width: CW });
    y += 18;

    if (comments.length) {
      pageGap();
      doc.font('Helvetica-Bold').fontSize(12).fillColor('#0b5394').text('Subject Comments', 40, y);
      y += 16;
      doc.font('Helvetica').fontSize(9.5).fillColor('#111111');
      comments.forEach(c => {
        pageGap();
        doc.text(`• ${c.subject_name} (${c.exam_name}): ${c.comment}`, 55, y, { width: CW - 15 });
        y += 14;
      });
      y += 6;
    }

    if (complaints.length) {
      pageGap();
      doc.font('Helvetica-Bold').fontSize(12).fillColor('#0b5394').text('Complaints & Remarks History', 40, y);
      y += 16;
      doc.font('Helvetica').fontSize(9.5).fillColor('#111111');
      complaints.forEach(c => {
        pageGap();
        doc.text(`• [${String(c.type).toUpperCase()}] ${c.title}: ${c.body} (${String(c.created_at).slice(0, 10)})`, 55, y, { width: CW - 15 });
        y += 14;
      });
    }

    const pages = doc.bufferedPageRange();
    for (let i = pages.start; i < pages.start + pages.count; i++) {
      doc.switchToPage(i);
      doc.font('Helvetica').fontSize(8).fillColor('#888888')
        .text(`Page ${i - pages.start + 1} of ${pages.count}`, 40, doc.page.height - 36, { align: 'center', width: CW });
      if (i === pages.start) {
        doc.text('Generated on ' + new Date().toISOString().slice(0, 10), 40, doc.page.height - 26, { align: 'center', width: CW });
      }
    }
    doc.end();
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/results/remarks', async (req, res) => {
  const { student_id, exam_id, teacher_remarks } = req.body || {};
  if (!student_id || !exam_id) return res.status(400).json({ error: 'student_id, exam_id required' });
  try {
    if (req.user.role !== 'admin') {
      // Teacher may only set remarks on results tied to their own subject exams
      const [owned] = await pool.query(
        `SELECT 1 FROM results r JOIN exams e ON e.id=r.exam_id JOIN subjects sub ON sub.id=e.subject_id
         WHERE r.student_id=? AND r.exam_id=? AND sub.teacher_id=?`,
        [student_id, exam_id, req.user.id]
      );
      if (owned.length === 0) return res.status(403).json({ error: 'Not authorized to edit this result' });
    }
    await pool.query('UPDATE results SET teacher_remarks=? WHERE student_id=? AND exam_id=?',
      [teacher_remarks || '', student_id, exam_id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;
module.exports.ensureSessionExams = ensureSessionExams;
module.exports.findOrCreateSessionByYear = findOrCreateSessionByYear;
module.exports.CANON = CANON;