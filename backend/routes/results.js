const router = require('express').Router();
const pool = require('../db');
const { getClassSignatories } = require('../lib/teacher_signatures');
const { dhakaToday } = require('../dates');
const {
  eventIsPublished,
  advanceActiveYear,
} = require('../lib/academic_session');
const { auth } = require('../middleware/auth');
const { computeResult } = require('../grading');
const { queuePush, getGuardianTokens } = require('../fcm');
const PDFDocument = require('pdfkit');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { loadSchoolLogo } = require('../lib/school_logo');
const { loadStudentActivities } = require('../lib/student_activities');
const {
  decidePromotionByGrace,
  normalizeSubjectFamily,
} = require('../lib/promotion_grace');
const promotionEngine = require('../promotion_engine');

function resultGradeRank(gpa) {
  const n = Number(gpa || 0);
  return n >= 5 ? 7 : n >= 4 ? 6 : n >= 3.5 ? 5 : n >= 3 ? 4 : n >= 2 ? 3 : n >= 1 ? 2 : 1;
}

async function resultPositionSnapshot(studentId, classId, eventId) {
  const [[cls]] = await pool.query('SELECT name, group_name FROM classes WHERE id=?', [classId]);
  if (!cls) return null;
  const [[rank]] = await pool.query(
    'SELECT section_position, combined_position, section_size, combined_size FROM results WHERE student_id=? AND exam_id=?', [studentId, eventId]);
  const [[sectionCount]] = await pool.query(
    `SELECT COUNT(*) AS c FROM results r JOIN students s ON s.id=r.student_id
      WHERE r.exam_id=? AND s.class_id=?`, [eventId, classId]);
  const [[combinedCount]] = await pool.query(
    `SELECT COUNT(*) AS c FROM results r JOIN students s ON s.id=r.student_id JOIN classes c ON c.id=s.class_id
      WHERE r.exam_id=? AND c.name=? AND COALESCE(c.group_name,'')=COALESCE(?,'')`,
    [eventId, cls.name, cls.group_name]);
  if (!rank || (rank.section_position == null && rank.combined_position == null)) return null;
  return {
    section: rank.section_position, section_of: Number(rank.section_size || sectionCount?.c || 0),
    combined: rank.combined_position, combined_of: Number(rank.combined_size || combinedCount?.c || 0),
  };
}

// Result computation, tabulation and marksheets are school-wide admin operations.
// Teachers enter marks through /api/teacher — they must NOT compute/tabulate
// arbitrary classes or read arbitrary student marksheets.
router.use(auth('admin'));

// Register Bangla font for PDFKit
function registerBanglaFont(doc) {
  const fontPath = path.join(__dirname, '..', 'assets', 'fonts', 'Kalpurush.ttf');
  if (fs.existsSync(fontPath)) {
    doc.registerFont('Kalpurush', fontPath);
    return 'Kalpurush';
  }
  return 'Helvetica';
}

// Helper to draw watermark logo
function drawWatermark(doc, logoImage, pageWidth, pageHeight) {
  if (!logoImage || (typeof logoImage === 'string' && !fs.existsSync(logoImage))) return;
  try {
    const img = doc.openImage(logoImage);
    const maxDim = Math.min(pageWidth, pageHeight) * 0.6;
    const scale = Math.min(maxDim / img.width, maxDim / img.height);
    const w = img.width * scale;
    const h = img.height * scale;
    const x = (pageWidth - w) / 2;
    const y = (pageHeight - h) / 2;
    doc.save()
      .opacity(0.04)
      .image(logoImage, x, y, { width: w, height: h })
      .restore();
  } catch (_) {}
}

// Helper to draw page frame (decorative borders)
function drawFrame(doc, margin) {
  const pw = doc.page.width;
  const ph = doc.page.height;
  const m = margin;
  doc.save()
    .lineWidth(2)
    .strokeColor('#222222')
    .rect(m, m, pw - 2*m, ph - 2*m)
    .stroke()
    .lineWidth(0.5)
    .strokeColor('#777777')
    .rect(m + 4, m + 4, pw - 2*m - 8, ph - 2*m - 8)
    .stroke()
    .restore();
}

// Helper to draw rosette decoration
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
  special_model_test: { label: 'Special Model Test', promotion_linked: 0 },
};
const CANON_KINDS = Object.keys(CANON);

// Model-test rosters are limited to students promoted by the previous year's
// Class 10 Test into this exact academic session.
function modelTestPromotionExists(studentAlias = 's') {
  return `EXISTS (SELECT 1 FROM promotions mp
    JOIN exam_events source_test ON source_test.id=mp.event_id
    WHERE mp.student_id=${studentAlias}.id AND mp.decision='promoted'
      AND mp.destination_session_id=? AND source_test.exam_kind='test' AND source_test.year=?)`;
}
const isCanon = k => CANON_KINDS.indexOf(k) !== -1;

function sessionYear(name) {
  const m = String(name || '').match(/(19|20)\d{2}/);
  if (m) return Number(m[0]);
  return new Date().getFullYear();
}

// Create the 4 canonical event shells for a session when missing. Legacy
// same-name events are adopted (kind/year stamped) instead of duplicated.
async function ensureSessionExams(sessionId, db = pool) {
  const [[sess]] = await db.query('SELECT id, name FROM sessions WHERE id=?', [sessionId]);
  if (!sess) throw Object.assign(new Error('Session not found'), { status: 404 });
  const year = sessionYear(sess.name);
  if (!(await isAcademicSessionOpen(year, db))) {
    throw Object.assign(new Error(`আগের session ${year - 1}-এর Class 10 Test exam publish হয়নি।`), {
      status: 409,
      code: 'PREVIOUS_TEST_NOT_PUBLISHED',
    });
  }
  const created = [], adopted = [], skipped = [];
  // Class mapping per exam kind
  const kindClasses = {
    special_model_test: ["SSC Batch"],
    pretest: ["Class 10"],
    test: ["Class 10"],
    half_yearly: ["Class 6", "Class 7", "Class 8", "Class 9"],
    annual: ["Class 6", "Class 7", "Class 8", "Class 9"],
  };

  for (const kind of CANON_KINDS) {
    const name = `${CANON[kind].label} ${year}`;
    const [same] = await db.query(
      'SELECT id, exam_kind FROM exam_events WHERE session_id=? AND exam_kind=? AND year=?', [sessionId, kind, year]);
    if (same.length) { skipped.push({ kind, id: same[0].id, name }); continue; }
    const [byName] = await db.query(
      'SELECT id FROM exam_events WHERE session_id=? AND name=?', [sessionId, name]);
    if (byName.length) {
      await db.query('UPDATE exam_events SET exam_kind=?, year=?, promotion_linked=? WHERE id=?',
        [kind, year, CANON[kind].promotion_linked, byName[0].id]);
      adopted.push({ kind, id: byName[0].id, name });
      continue;
    }
    // Get class_ids for this kind
    const classNames = kindClasses[kind] || [];
    let classIdsArr = [];
    if (classNames.length) {
      // `name IN (?)` is rewritten by the PostgreSQL compatibility layer as
      // `name = ANY(?)`; here the one name is a scalar, not a SQL array.
      const classFilter = classNames.length === 1
        ? 'name=?'
        : `name IN (${classNames.map(() => '?').join(',')})`;
      const [classes] = await db.query(
        `SELECT id FROM classes WHERE ${classFilter}`,
        classNames
      );
      classIdsArr = classes.map(c => Number(c.id));
    }
    try {
      const [r] = await db.query(
        `INSERT INTO exam_events
          (name, session_id, exam_kind, year, promotion_linked, is_published, notify_guardians, entry_open, class_ids)
         VALUES (?,?,?,?,?,0,0,0,?)`,
        [name, sessionId, kind, year, CANON[kind].promotion_linked, classIdsArr.length ? JSON.stringify(classIdsArr) : null]);
      // Also populate exam_event_classes
      if (classIdsArr.length) {
        try {
          const vals = classIdsArr.map(()=>'(?,?)').join(',');
          const params = [];
          for (const cid of classIdsArr) { params.push(r.insertId, cid); }
          await db.query(`INSERT IGNORE INTO exam_event_classes (event_id, class_id) VALUES ${vals}`, params);
        } catch(e) { console.error('exam_event_classes insert err', e.message); }
      }
      created.push({ kind, id: r.insertId, name });
    } catch (e) {
      if (e.code === '23505') skipped.push({ kind, name, note: 'already exists for year' });
      else throw e;
    }
  }
  // Provision each canonical event's subject rows with the academic session.
  // They remain locked until the admin unlocks the event banner.
  await ensureCanonicalSubjectExams(sessionId, db);
  return { session: sess, year, created, adopted, skipped };
}

async function ensureCanonicalSubjectExams(sessionId, db = pool) {
  const [[admin]] = await db.query("SELECT id FROM users WHERE role='admin' ORDER BY id LIMIT 1");
  if (!admin) return { created: 0 };
  const [events] = await db.query(
    `SELECT id, name, exam_kind, class_ids FROM exam_events
     WHERE session_id=? AND exam_kind IN ('half_yearly','annual','pretest','test','special_model_test')`,
    [sessionId]);
  let created = 0;
  for (const ev of events) {
    const allowed = ev.exam_kind === 'special_model_test' ? /ssc\s*batch/i
      : ['pretest','test'].includes(ev.exam_kind) ? /class\s*10\b/i : /class\s*[6-9]\b/i;
    const [classes] = await db.query('SELECT id,name FROM classes');
    let ids = ev.class_ids;
    if (typeof ids === 'string') { try { ids = JSON.parse(ids); } catch (_) { ids = null; } }
    if (!Array.isArray(ids) || ids.length === 0) {
      ids = classes.filter(c => allowed.test(String(c.name || ''))).map(c => Number(c.id));
      await db.query('UPDATE exam_events SET class_ids=? WHERE id=?', [JSON.stringify(ids), ev.id]);
      if (ids.length) {
        const values = ids.map(() => '(?,?)').join(',');
        await db.query(`INSERT IGNORE INTO exam_event_classes (event_id,class_id) VALUES ${values}`,
          ids.flatMap(id => [ev.id, id])).catch(() => {});
      }
    }
    const selected = classes.filter(c => Array.isArray(ids) && ids.length
      ? ids.map(Number).includes(Number(c.id)) : allowed.test(String(c.name || '')));
    for (const cls of selected) {
      const [subjects] = await db.query('SELECT id,name FROM subjects WHERE class_id=? ORDER BY name', [cls.id]);
      for (const subject of subjects) {
        const [[existing]] = await db.query(
          'SELECT id FROM exams WHERE event_id=? AND class_id=? AND subject_id=?', [ev.id, cls.id, subject.id]);
        if (existing) continue;
        await db.query(
          `INSERT INTO exams (name,exam_type,class_id,subject_id,source,created_by,event_id,status,entry_open)
           VALUES (?,'class_test',?,?, 'admin', ?,?,'draft',0)`,
          [`${ev.name} - ${subject.name}`, cls.id, subject.id, admin.id, ev.id]);
        created++;
      }
    }
  }
  return { created };
}

async function firstAcademicSessionYear(db = pool) {
  const [active] = await db.query('SELECT name FROM sessions WHERE is_active=1 ORDER BY name LIMIT 1');
  if (active.length) return sessionYear(active[0].name);
  const [withEvents] = await db.query(
    `SELECT s.name FROM sessions s JOIN exam_events e ON e.session_id=s.id
     ORDER BY s.name LIMIT 1`);
  if (withEvents.length) return sessionYear(withEvents[0].name);
  return Number(dhakaToday().slice(0, 4));
}

async function isAcademicSessionOpen(year, db = pool) {
  const requestedYear = Number(year);
  if (!requestedYear) return false;
  const firstYear = await firstAcademicSessionYear(db);
  if (requestedYear <= firstYear) return requestedYear === firstYear;
  const [rows] = await db.query(
    `SELECT e.year, e.exam_kind, e.is_published FROM exam_events e
     JOIN sessions s ON s.id=e.session_id
     WHERE e.year=? AND s.name=? AND e.exam_kind='test'`,
    [requestedYear - 1, String(requestedYear - 1)]
  );
  return eventIsPublished(rows, requestedYear - 1, 'test');
}

// A new session opens and becomes active as soon as the previous year's
// Class 10 Test is published. Calendar rollover alone never promotes or moves
// students; promotion decisions remain a separate admin workflow.
async function syncCurrentAcademicSession(db = pool) {
  let firstYear = await firstAcademicSessionYear(db);
  let [[anchor]] = await db.query('SELECT id, name FROM sessions WHERE name=?', [String(firstYear)]);
  if (!anchor) {
    await db.query(
      'INSERT INTO sessions (name, is_active) VALUES (?,0) ON CONFLICT (name) DO NOTHING',
      [String(firstYear)]
    );
    [[anchor]] = await db.query('SELECT id, name FROM sessions WHERE name=?', [String(firstYear)]);
    if (!anchor) throw new Error(`Could not ensure academic session ${firstYear}`);
  }

  await ensureSessionHorizon(db, firstYear, 2050);
  const [eventRows] = await db.query(
    `SELECT e.year, e.exam_kind, e.is_published, s.name AS session_name
     FROM exam_events e JOIN sessions s ON s.id=e.session_id
     WHERE e.exam_kind IN ('half_yearly','annual','pretest','test','special_model_test')`
  );
  const events = eventRows.map(event => ({
    ...event,
    year: Number(event.year) || sessionYear(event.session_name),
  }));

  const activeYear = advanceActiveYear(firstYear, 2050, events);
  let [[session]] = await db.query('SELECT id, name FROM sessions WHERE name=?', [String(activeYear)]);
  if (!session) {
    await db.query(
      'INSERT INTO sessions (name, is_active) VALUES (?,0) ON CONFLICT (name) DO NOTHING',
      [String(activeYear)]
    );
    [[session]] = await db.query('SELECT id, name FROM sessions WHERE name=?', [String(activeYear)]);
  }
  if (!session) throw new Error(`Could not ensure academic session ${activeYear}`);

  await db.query(
    'UPDATE sessions SET is_active=CASE WHEN name=? THEN 1 ELSE 0 END',
    [String(activeYear)]
  );
  await ensureSessionExams(session.id, db);
  return { ...session, is_active: 1, current_year: activeYear };
}

// Provision the requested planning horizon once, using the same canonical
// event builder as manually-created sessions. Existing years are left intact.
let canonicalIndexReady;
async function ensureCanonicalEventIndex(db = pool) {
  if (/^mysql:\/\//i.test(process.env.DATABASE_URL || '')) return;
  if (canonicalIndexReady) return canonicalIndexReady;
  canonicalIndexReady = (async () => {
    const [[index]] = await db.query(
      `SELECT indexdef FROM pg_indexes WHERE schemaname='public' AND indexname='uq_event_kind_year'`);
    if (index && String(index.indexdef).includes('special_model_test')) return;
    if (index) await db.query('DROP INDEX IF EXISTS public.uq_event_kind_year');
    await db.query(`CREATE UNIQUE INDEX uq_event_kind_year
      ON public.exam_events (exam_kind, year)
      WHERE exam_kind IN ('half_yearly','annual','pretest','test','special_model_test')
        AND year IS NOT NULL`);
  })().catch(err => { canonicalIndexReady = null; throw err; });
  return canonicalIndexReady;
}

async function ensureSessionHorizon(db = pool, firstYear = null, lastYear = 2050) {
  firstYear = Number(firstYear) || await firstAcademicSessionYear(db);
  const endYear = Math.max(Number(lastYear), firstYear);
  const [existingRows] = await db.query('SELECT name FROM sessions WHERE name>=? AND name<=?', [String(firstYear), String(endYear)]);
  const existing = new Set(existingRows.map(row => String(row.name)));
  const created = [];
  for (let year = firstYear; year <= endYear; year++) {
    if (!existing.has(String(year))) created.push(year);
  }
  if (created.length) {
    const values = created.map(() => '(?,0)').join(',');
    await db.query(
      `INSERT INTO sessions (name, is_active) VALUES ${values} ON CONFLICT (name) DO NOTHING`,
      created.map(String)
    );
  }
  return { first_year: firstYear, last_year: lastYear, created };
}

// Keep future session class filters in step when an admin adds, renames or
// removes a section. Event shells store class ids so later auto-create only
// creates subject exams for the matching grade band.
async function syncCanonicalEventClasses(db = pool) {
  const [classes] = await db.query('SELECT id, name FROM classes');
  const [events] = await db.query(
    `SELECT id, exam_kind FROM exam_events
     WHERE exam_kind IN ('half_yearly','annual','pretest','test','special_model_test')`
  );
  const allowed = {
    half_yearly: c => /class\s*[6-9]\b/i.test(String(c.name || '')),
    annual: c => /class\s*[6-9]\b/i.test(String(c.name || '')),
    pretest: c => /class\s*10\b/i.test(String(c.name || '')),
    test: c => /class\s*10\b/i.test(String(c.name || '')),
    special_model_test: c => /ssc\s*batch/i.test(String(c.name || '')),
  };
  for (const event of events) {
    const [[snapshot]] = await db.query('SELECT class_ids FROM exam_events WHERE id=?', [event.id]);
    // The first mapping is this year's roster snapshot; preserve historical scope.
    if (snapshot && snapshot.class_ids != null) continue;
    const classIds = classes.filter(allowed[event.exam_kind] || (() => false)).map(c => Number(c.id));
    await db.query('UPDATE exam_events SET class_ids=? WHERE id=?', [JSON.stringify(classIds), event.id]);
    if (classIds.length) {
      const values = classIds.map(() => '(?,?)').join(',');
      await db.query(`INSERT IGNORE INTO exam_event_classes (event_id,class_id) VALUES ${values}`,
        classIds.flatMap(id => [event.id, id])).catch(() => {});
    }
  }
  return { events: events.length };
}

async function findOrCreateSessionByYear(year) {
  const [rows] = await pool.query('SELECT id, name FROM sessions WHERE name=?', [String(year)]);
  if (rows.length) return rows[0];
  await pool.query('INSERT INTO sessions (name, is_active) VALUES (?,0) ON CONFLICT (name) DO NOTHING', [String(year)]);
  const [[session]] = await pool.query('SELECT id, name FROM sessions WHERE name=?', [String(year)]);
  if (!session) throw new Error(`Could not ensure academic session ${year}`);
  return session;
}

async function openNextSessionAfterTest(event, actorId) {
  if (!event || event.exam_kind !== 'test' || !event.year) return null;
  const [[class10]] = await pool.query(
    `SELECT 1 AS ok FROM exams x JOIN classes c ON c.id=x.class_id
     WHERE x.event_id=? AND c.name ~* 'class[[:space:]]*10([[:space:]]|$)' LIMIT 1`,
    [event.id]
  );
  if (!class10) throw new Error('Published Test event is not assigned to Class 10.');
  const session = await findOrCreateSessionByYear(Number(event.year) + 1);
  await ensureSessionExams(session.id);
  await pool.query(
    'INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
    [actorId, 'session_open', `Opened academic session ${session.name} after publishing ${event.name}`]
  ).catch(() => {});
  return session.name;
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
      `SELECT e.*, s.name AS session_name, s.is_active AS session_is_active,
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
  const { name, session_id, start_date, exam_date, result_date, exam_kind, year, promotion_linked, class_ids } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name required' });
  const kind = exam_kind || 'other';
  const yr = year != null && year !== '' ? Number(year) : null;
  if (isCanon(kind) && !yr) return res.status(400).json({ error: 'year required for ' + kind });
  try {
    if (isCanon(kind)) {
      const [[session]] = await pool.query('SELECT id, name FROM sessions WHERE id=?', [session_id || 1]);
      const sessionYearValue = sessionYear(session?.name);
      if (!session || yr !== sessionYearValue) {
        return res.status(400).json({
          error: `পরীক্ষার বছর শিক্ষাবর্ষের সঙ্গে মিলতে হবে (${session?.name || 'সেশন নেই'} → ${sessionYearValue || '—'})।`,
        });
      }
      if (!(await isAcademicSessionOpen(yr))) {
        return res.status(409).json({
          error: `আগের session ${yr - 1}-এর Class 10 Test exam publish হয়নি।`,
          code: 'PREVIOUS_TEST_NOT_PUBLISHED',
        });
      }
    }
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
    const classIdsArr = Array.isArray(class_ids) ? class_ids.map(x=>Number(x)).filter(x=>!isNaN(x)) : null;
    const [result] = await pool.query(
      'INSERT INTO exam_events (name, session_id, start_date, exam_date, result_date, created_by, exam_kind, year, promotion_linked, class_ids) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [name, session_id || 1, start_date || null, exam_date || null, result_date || null, req.user.id, kind,
       yr, promotion_linked != null ? Number(promotion_linked) : (isCanon(kind) ? CANON[kind].promotion_linked : 0),
       classIdsArr ? JSON.stringify(classIdsArr) : null]
    );
    const eventId = result.insertId;
    if (classIdsArr && classIdsArr.length) {
      try {
        const vals = classIdsArr.map(()=>'(?,?)').join(',');
        const params = [];
        for (const cid of classIdsArr) { params.push(eventId, cid); }
        await pool.query(`INSERT IGNORE INTO exam_event_classes (event_id, class_id) VALUES ${vals}`, params);
      } catch(e) { console.error('exam_event_classes insert err', e.message); }
    }
    res.status(201).json({ id: eventId });
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
  const reason = String((req.body && req.body.reason) || '').trim();
  if (!reason) return res.status(400).json({ error: 'পরীক্ষা delete করার কারণ লিখতে হবে।' });
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [[event]] = await conn.query('SELECT * FROM exam_events WHERE id=? FOR UPDATE', [req.params.id]);
    if (!event) { await conn.rollback(); return res.status(404).json({ error: 'Event not found' }); }
    const [exams] = await conn.query('SELECT * FROM exams WHERE event_id=?', [req.params.id]);
    const examIds = exams.map(e => e.id);
    const [markRows] = examIds.length
      ? await conn.query('SELECT * FROM marks WHERE exam_id IN (?)', [examIds])
      : [[]];
    const [resultRows] = await conn.query('SELECT * FROM results WHERE exam_id=?', [req.params.id]);
    const [promotionRows] = await conn.query('SELECT * FROM promotions WHERE event_id=?', [req.params.id]);
    const [notificationRows] = await conn.query(
      `SELECT * FROM notifications WHERE related_id=? OR related_id IN (?)`,
      [req.params.id, examIds.length ? examIds : [-1]]
    );
    const [[admin]] = await conn.query('SELECT name FROM users WHERE id=?', [req.user.id]);
    const audit = {
      event,
      exams,
      marks: markRows,
      results: resultRows,
      promotions: promotionRows,
      notifications: notificationRows,
      reason,
      deleted_by: { id: req.user.id, name: admin?.name || req.user.name || null },
      deleted_at: new Date().toISOString(),
    };
    await conn.query(
      'INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'event_delete', JSON.stringify(audit)]
    );
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
    res.json({ ok: true, deleted_event: Number(req.params.id), exams: examIds.length, marks, results, promotions });
  } catch (err) { try { await conn.rollback(); } catch (e) {} console.error(err); res.status(500).json({ error: 'Server error' }); }
  finally { conn.release(); }
});

router.put('/events/:id', async (req, res) => {
  const { name, session_id, start_date, exam_date, result_date, exam_kind, year, promotion_linked, class_ids, entry_open } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name required' });
  try {
    const [[ev]] = await pool.query('SELECT id, session_id, year, exam_kind FROM exam_events WHERE id=?', [req.params.id]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    const kind = exam_kind !== undefined ? (exam_kind || 'other') : undefined;
    const yr = year !== undefined ? (year === '' || year == null ? null : Number(year)) : undefined;
    const nextKind = kind === undefined ? ev.exam_kind : kind;
    const nextYear = yr === undefined ? Number(ev.year) : yr;
    const nextSessionId = session_id === undefined ? ev.session_id : Number(session_id || 1);
    if (isCanon(nextKind)) {
      if (nextYear == null) return res.status(400).json({ error: 'year required for ' + nextKind });
      const [[targetSession]] = await pool.query('SELECT name FROM sessions WHERE id=?', [nextSessionId]);
      if (!targetSession || Number(sessionYear(targetSession.name)) !== Number(nextYear)) {
        return res.status(400).json({ error: 'পরীক্ষার বছর শিক্ষাবর্ষের সঙ্গে মিলতে হবে।' });
      }
      if (!(await isAcademicSessionOpen(nextYear))) {
        return res.status(409).json({
          error: `আগের session ${nextYear - 1}-এর Class 10 Test exam publish হয়নি।`,
          code: 'PREVIOUS_TEST_NOT_PUBLISHED',
        });
      }
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
    if (class_ids !== undefined) {
      const classIdsArr = Array.isArray(class_ids) ? class_ids.map(x=>Number(x)).filter(x=>!isNaN(x)) : null;
      updates.push('class_ids=?'); params.push(classIdsArr ? JSON.stringify(classIdsArr) : null);
      if (classIdsArr && classIdsArr.length) {
        try {
          await pool.query('DELETE FROM exam_event_classes WHERE event_id=?', [req.params.id]);
          const vals = classIdsArr.map(()=>'(?,?)').join(',');
          const p2 = [];
          for (const cid of classIdsArr) { p2.push(req.params.id, cid); }
          await pool.query(`INSERT IGNORE INTO exam_event_classes (event_id, class_id) VALUES ${vals}`, p2);
        } catch(e){}
      }
    }
    if (entry_open !== undefined) {
      updates.push('entry_open=?'); params.push(entry_open ? 1 : 0);
    }
    params.push(req.params.id);
    await pool.query(`UPDATE exam_events SET ${updates.join(', ')} WHERE id=?`, params);
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    if (err.code === '23505') return res.status(409).json({ error: 'এই kind+year-এর exam ইতিমধ্যে আছে।' });
    res.status(500).json({ error: 'Server error' });
  }
});

router.post('/events/:id/entry-open', async (req, res) => {
  try {
    const { open } = req.body || {};
    await pool.query('UPDATE exam_events SET entry_open=? WHERE id=?', [open ? 1 : 0, req.params.id]);
    if (open) {
      await pool.query('UPDATE exams SET entry_open=1 WHERE event_id=? AND status<>\'published\'', [req.params.id]);
    } else {
      await pool.query('UPDATE exams SET entry_open=0 WHERE event_id=?', [req.params.id]);
    }
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Before publishing Annual/Test results, let Admin choose the exact mandatory
// subjects that receive grace. The list is class-specific and never includes
// subjects configured as optional/fourth subjects.
router.get('/events/:id/promotion-grace-options', async (req, res) => {
  try {
    const [[event]] = await pool.query(
      'SELECT id, name, exam_kind, year, is_published FROM exam_events WHERE id=?', [req.params.id]);
    if (!event) return res.status(404).json({ error: 'Event not found' });
    if (!['annual', 'test'].includes(String(event.exam_kind))) {
      return res.status(400).json({ error: 'শুধু Annual অথবা Test পরীক্ষায় subject grace বাছাই করা যাবে।' });
    }
    const [classes] = await pool.query(
      `SELECT DISTINCT c.id AS class_id, c.name AS class_name, c.section, c.group_name
         FROM exams x JOIN classes c ON c.id=x.class_id
        WHERE x.event_id=? ORDER BY c.name, c.section, c.group_name`, [req.params.id]);
    const [subjects] = await pool.query(
      `SELECT DISTINCT x.class_id, sub.id AS subject_id, sub.name AS subject_name
         FROM exams x JOIN subjects sub ON sub.id=x.subject_id
        WHERE x.event_id=? AND COALESCE(sub.is_optional,FALSE)=FALSE
        ORDER BY x.class_id, sub.name`, [req.params.id]);
    const groupedSubjects = new Map();
    for (const subject of subjects) {
      const familyKey = normalizeSubjectFamily(subject.subject_name);
      const groupedKey = `${Number(subject.class_id)}:${familyKey}`;
      const existing = groupedSubjects.get(groupedKey) || {
        class_id: Number(subject.class_id), subject_name: String(subject.subject_name).replace(/\s+(1st|2nd|first|second)$/i, ''), subject_ids: [],
      };
      existing.subject_ids.push(Number(subject.subject_id));
      groupedSubjects.set(groupedKey, existing);
    }
    const subjectOptions = [...groupedSubjects.values()];
    const [selected] = await pool.query(
      `SELECT class_id, subject_id FROM event_promotion_grace WHERE event_id=?`, [req.params.id]);
    res.json({ event, classes: classes.filter(cls => promotionYearForClass(cls.class_name, event.exam_kind)).map(cls => ({
      ...cls,
      subjects: subjectOptions.filter(subject => Number(subject.class_id) === Number(cls.class_id)),
      selected_subject_ids: selected.filter(row => Number(row.class_id) === Number(cls.class_id)).map(row => Number(row.subject_id)),
    })) });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Publish an event: marks it published (Published Exams list), publishes all
// its subject exams (guardian gating), optionally notifies guardians (ADMIN
// decides), and opens the next session only for a published Class 10 Test.
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
  const [[event]] = await pool.query('SELECT exam_kind, session_id, year FROM exam_events WHERE id=?', [eventId]);
  const model = event && event.exam_kind === 'special_model_test';
  const studentScope = model ? ` AND s.session_id=? AND ${modelTestPromotionExists('s')}` : '';
  const markStudentJoin = model ? ` JOIN students s ON s.id=m.student_id AND s.session_id=? AND ${modelTestPromotionExists('s')}` : '';
  const params = [];
  const [classes] = await pool.query(
    `SELECT c.id, c.name, c.section,
      (SELECT COUNT(*) FROM students s WHERE s.class_id=c.id${studentScope}) AS students,
      (SELECT COUNT(DISTINCT m.student_id) FROM marks m${markStudentJoin} JOIN exams x ON x.id=m.exam_id
        WHERE x.event_id=? AND x.class_id=c.id AND x.status<>'published') AS students_done,
      (SELECT COUNT(*) FROM exams x WHERE x.event_id=? AND x.class_id=c.id AND x.status<>'published') AS subjects,
      (SELECT COUNT(DISTINCT x.subject_id) FROM exams x JOIN marks m ON m.exam_id=x.id
        WHERE x.event_id=? AND x.class_id=c.id AND x.status<>'published') AS subjects_done,
      (SELECT COUNT(*) FROM exams x WHERE x.event_id=? AND x.class_id=c.id
        AND x.status<>'published' AND x.entry_status <> 'approved') AS not_approved
     FROM classes c WHERE c.id IN (SELECT DISTINCT class_id FROM exams WHERE event_id=? AND status<>'published')
       AND (NOT ? OR EXISTS (SELECT 1 FROM students eligible WHERE eligible.class_id=c.id AND eligible.session_id=? AND ${model ? modelTestPromotionExists('eligible') : '1=1'}))`,
    model
      ? [event.session_id, event.session_id, Number(event.year) - 1,
         event.session_id, event.session_id, Number(event.year) - 1,
         eventId, eventId, eventId, eventId, eventId, true, event.session_id, event.session_id, Number(event.year) - 1]
      : [eventId, eventId, eventId, eventId, eventId, false, 0]);
  for (const c of classes) {
    const gaps = [];
    if (Number(c.subjects_done || 0) < Number(c.subjects || 0)) {
      gaps.push(`${Number(c.subjects) - Number(c.subjects_done)} subject-এর marks বাকি`);
    }
    if (Number(c.students_done || 0) < Number(c.students || 0)) {
      gaps.push(`${Number(c.students) - Number(c.students_done)} জন student-এর marks বাকি`);
    }
    if (Number(c.not_approved || 0) > 0) {
      gaps.push(`${Number(c.not_approved)} subject এখনো class-teacher approved নয়`);
    }
    if (gaps.length) missing.push({ class_id: c.id, class_name: `${c.name} (${c.section})`, gaps });
  }
  return missing;
}

function promotionYearForClass(className, eventKind) {
  const isClass10 = /class\s*10/i.test(String(className || ''));
  if (isClass10) return eventKind === 'test';
  return /class\s*[6-9]\b/i.test(String(className || '')) && eventKind === 'annual';
}

async function prepareEventPromotionReview(event, adminId) {
  if (!event || !['annual', 'test'].includes(String(event.exam_kind)) || !event.year) return null;
  const targetYear = Number(event.year) + 1;
  let [[targetSession]] = await pool.query('SELECT id FROM sessions WHERE name=?', [String(targetYear)]);
  if (!targetSession) {
    await pool.query('INSERT INTO sessions (name,is_active) VALUES (?,0) ON CONFLICT (name) DO NOTHING', [String(targetYear)]);
    [[targetSession]] = await pool.query('SELECT id FROM sessions WHERE name=?', [String(targetYear)]);
  }
  if (!targetSession) return null;

  const [classes] = await pool.query(
    `SELECT DISTINCT c.id,c.name,c.section,c.group_name FROM exams x
      JOIN classes c ON c.id=x.class_id WHERE x.event_id=? ORDER BY c.name,c.section,c.id`, [event.id]);
  let autoApproved = 0;
  for (const cls of classes) {
    if (!promotionYearForClass(cls.name, event.exam_kind)) continue;
    const [graceSubjects] = await pool.query(
      `SELECT sub.name FROM event_promotion_grace g JOIN subjects sub ON sub.id=g.subject_id
        WHERE g.event_id=? AND g.class_id=?`, [event.id, cls.id]);
    const selectedNames = graceSubjects.map(subject => subject.name);
    let destination;
    if (/class\s*8\b/i.test(cls.name)) destination = await promotionEngine.getPendingGroupClass9();
    else destination = await promotionEngine.promotionDestination(pool, cls);
    const [students] = await pool.query(
      `SELECT id,name,roll FROM students WHERE class_id=? AND (status IS NULL OR status IN ('active','irregular')) ORDER BY roll`, [cls.id]);
    for (const student of students) {
      const result = await computeResult(student.id, event.id);
      const outcome = result
        ? decidePromotionByGrace({
          families: result.families,
          selectedSubjectNames: selectedNames,
          resultStatus: result.result_status,
        })
        : { status: 'pending_results', decision: null, eligible: false, failed: [], graceFailed: [], ungracedFailed: [], autoGrace: false };
      const note = outcome.autoGrace
        ? `Auto-approved at publish; grace subjects: ${outcome.graceFailed.join(', ')}`
        : outcome.status === 'not_eligible'
          ? `Un-graced mandatory failures: ${outcome.ungracedFailed.join(', ')}`
          : null;
      await pool.query(
        `INSERT INTO student_promotion_status
          (student_id,from_class_id,target_class_id,target_session_id,source_event_id,status,decision,eligible,
           final_gpa,failed_subjects,mandatory_failed_subjects,grace_used,admin_note,approved_by,approved_at,created_at,updated_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,CASE WHEN ? THEN NOW() ELSE NULL END,NOW(),NOW())
         ON CONFLICT (student_id,target_session_id) DO UPDATE SET
          from_class_id=EXCLUDED.from_class_id,target_class_id=EXCLUDED.target_class_id,source_event_id=EXCLUDED.source_event_id,
          status=CASE WHEN student_promotion_status.status IN ('promoted','retained') THEN student_promotion_status.status ELSE EXCLUDED.status END,
          decision=CASE WHEN student_promotion_status.status IN ('promoted','retained') THEN student_promotion_status.decision ELSE EXCLUDED.decision END,
          eligible=EXCLUDED.eligible,final_gpa=EXCLUDED.final_gpa,failed_subjects=EXCLUDED.failed_subjects,
          mandatory_failed_subjects=EXCLUDED.mandatory_failed_subjects,grace_used=EXCLUDED.grace_used,
          admin_note=EXCLUDED.admin_note,approved_by=COALESCE(student_promotion_status.approved_by,EXCLUDED.approved_by),
          approved_at=COALESCE(student_promotion_status.approved_at,EXCLUDED.approved_at),updated_at=NOW()`,
        [student.id, cls.id, destination?.id || null, targetSession.id, event.id, outcome.status, outcome.decision,
          outcome.eligible, result?.final_gpa ?? null, outcome.failed, outcome.ungracedFailed,
          outcome.autoGrace ? 1 : 0, note, outcome.autoGrace ? adminId : null, outcome.autoGrace]);
      if (outcome.autoGrace) {
        autoApproved++;
        await pool.query(
          `INSERT INTO promotion_audit_log (student_id,action,to_status,from_class_id,to_class_id,target_session_id,admin_id,reason,metadata,created_at)
           VALUES (?,'publish_grace_auto_approved','approved',?,?,?,?,?,?,NOW())`,
          [student.id, cls.id, destination?.id || null, targetSession.id, adminId, note,
            JSON.stringify({ event_id: event.id, grace_subjects: outcome.graceFailed })]);
      }
    }
  }
  return { target_session_id: Number(targetSession.id), auto_approved: autoApproved };
}

router.post('/events/:id/publish', async (req, res) => {
  const notify = req.body ? !!req.body.notify_guardians : false;
  try {
    const [[ev]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [req.params.id]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    const graceSelections = Array.isArray(req.body?.grace_subjects) ? req.body.grace_subjects : [];
    if (!Number(ev.is_published) && ['annual', 'test'].includes(String(ev.exam_kind))) {
      const [allowed] = await pool.query(
        `SELECT DISTINCT x.class_id,sub.id AS subject_id FROM exams x
          JOIN subjects sub ON sub.id=x.subject_id
         WHERE x.event_id=? AND COALESCE(sub.is_optional,FALSE)=FALSE`, [ev.id]);
      const allowedPairs = new Set(allowed.map(row => `${Number(row.class_id)}:${Number(row.subject_id)}`));
      for (const row of graceSelections) {
        const classId = Number(row.class_id);
        for (const subjectId of (Array.isArray(row.subject_ids) ? row.subject_ids : []).map(Number)) {
          if (!Number.isInteger(classId) || !Number.isInteger(subjectId) ||
              !allowedPairs.has(`${classId}:${subjectId}`)) {
            return res.status(400).json({ error: 'শুধু এই পরীক্ষার সংশ্লিষ্ট class-এর mandatory subject grace করা যাবে।' });
          }
        }
      }
    }
    if (Number(ev.is_published) === 1) {
      const nextYear = await openNextSessionAfterTest(ev, req.user.id);
      if (isCanon(ev.exam_kind)) await syncCurrentAcademicSession();
      const promotionReview = await prepareEventPromotionReview(ev, req.user.id).catch(err => {
        console.error('grace promotion review failed:', err.message); return null;
      });
      return res.json({ ok: true, already_published: true, next_year_session: nextYear, promotion_review: promotionReview });
    }
    const [[activeScope]] = await pool.query(
      `SELECT COUNT(*) AS n FROM exams WHERE event_id=? AND entry_open=1 AND status<>'published'`, [req.params.id]);
    if (!Number(activeScope && activeScope.n)) {
      return res.status(409).json({ error: 'ফল প্রকাশের জন্য অন্তত একটি active subject খুলতে হবে।' });
    }
    const missing = await eventPublishGate(req.params.id);
    if (missing.length) {
      return res.status(422).json({
        error: 'সব subject/student-এর marks entry শেষ না হওয়া পর্যন্ত publish করা যাবে না।',
        missing,
      });
    }
    const publishConn = await pool.getConnection();
    try {
      await publishConn.beginTransaction();
      const [[lockedEvent]] = await publishConn.query(
        'SELECT is_published FROM exam_events WHERE id=? FOR UPDATE', [req.params.id]);
      if (!lockedEvent) {
        await publishConn.rollback();
        return res.status(404).json({ error: 'Event not found' });
      }
      if (Number(lockedEvent.is_published) === 1) {
        await publishConn.rollback();
        const nextYear = await openNextSessionAfterTest(ev, req.user.id);
        if (isCanon(ev.exam_kind)) await syncCurrentAcademicSession();
        const promotionReview = await prepareEventPromotionReview(ev, req.user.id).catch(err => {
          console.error('grace promotion review failed:', err.message); return null;
        });
        return res.json({ ok: true, already_published: true, next_year_session: nextYear, promotion_review: promotionReview });
      }
      await publishConn.query(
        `UPDATE exam_events SET is_published=1, published_at=NOW(), notify_guardians=? WHERE id=?`,
        [notify ? 1 : 0, req.params.id]);
      await publishConn.query(
        `UPDATE exams SET status='published', entry_open=0 WHERE event_id=? AND entry_open=1 AND status<>'published'`,
        [req.params.id]);
      if (['annual', 'test'].includes(String(ev.exam_kind))) {
        await publishConn.query('DELETE FROM event_promotion_grace WHERE event_id=?', [ev.id]);
        for (const row of graceSelections) {
          const classId = Number(row.class_id);
          for (const subjectId of [...new Set((Array.isArray(row.subject_ids) ? row.subject_ids : []).map(Number))]) {
            await publishConn.query(
              `INSERT INTO event_promotion_grace (event_id,class_id,subject_id,granted_by) VALUES (?,?,?,?)
               ON CONFLICT (event_id,class_id,subject_id) DO NOTHING`, [ev.id, classId, subjectId, req.user.id]);
          }
        }
      }
      await publishConn.commit();
    } catch (publishErr) {
      try { await publishConn.rollback(); } catch (_) {}
      throw publishErr;
    } finally {
      publishConn.release();
    }
    // Auto result generation
    let autoComputed = [];
    try {
      const [clsRows] = await pool.query("SELECT DISTINCT class_id FROM exams WHERE event_id=? AND status='published'", [req.params.id]);
      for (const c of clsRows) {
        const r = await computeEventResults(req.params.id, c.class_id);
        autoComputed.push({ class_id: c.class_id, ...r });
      }
    } catch (e) { console.error('auto-compute on publish failed:', e.message); }
    let promotionReview = null;
    try { promotionReview = await prepareEventPromotionReview(ev, req.user.id); }
    catch (e) { console.error('grace promotion review failed:', e.message); }
    let notified = 0, push = null, already_notified = false;
    if (notify) {
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
          await pool.query(
            `INSERT INTO notifications (student_id, title, body, type, target_type, related_id, created_by, dedup_key)
             VALUES ${vals} ON CONFLICT (dedup_key) DO NOTHING`, params);
          const [[cnt]] = await pool.query(
            `SELECT COUNT(*) AS c FROM notifications WHERE dedup_key LIKE ?`, [`result:${ev.id}:%`]);
          notified = cnt ? Number(cnt.c) : studentIds.length;
        }
        await pool.query('UPDATE exam_events SET notified_at=NOW() WHERE id=? AND notify_guardians=1', [req.params.id]);
      }
    }
    // Only publishing the Class 10 Test opens the next academic session.
    let nextYear = null;
    const autoPromotions = [];
    if (ev.exam_kind === 'test' && ev.year) {
      nextYear = await openNextSessionAfterTest(ev, req.user.id);
    }
    if (isCanon(ev.exam_kind)) await syncCurrentAcademicSession();
    // Opening the next session does not decide student promotion. Admin
    // reviews and executes approved promotion decisions separately.
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [req.user.id, 'event_publish', `Published event ${ev.name} (notify=${notify ? 1 : 0}, notified=${notified}, already=${already_notified ? 1 : 0})`]).catch(() => {});
    res.json({ ok: true, notified, already_notified, push, next_year_session: nextYear, auto_computed: autoComputed, auto_promotions: autoPromotions, promotion_review: promotionReview });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/events/:id/unpublish', async (req, res) => {
  try {
    const [[ev]] = await pool.query('SELECT id FROM exam_events WHERE id=?', [req.params.id]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    const [[graceMoves]] = await pool.query(
      `SELECT COUNT(*) AS count FROM student_promotion_status
        WHERE source_event_id=? AND status='promoted' AND grace_used=1`, [req.params.id]);
    if (Number(graceMoves?.count || 0) > 0) {
      return res.status(409).json({ error: 'Grace promotion সম্পন্ন হয়েছে; আগে promotion reversal করুন, তারপর ফল unpublish করা যাবে।' });
    }
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
    const [[scope]] = await pool.query('SELECT exam_kind, session_id, year FROM exam_events WHERE id=?', [req.params.id]);
    const model = scope && scope.exam_kind === 'special_model_test';
    const studentScope = model ? ` AND s.session_id=? AND ${modelTestPromotionExists('s')}` : '';
    const studentScopeParams = model ? [scope.session_id, scope.session_id, Number(scope.year) - 1] : [];
    const [classes] = await pool.query(
      `SELECT c.id AS class_id, c.name AS class_name, c.section, c.group_name,
        (SELECT COUNT(*) FROM students s WHERE s.class_id=c.id${studentScope}) AS student_count,
        (SELECT COUNT(DISTINCT m.student_id) FROM marks m JOIN exams x ON x.id=m.exam_id
          JOIN students s ON s.id=m.student_id${model ? ` AND s.session_id=? AND ${modelTestPromotionExists('s')}` : ''}
          WHERE x.event_id=? AND x.class_id=c.id AND x.entry_open=1 AND x.status<>'published') AS students_with_marks,
        (SELECT COUNT(*) FROM marks m JOIN exams x ON x.id=m.exam_id WHERE x.event_id=? AND x.class_id=c.id AND x.entry_open=1 AND x.status<>'published') AS marks_count,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id=? AND x.class_id=c.id AND x.entry_open=1 AND x.status<>'published') AS subject_count,
        (SELECT COUNT(DISTINCT x.subject_id) FROM exams x JOIN marks m ON m.exam_id=x.id WHERE x.event_id=? AND x.class_id=c.id AND x.entry_open=1 AND x.status<>'published') AS subjects_with_marks,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id=? AND x.class_id=c.id AND x.entry_open=1 AND x.status<>'published') AS assigned_subjects,
        (SELECT COUNT(*) FROM subjects sub WHERE sub.class_id=c.id
           AND NOT EXISTS (SELECT 1 FROM exams x JOIN marks m ON m.exam_id=x.id
                           WHERE x.event_id=? AND x.class_id=c.id AND x.subject_id=sub.id AND x.entry_open=1 AND x.status<>'published')) AS pending_subjects
       FROM classes c
       WHERE EXISTS (SELECT 1 FROM exams ex WHERE ex.event_id=? AND ex.class_id=c.id AND ex.entry_open=1 AND ex.status<>'published')
         AND (NOT ? OR EXISTS (SELECT 1 FROM students eligible WHERE eligible.class_id=c.id AND eligible.session_id=? AND ${model ? modelTestPromotionExists('eligible') : '1=1'}))
       ORDER BY c.name, c.section, c.group_name`,
      [
        ...studentScopeParams,
        ...(model ? [scope.session_id, scope.session_id, Number(scope.year) - 1] : []), req.params.id,
        req.params.id, req.params.id, req.params.id, req.params.id, req.params.id,
        req.params.id, model, model ? scope.session_id : 0,
        ...(model ? [scope.session_id, Number(scope.year) - 1] : []),
      ]
    );
    const [subjects] = await pool.query(
      `SELECT x.class_id, x.id AS exam_id, sub.name AS subject_name, x.status,
        (SELECT COUNT(*) FROM marks m JOIN students s ON s.id=m.student_id${model ? ` AND s.session_id=? AND ${modelTestPromotionExists('s')}` : ''} WHERE m.exam_id=x.id) AS entered_count,
        (SELECT COUNT(*) FROM students s WHERE s.class_id=x.class_id${studentScope}) AS student_count
       FROM exams x JOIN subjects sub ON sub.id=x.subject_id
       WHERE x.event_id=? AND x.entry_open=1 AND x.status<>'published' ORDER BY x.class_id, sub.name`,
      [...(model ? [scope.session_id, scope.session_id, Number(scope.year) - 1] : []), ...studentScopeParams, req.params.id]
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
  const [[eventScope]] = await pool.query('SELECT exam_kind, session_id, year FROM exam_events WHERE id=?', [event_id]);
  const [[selectedClass]] = await pool.query('SELECT id, name, group_name FROM classes WHERE id=?', [class_id]);
  if (!selectedClass) throw Object.assign(new Error('Class not found'), { status: 404 });
  const modelSession = eventScope && eventScope.exam_kind === 'special_model_test';
  // A class row is one section. Calculate merit across every section of the
  // same class/group that participates in this event, while preserving each
  // student's within-section position separately.
  const [students] = await pool.query(
    `SELECT s.id, s.section, c.id AS class_id, c.group_name, c.section AS class_section
       FROM students s JOIN classes c ON c.id = s.class_id
      WHERE c.name=? AND COALESCE(c.group_name,'')=COALESCE(?,'')
        AND EXISTS (SELECT 1 FROM exams event_exam WHERE event_exam.event_id=? AND event_exam.class_id=c.id)
        ${modelSession ? `AND s.session_id=? AND ${modelTestPromotionExists('s')}` : ''}`,
    modelSession
      ? [selectedClass.name, selectedClass.group_name, event_id, eventScope.session_id, eventScope.session_id, Number(eventScope.year) - 1]
      : [selectedClass.name, selectedClass.group_name, event_id]);
  let computed = 0, withMarks = 0;
  const scored = [];
  for (const s of students) {
    const r = await computeResult(s.id, event_id);
    if (!r) continue;
    withMarks++;
    await pool.query(
      `INSERT INTO results (student_id, exam_id, total_gpa_without_4th, gpa_4th_bonus, final_gpa,
                            result_status, total_marks_obtained, total_marks_full, pass_all)
       VALUES (?,?,?,?,?,?,?,?,?)
       ON CONFLICT (student_id, exam_id) DO UPDATE SET total_gpa_without_4th=EXCLUDED.total_gpa_without_4th,
         gpa_4th_bonus=EXCLUDED.gpa_4th_bonus, final_gpa=EXCLUDED.final_gpa,
         result_status=EXCLUDED.result_status, total_marks_obtained=EXCLUDED.total_marks_obtained,
         total_marks_full=EXCLUDED.total_marks_full, pass_all=EXCLUDED.pass_all, computed_at=NOW()`,
      [s.id, event_id, r.total_gpa_without_4th, r.gpa_4th_bonus, r.final_gpa, r.result_status,
       Number(r.total_marks || 0), Number(r.total_full || 0), r.result_status === 'PASSED' ? 1 : 0]
    );
    computed++;
    scored.push({
      id: s.id, class_id: s.class_id, sec: String(s.class_section || s.section || ''),
      gpa: Number(r.final_gpa), bonus: Number(r.gpa_4th_bonus || 0),
      total: Number(r.total_marks || 0), fourth: Number(r.fourth_score || 0),
      passed: r.result_status === 'PASSED' ? 1 : 0,
    });
  }
  // Materialize positions (Q9): combined across all sections, plus section-local.
  scored.sort((a, b) =>
    resultGradeRank(b.gpa) - resultGradeRank(a.gpa) ||
    (b.total - a.total) ||
    crypto.createHash('sha256').update(`merit:${event_id}:${a.id}`).digest('hex')
      .localeCompare(crypto.createHash('sha256').update(`merit:${event_id}:${b.id}`).digest('hex')));
  const secCounters = {};
  const sectionSizes = {};
  for (const row of scored) sectionSizes[row.sec] = (sectionSizes[row.sec] || 0) + 1;
  for (let i = 0; i < scored.length; i++) {
    const row = scored[i];
    const combined = i + 1;
    secCounters[row.sec] = (secCounters[row.sec] || 0) + 1;
    await pool.query(
      `UPDATE results SET combined_position=?, section_position=?, combined_size=?, section_size=?
        WHERE student_id=? AND exam_id=?`,
      [combined, secCounters[row.sec], scored.length, sectionSizes[row.sec], row.id, event_id]);
  }
  return { ok: true, students: students.length, computed, with_marks: withMarks };
}

router.get('/tabulation', async (req, res) => {
  const { event_id, class_id } = req.query;
  if (!event_id || !class_id) return res.status(400).json({ error: 'event_id and class_id required' });
  try {
    const [[scope]] = await pool.query('SELECT exam_kind, session_id, year FROM exam_events WHERE id=?', [event_id]);
    const modelSession = scope && scope.exam_kind === 'special_model_test';
    const [[selectedClass]] = await pool.query('SELECT name, group_name FROM classes WHERE id=?', [class_id]);
    const [[sectionCount]] = await pool.query(
      `SELECT COUNT(*) AS c FROM results r JOIN students s ON s.id=r.student_id
        WHERE r.exam_id=? AND s.class_id=?`, [event_id, class_id]);
    const [[combinedCount]] = await pool.query(
      `SELECT COUNT(*) AS c FROM results r JOIN students s ON s.id=r.student_id JOIN classes c ON c.id=s.class_id
        WHERE r.exam_id=? AND c.name=? AND COALESCE(c.group_name,'')=COALESCE(?,'')`,
      [event_id, selectedClass?.name, selectedClass?.group_name]);
    const [students] = await pool.query(
      `SELECT s.id, s.name, s.roll, s.student_code, s.birth_cert_no, s.father_name, s.mother_name, s.dob, r.final_gpa, r.total_gpa_without_4th,
              r.gpa_4th_bonus, r.result_status, r.section_position, r.combined_position,
              r.section_size, r.combined_size
       FROM students s
       LEFT JOIN results r ON r.student_id = s.id AND r.exam_id = ?
        WHERE s.class_id = ?${modelSession ? ` AND s.session_id=? AND ${modelTestPromotionExists('s')}` : ''} ORDER BY s.roll`,
      modelSession ? [event_id, class_id, scope.session_id, scope.session_id, Number(scope.year) - 1] : [event_id, class_id]
    );
    const famSet = new Set();
    const rows = [];
    for (const stu of students) {
      const r = await computeResult(stu.id, event_id);
      const famMap = {};
      if (r) {
        r.families.forEach(f => { famSet.add(f.subject); famMap[f.subject] = f; });
      }
      const activities = await loadStudentActivities(pool, {
        studentId: stu.id, classId, eventId, year: scope?.year, to: scope?.result_date || dhakaToday(),
      });
      rows.push({
        ...stu,
        activities, activity_period: { from: activities.from, to: activities.to },
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
    // Merit ranking: result grade, then total marks. Equal grade+marks get a
    // stable random-looking order keyed by event/student, never by roll/name.
    rows.forEach(row => { row.position = null; });
    const sortedForRank = [...rows].filter(r => r.final_gpa != null && r.result_status === 'PASSED')
      .sort((a, b) =>
        resultGradeRank(b.final_gpa) - resultGradeRank(a.final_gpa) ||
        (Number(b.total_marks || 0) - Number(a.total_marks || 0)) ||
        crypto.createHash('sha256').update(`merit:${event_id}:${a.id}`).digest('hex')
          .localeCompare(crypto.createHash('sha256').update(`merit:${event_id}:${b.id}`).digest('hex')));
    sortedForRank.forEach((r, i) => {
      r.position = r.section_position ?? (i + 1);
      r.section_of = Number(r.section_size || sectionCount?.c || 0);
      r.combined_of = Number(r.combined_size || combinedCount?.c || 0);
    });
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
      const dualPosition = await resultPositionSnapshot(st.id, classId, eventId);
      doc.addPage();
      let y = 50;
      const schoolName = settings.school_name || settings.school || settings.school_name_en || 'School';
      const schoolAddr = settings.school_address || settings.address || '';
      doc.font('Helvetica-Bold').fontSize(15).fillColor('#222222').text(String(schoolName), 40, y, { align: 'center', width: CW });
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
      if (dualPosition) {
        doc.font('Helvetica').fontSize(9.5).fillColor('#111111')
          .text(`মেধা স্থান: শাখা ${dualPosition.section || '—'}/${dualPosition.section_of} • সব শাখা ${dualPosition.combined || '—'}/${dualPosition.combined_of}`, 40, y, { width: CW });
        y += 15;
      }
      y += 10;
      if (!result) {
        doc.font('Helvetica').fontSize(10).fillColor('#888').text('No result data', 40, y);
        continue;
      }
      doc.font('Helvetica-Bold').fontSize(9.5).fillColor('#444444').text(
        `GPA (without 4th): ${result.total_gpa_without_4th.toFixed(2)}    4th bonus: ${result.gpa_4th_bonus.toFixed(2)}    Final GPA: ${result.final_gpa.toFixed(2)}`,
        40, y, { width: CW });
      y += 16;
      doc.fillColor(result.result_status === 'PASSED' ? '#1e7d32' : '#c62828').font('Helvetica-Bold').fontSize(11)
        .text('Result: ' + result.result_status, 40, y);
      y += 20;
      doc.fillColor('#111111');
      const cols = [{ w: 235, t: 'Subject' }, { w: 70, t: 'Total' }, { w: 100, t: 'Grade' }, { w: 80, t: 'GPA' }];
      const rowH = 18, tableX = 40;
      doc.fillColor('#444444').rect(tableX, y, CW, rowH).fill();
      doc.fillColor('#ffffff').font('Helvetica-Bold').fontSize(9);
      let cx = tableX;
      cols.forEach(c => { doc.text(c.t, cx + 5, y + 5, { width: c.w - 10, align: cx === tableX ? 'left' : 'center' }); cx += c.w; });
      y += rowH;
      doc.fillColor('#111111');
      result.families.forEach((f, i) => {
        if (y > doc.page.height - 70) { doc.addPage(); y = 40; }
        if (i % 2 === 0) { doc.fillColor('#f1f1f1').rect(tableX, y, CW, rowH).fill(); }
        doc.fillColor('#111111').font('Helvetica').fontSize(9);
        const display = (f.is_optional ? '(4th) ' : '') + f.subject;
        cx = tableX;
        doc.text(display, cx + 5, y + 5, { width: cols[0].w - 10 }); cx += cols[0].w;
        doc.text(f.absent ? 'Absent' : `${f.total}/${f.full}`, cx + 5, y + 5, { width: cols[1].w - 10, align: 'center' }); cx += cols[1].w;
        doc.text(f.absent ? '—' : f.letter_grade, cx + 5, y + 5, { width: cols[2].w - 10, align: 'center' }); cx += cols[2].w;
        doc.text(f.absent ? '—' : f.grade_point.toFixed(1), cx + 5, y + 5, { width: cols[3].w - 10, align: 'center' });
        y += rowH;
      });
      doc.strokeColor('#444444').lineWidth(1).rect(tableX, y - rowH * result.families.length, CW, rowH * result.families.length).stroke();
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
    const dualPosition = await resultPositionSnapshot(student.id, student.class_id, Number(req.params.eventId));
    const activities = await loadStudentActivities(pool, {
      studentId: student.id, classId: student.class_id, eventId: Number(req.params.eventId),
      year: event?.year, to: event?.result_date || event?.exam_date || dhakaToday(),
    });
    const [att] = await pool.query(
      `SELECT status, COUNT(*) AS c FROM attendance WHERE student_id=? GROUP BY status`,
      [student.id]);
    const [settingsRows] = await pool.query('SELECT setting_key, setting_value FROM app_settings');
    const settings = {};
    settingsRows.forEach(s => { settings[s.setting_key] = s.setting_value; });
    res.json({ student, event, result, remarks: saved ? saved.teacher_remarks : null, settings,
      signatures: await getClassSignatories(student.class_id),
      serial_no: saved ? 'MS-' + req.params.eventId + '-' + String(saved.id).padStart(4, '0') : '—',
      class_highest_gpa: hi && hi.gpa != null ? Number(hi.gpa) : null,
      dual_position: dualPosition,
      attendance: att, activities, activity_period: { from: activities.from, to: activities.to } });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// Multi-page PDF marksheet: page 1 = transcript summary incl. 4th-subject bonus GPA;
    // later pages = per-subject breakdown, attendance, subject comments and complaints/remarks.
    // Design matches reference project: frame borders, watermark logo, Bengali/English headers,
    // grading scale table, signature blocks.
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
          'SELECT teacher_remarks, section_position, combined_position FROM results WHERE student_id=? AND exam_id=?',
          [student.id, req.params.eventId]
        );
        const dualPosition = await resultPositionSnapshot(student.id, student.class_id, Number(req.params.eventId));
        const [settingsRows] = await pool.query('SELECT setting_key, setting_value FROM app_settings');
        const settings = {};
        settingsRows.forEach(s => { settings[s.setting_key] = s.setting_value; });
        const signatures = await getClassSignatories(student.class_id);

        const [attRows] = await pool.query(
          'SELECT status, COUNT(*) AS cnt FROM attendance WHERE student_id=? GROUP BY status', [student.id]
        );

        const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename=marksheet_${student.student_code}_event${req.params.eventId}.pdf`);
        doc.pipe(res);

        const FONT = registerBanglaFont(doc);
        const CW = doc.page.width - 80;
        const MARGIN = 40;
        let y = MARGIN;

        // Draw frame and watermark on first page
        drawFrame(doc, MARGIN);
        const logoPath = await loadSchoolLogo(settings.school_logo_path);
        drawWatermark(doc, logoPath, doc.page.width, doc.page.height);
        drawRosette(doc, doc.page.width / 2, doc.page.height / 2);

        const pageGap = () => {
          if (y > doc.page.height - 80) {
            doc.addPage();
            y = MARGIN;
            drawFrame(doc, MARGIN);
            drawWatermark(doc, logoPath, doc.page.width, doc.page.height);
            return true;
          }
          return false;
        };

        // ======================== HEADER ========================
        const schoolNameEn = settings.school_name || settings.school || 'School';
        const schoolNameBn = settings.school_name_bn || 'নাজিরহাট কলেজিয়েট উচ্চ বিদ্যালয়';
        const schoolAddr = settings.school_address || settings.address || '';
        
        doc.font(FONT).fontSize(14).fillColor('#111111').text(schoolNameEn, MARGIN, y, { align: 'center', width: CW });
        y += 18;
        doc.font(FONT).fontSize(13).fillColor('#111111').text(schoolNameBn, MARGIN, y, { align: 'center', width: CW });
        y += 16;
        if (schoolAddr) {
          doc.font(FONT).fontSize(9).fillColor('#555555').text(schoolAddr, MARGIN, y, { align: 'center', width: CW });
          y += 12;
        }
        if (logoPath) { try { doc.image(logoPath, doc.page.width / 2 - 23, y, { fit: [46, 46] }); y += 48; } catch (_) {} }
        
        doc.font(FONT).fontSize(11).fillColor('#111111').text('Academic Transcript — ' + String(event.name), MARGIN, y, { align: 'center', width: CW });
        y += 22;

        doc.font(FONT).fontSize(10).fillColor('#444444').text('Student Information', MARGIN, y);
        y += 14;
        
        // Student info in a grid (matching reference)
        const infoLines = [
          ['Name of Student', student.name],
          ["Father's Name", student.father_name || '—'],
          ['Registration No', String(student.student_code)],
          ["Mother's Name", student.mother_name || '—'],
          ['Roll No', String(student.roll)],
          ['Group', student.group_name || student.section || '—'],
          ['Academic Session', settings.exam_term_name || '—'],
          ['Date of Birth', student.dob ? String(student.dob).slice(0, 10) : '—'],
          ['Class', `${student.class_name}${student.group_name ? ' (' + student.group_name + ')' : ' (' + student.section + ')'}`],
          ['Religion', student.religion || '—'],
          ['Section Merit', dualPosition ? `${dualPosition.section || '—'} / ${dualPosition.section_of}` : '—'],
          ['All Sections Merit', dualPosition ? `${dualPosition.combined || '—'} / ${dualPosition.combined_of}` : '—']
        ];

        const col1W = 140, col2W = CW - col1W - 10;
        infoLines.forEach(([k, v], idx) => {
          const x = idx % 2 === 0 ? MARGIN : MARGIN + col1W + 20;
          const w = idx % 2 === 0 ? col1W : col2W;
          doc.font(FONT).fontSize(9).fillColor('#555555').text(k + ':', x, y, { width: w });
          doc.font(FONT).fontSize(9).fillColor('#111111').text(String(v), x + 120, y, { width: w - 120 });
          if (idx % 2 === 1) y += 14;
        });
        if (infoLines.length % 2 === 1) y += 14;
        y += 10;

        // ======================== GRADING SCALE ========================
        const gradeScale = [
          { grade: 'A+', range: '80 – 100', gp: '5.0' },
          { grade: 'A',  range: '70 – 79',  gp: '4.0' },
          { grade: 'A-', range: '60 – 69',  gp: '3.5' },
          { grade: 'B',  range: '50 – 59',  gp: '3.0' },
          { grade: 'C',  range: '40 – 49',  gp: '2.0' },
          { grade: 'D',  range: '33 – 39',  gp: '1.0' },
          { grade: 'F',  range: '00 – 32',  gp: '0.0' }
        ];
        
        const gsW = 180;
        const gsX = MARGIN + CW - gsW;
        doc.font(FONT).fontSize(8).fillColor('#444444').text('Grading Scale', gsX, y, { width: gsW, align: 'center' });
        let gy = y + 12;
        doc.font(FONT).fontSize(7).fillColor('#444444');
        doc.rect(gsX, gy, 50, 14).fill();
        doc.rect(gsX + 50, gy, 65, 14).fill();
        doc.rect(gsX + 115, gy, 65, 14).fill();
        doc.fillColor('#fff').font(FONT).fontSize(7).font('Helvetica-Bold');
        doc.text('Letter Grade', gsX + 2, gy + 2, { width: 46, align: 'center' });
        doc.text('Class Interval', gsX + 52, gy + 2, { width: 61, align: 'center' });
        doc.text('Grade Point', gsX + 117, gy + 2, { width: 61, align: 'center' });
        gy += 14;
        doc.fillColor('#111111').font(FONT).fontSize(7);
        gradeScale.forEach((g, i) => {
          if (i % 2 === 0) doc.fillColor('#f1f1f1').rect(gsX, gy, gsW, 14).fill();
          doc.font(FONT).fontSize(7).fillColor('#111111');
          doc.text(g.grade, gsX + 2, gy + 2, { width: 46, align: 'center' });
          doc.text(g.range, gsX + 52, gy + 2, { width: 61, align: 'center' });
          doc.text(g.gp, gsX + 117, gy + 2, { width: 61, align: 'center' });
          gy += 14;
        });
        doc.strokeColor('#444444').lineWidth(0.5).rect(gsX, y, gsW, gy - y).stroke();
        
        y += 8;

        // ======================== MARKS TABLE ========================
        const mCols = [
          { w: 40, t: 'Sl.', key: 'sl', align: 'center' },
          { w: 180, t: 'Name of Subjects', key: 'subject', align: 'left' },
          { w: 70, t: 'Marks', key: 'marks', align: 'center' },
          { w: 80, t: 'Letter Grade', key: 'grade', align: 'center' },
          { w: 70, t: 'Grade Point', key: 'gp', align: 'center' }
        ];
        const mRowH = 18;
        const mTableX = MARGIN;

        // Header
        doc.fillColor('#444444').rect(mTableX, y, CW, mRowH).fill();
        doc.fillColor('#fff').font(FONT).fontSize(8).font('Helvetica-Bold');
        let mcx = mTableX;
        mCols.forEach(c => {
          doc.text(c.t, mcx + 3, y + 4, { width: c.w - 6, align: c.align });
          mcx += c.w;
        });
        y += mRowH;
        doc.fillColor('#111111').font(FONT).fontSize(8);

        // Regular subjects
        let sl = 1;
        result.families.forEach((f, i) => {
          if (!f.is_optional) {
            pageGap();
            if (i % 2 === 0) doc.fillColor('#f1f1f1').rect(mTableX, y, CW, mRowH).fill();
            mcx = mTableX;
            const marksText = f.absent ? 'Absent' : `${f.total}/${f.full}`;
            const rowData = [sl++, f.subject, marksText, f.absent ? '—' : f.letter_grade, f.absent ? '—' : f.grade_point.toFixed(1)];
            rowData.forEach((v, ci) => {
              doc.text(String(v), mcx + 3, y + 4, { width: mCols[ci].w - 6, align: mCols[ci].align });
              mcx += mCols[ci].w;
            });
            y += mRowH;
          }
        });

        // 4th subject (optional)
        const fourthSubs = result.families.filter(f => f.is_optional);
        if (fourthSubs.length) {
          pageGap();
          y += 6;
          doc.font(FONT).fontSize(8).fillColor('#444444').text('Fourth Subject (Optional)', MARGIN, y);
          y += 12;
          doc.fillColor('#444444').rect(mTableX, y, CW, mRowH).fill();
          doc.fillColor('#fff').font(FONT).fontSize(8).font('Helvetica-Bold');
          mcx = mTableX;
          mCols.forEach(c => {
            doc.text(c.t, mcx + 3, y + 4, { width: c.w - 6, align: c.align });
            mcx += c.w;
          });
          y += mRowH;
          doc.fillColor('#111111').font(FONT).fontSize(8);
          fourthSubs.forEach((f, i) => {
            pageGap();
            if (i % 2 === 0) doc.fillColor('#f1f1f1').rect(mTableX, y, CW, mRowH).fill();
            mcx = mTableX;
            const marksText = f.absent ? 'Absent' : `${f.total}/${f.full}`;
            const rowData = [sl++, f.subject, marksText, f.absent ? '—' : f.letter_grade, f.absent ? '—' : f.grade_point.toFixed(1)];
            rowData.forEach((v, ci) => {
              doc.text(String(v), mcx + 3, y + 4, { width: mCols[ci].w - 6, align: mCols[ci].align });
              mcx += mCols[ci].w;
            });
            y += mRowH;
          });
        }

        doc.strokeColor('#444444').lineWidth(1).rect(mTableX, y - mRowH * (sl - 1), CW, mRowH * (sl - 1)).stroke();
        y += 12;

        // ======================== GPA SUMMARY ========================
        doc.font(FONT).fontSize(9).fillColor('#444444').text(
          `GPA (without 4th subject): ${result.total_gpa_without_4th.toFixed(2)}    4th-subject bonus: ${result.gpa_4th_bonus.toFixed(2)}    Final GPA: ${result.final_gpa.toFixed(2)}`,
          MARGIN, y, { width: CW });
        y += 16;
        doc.fillColor(result.result_status === 'PASSED' ? '#1e7d32' : '#c62828')
          .font(FONT).fontSize(11).font('Helvetica-Bold')
          .text('Result: ' + result.result_status, MARGIN, y);
        y += 24;

        // Signature stamp, signature line, full name, then official designation.
        const sigY = doc.page.height - 130;
        const sigW = 190;
        const sx = [MARGIN + 8, MARGIN + CW - sigW - 8];
        [signatures.class_teacher, signatures.head_teacher].forEach((sig, index) => {
          if (sig && sig.data_base64) {
            try { doc.image(Buffer.from(sig.data_base64, 'base64'), sx[index] + 35, sigY, { fit: [120, 28], align: 'center' }); } catch (_) {}
          }
          doc.moveTo(sx[index], sigY + 31).lineTo(sx[index] + sigW, sigY + 31).strokeColor('#111').lineWidth(0.6).stroke();
          if (sig?.name) doc.font('Times-Bold').fontSize(8.5).fillColor('#111').text(String(sig.name), sx[index], sigY + 34, { width: sigW, align: 'center', lineBreak: false });
          doc.font(FONT).fontSize(8).fillColor('#333').text(String(sig?.designation || (index === 0 ? 'শ্রেণি শিক্ষক' : 'প্রধান শিক্ষক')), sx[index], sigY + 46, { width: sigW, align: 'center', lineBreak: false });
        });

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
module.exports.ensureCanonicalSubjectExams = ensureCanonicalSubjectExams;
module.exports.syncCurrentAcademicSession = syncCurrentAcademicSession;
module.exports.ensureSessionHorizon = ensureSessionHorizon;
module.exports.syncCanonicalEventClasses = syncCanonicalEventClasses;
module.exports.findOrCreateSessionByYear = findOrCreateSessionByYear;
module.exports.isAcademicSessionOpen = isAcademicSessionOpen;
module.exports.eventPublishGate = eventPublishGate;
module.exports.CANON = CANON;
