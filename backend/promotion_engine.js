// ------------------------------------------------------------------
// Promotion + section-balancing + Class 9 group engine (Q7, Q8, Q9).
//
// Three cooperating pieces:
//
// 1. MERIT - every student of a class, graded on one event, ranked by
//    Total Marks > Weighted GPA > pass status. Produces BOTH a section
//    position (inside their section/group) and a combined position
//    (across every section of the class). Q9 mechanic 1.
//
// 2. BALANCE - the promoted students of a class are split across the
//    destination's sections by combined merit using SNAKE assignment
//    (rank 1->A, 2->B, 3->B, 4->A ...). Snake keeps the strongest and
//    weakest students spread evenly rather than dumping the top half
//    into one section. Roll numbers restart at 1 inside each section.
//    Q9 mechanic 2.
//
// 3. GROUPS - a Class 8 cohort is offered to the Class 9 groups
//    (Science / Commerce / Arts). Eligibility comes from
//    group_eligibility_rules; a chosen group becomes the destination
//    class; rolls are re-issued per group. Admin can transfer a student
//    later and the destination merit + rolls recalculate. Q9 mechanic 3.
//
// Everything is written through section_allocations so the run is fully
// auditable and re-runnable without corrupting history.
// ------------------------------------------------------------------

const pool = require('./db');
const crypto = require('crypto');
const { computeResult } = require('./grading');
const { canonicalSubject, validateStudentCurriculum } = require('./curriculum');

// ------------------------------------------------------------------
// Destination class resolution
// ------------------------------------------------------------------

/** Class levels that carry sections (6-8) vs groups (9-10, SSC). */
function isGroupedClass(className) {
  return /class\s*(9|10)\b/i.test(String(className)) || /ssc/i.test(String(className));
}

/** "Class 6 (A)" -> the set of sections/groups on the destination class. */
async function destinationSections(conn, destClassId) {
  const [rows] = await conn.query(
    `SELECT id, name, section, group_name FROM classes WHERE id=?`, [destClassId]);
  const cls = rows[0];
  if (!cls) return { cls: null, sections: [] };
  const [all] = await conn.query(
    `SELECT id, name, section, group_name FROM classes
      WHERE name = ? ORDER BY section`, [cls.name]);
  return { cls, sections: all };
}

async function getPendingGroupClass9() {
  const [[pending]] = await pool.query(
    `SELECT id, name, section, group_name FROM classes
      WHERE name='Class 9' AND (section='Pending Group' OR group_name='Pending Group')
      ORDER BY id LIMIT 1`);
  if (pending) return pending;
  let insert;
  try {
    [insert] = await pool.query(
      `INSERT INTO classes (name, section, group_name) VALUES ('Class 9','Pending Group','Pending Group')`);
  } catch (err) {
    if (err.code !== '23505' && err.code !== 'ER_DUP_ENTRY') throw err;
    const [[raced]] = await pool.query(`SELECT id, name, section, group_name FROM classes WHERE name='Class 9' AND section='Pending Group' ORDER BY id LIMIT 1`);
    if (raced) return raced;
    throw err;
  }
  const [[created]] = await pool.query('SELECT id, name, section, group_name FROM classes WHERE id=?', [insert.insertId]);
  return created;
}

/**
 * Map a source class to its promotion destination. Unlike the legacy
 * version this does NOT try to preserve the old section: sections are
 * re-balanced by the algorithm. It only needs the destination CLASS NAME.
 */
async function promotionDestination(conn, cls) {
  const name = String(cls.name || '');
  if (/class\s*10/i.test(name)) {
    return (await conn.query(
      `SELECT id, name, section, group_name FROM classes
        WHERE name='SSC Batch' ORDER BY group_name, id LIMIT 1`))[0][0] || null;
  }
  if (/ssc/i.test(name)) return null; // SSC graduates out of the school
  const m = name.match(/(\d+)/);
  if (!m) return null;
  const nextName = 'Class ' + (Number(m[1]) + 1);
  const [rows] = await conn.query(
    `SELECT id, name, section, group_name FROM classes WHERE name=? ORDER BY section, id LIMIT 1`,
    [nextName]);
  return rows[0] || null;
}

// ------------------------------------------------------------------
// 1. MERIT
// ------------------------------------------------------------------

/** Group key for section-position: section for 6-8, group for 9-10/SSC. */
function sectionKey(row) {
  return String(row.group_name || row.section || '');
}

/**
 * Rank a whole class on one event.
 * Returns { rows:[...], byStudent:Map, totals } where each row carries
 * total_marks_obtained, final_gpa, pass_all, section_position,
 * combined_position and the failed-subject list.
 */
async function computeMerit(classId, eventId) {
  const [students] = await pool.query(
    `SELECT s.id, s.name, s.student_code, s.roll, s.section, c.group_name, c.section AS class_section
       FROM students s JOIN classes c ON c.id = s.class_id
      WHERE s.class_id=? AND (s.status IS NULL OR s.status='active')
      ORDER BY s.roll`, [classId]);

  const scored = [];
  for (const s of students) {
    const r = await computeResult(s.id, eventId);
    if (!r) continue;
    // Q10: an ABSENT subject counts as 0 and, when mandatory, as a fail.
    // grading.js tags a fully-absent subject letter_grade='Absent' (not 'F'),
    // so treat both 'F' and 'Absent' as failing for promotion purposes.
    const failed = (r.families || [])
      .filter(f => !f.is_optional && (f.letter_grade === 'F' || f.absent === true || f.letter_grade === 'Absent'))
      .map(f => f.subject);
    scored.push({
      student_id: s.id,
      name: s.name,
      student_code: s.student_code,
      old_roll: s.roll,
      old_section: s.section,
      group_name: s.group_name || s.class_section,
      total_marks_obtained: Number(r.total_marks || 0),
      total_marks_full: Number(r.total_full || 0),
      final_gpa: Number(r.final_gpa || 0),
      final_grade: gradeBand(r.final_gpa),
      source_event_id: eventId,
      total_gpa_without_4th: Number(r.total_gpa_without_4th || 0),
      gpa_4th_bonus: Number(r.gpa_4th_bonus || 0),
      result_status: r.result_status,
      pass_all: r.result_status === 'PASSED' ? 1 : 0,
      fail_count: failed.length,
      failed_subjects: failed,
      families: r.families || [],
    });
  }

  // Promotion merit: result grade first, marks second. If both are identical,
  // use a stable random-looking event/student key so repeated reads never
  // reorder the same cohort.
  scored.sort((a, b) =>
    gradeBandRank(b.final_grade) - gradeBandRank(a.final_grade) ||
    b.total_marks_obtained - a.total_marks_obtained ||
    randomMeritKey(eventId, a.student_id).localeCompare(randomMeritKey(eventId, b.student_id)));

  const sectionCounters = {};
  scored.forEach((row, i) => {
    row.combined_rank = i + 1;
    const key = sectionKey(row);
    sectionCounters[key] = (sectionCounters[key] || 0) + 1;
    row.section_position = sectionCounters[key];
  });

  const byStudent = new Map(scored.map(r => [r.student_id, r]));
  return { rows: scored, byStudent, total: scored.length };
}

// ------------------------------------------------------------------
// 2. PROMOTION DECISION (Q7 + Q8)
// ------------------------------------------------------------------

/**
 * Decide promoted / conditional / retained for one student using the
 * mandatory-pass list first, then the grace count. 4th-subject fails
 * never count (grading already excludes them from `failed`).
 */
async function decide(studentRow, classId, examType) {
  const [[grace]] = await pool.query(
    'SELECT grace_failed FROM promotion_grace WHERE class_id=? AND exam_type=?', [classId, examType]);
  const graceFailed = grace ? Number(grace.grace_failed) : 0;

  const [mandatory] = await pool.query(
    `SELECT s.name FROM mandatory_pass mp JOIN subjects s ON s.id = mp.subject_id
      WHERE mp.class_id=?`, [classId]);
  const mandatoryNames = mandatory.map(m => m.name);

  const failed = studentRow.failed_subjects || [];
  const mandatoryFailed = failed.filter(f =>
    mandatoryNames.some(mn => String(f).toLowerCase() === String(mn).toLowerCase()));

  let decision, eligible = false;
  if (studentRow.result_status === 'ABSENT' || !(studentRow.families || []).length) {
    decision = 'retained';
  } else if (mandatoryFailed.length > 0) {
    decision = 'retained';                       // grace cannot rescue a mandatory fail
  } else if (failed.length === 0) {
    decision = 'promoted'; eligible = true;
  } else if (failed.length <= graceFailed) {
    decision = 'conditional'; eligible = true;   // Q8: conditional students DO move up
  } else {
    decision = 'retained';
  }
  return {
    decision, eligible, grace_failed: graceFailed,
    mandatory_failed: mandatoryFailed, failed_subjects: failed,
  };
}

/** Full review list for a class on a promotion-source event. */
async function reviewPromotion(classId, eventId) {
  const [[cls]] = await pool.query('SELECT id, name, section, group_name FROM classes WHERE id=?', [classId]);
  if (!cls) throw Object.assign(new Error('class not found'), { status: 404 });
  const [[ev]] = await pool.query('SELECT id, name, exam_kind, is_published FROM exam_events WHERE id=?', [eventId]);
  if (!ev) throw Object.assign(new Error('event not found'), { status: 404 });

  const merit = await computeMerit(classId, eventId);
  const examType = ev.exam_kind === 'test' ? 'test' : 'annual';

  const review = [];
  for (const row of merit.rows) {
    const d = await decide(row, classId, examType);
    review.push({
      ...row,
      decision: d.decision,
      eligible: d.eligible,
      grace_failed: d.grace_failed,
      mandatory_failed: d.mandatory_failed,
    });
  }
  review.sort((a, b) => a.combined_rank - b.combined_rank);
  return { event: ev, class: cls, exam_type: examType, total: review.length, review };
}

// ------------------------------------------------------------------
// 3. SECTION BALANCING (Q9 mechanic 2)
// ------------------------------------------------------------------

/**
 * Round-robin assign ranks across N destination sections, then move the
 * EXTRA students (remainder) onto the earliest sections. This satisfies the
 * exact rule: with 11 students in 3 sections, A gets 4 and B gets 4, C gets 3
 * (11 % 3 == 2  ->  A +1 and B +1). It also keeps the section averages close
 * because consecutive ranks alternate sections.
 *
 * rank 1->A, 2->B, 3->C, 4->A, 5->B, 6->C ...  then rebalance the tail.
 */
function snakeAssign(ranks, sectionNames) {
  const n = sectionNames.length;
  if (n === 1) return ranks.map((_, i) => ({ rank_index: i, section: sectionNames[0] }));

  const total = ranks.length;
  // Target size per section: floor, then the first (total % n) sections get +1.
  const base = Math.floor(total / n);
  const extra = total % n;
  const target = sectionNames.map((_, i) => base + (i < extra ? 1 : 0));

  const out = ranks.map((_, i) => ({ rank_index: i, section: sectionNames[i % n] }));
  // Greedy rebalance: move the lowest-ranked student out of an over-full
  // section into the earliest under-full section (never moves more than the
  // remainder count, so section parity stays exact).
  const counts = {};
  for (const name of sectionNames) counts[name] = 0;
  out.forEach(o => { counts[o.section]++; });
  const overflow = [];
  for (const name of sectionNames) {
    while (counts[name] > target[sectionNames.indexOf(name)]) {
      const lastIdx = out.map(o => o.section).lastIndexOf(name);
      overflow.push(lastIdx);
      out[lastIdx].section = null; // mark for reassignment
      counts[name]--;
    }
  }
  if (overflow.length) {
    const under = [];
    for (const name of sectionNames) {
      while (counts[name] < target[sectionNames.indexOf(name)]) { under.push(name); counts[name]++; }
    }
    // Highest rank first picks the earliest under-full section.
    overflow.sort((a, b) => a - b);
    overflow.forEach((idx, k) => { out[idx].section = under[k]; });
  }
  return out;
}

/**
 * Build (and persist) a balanced allocation for a promotion run.
 * does NOT move students yet - execute() applies it.
 */
async function balanceRun(eventId, classId, opts = {}) {
  const algorithm = opts.algorithm || 'snake';
  const [[srcCls]] = await pool.query('SELECT id, name, section, group_name FROM classes WHERE id=?', [classId]);
  if (!srcCls) throw Object.assign(new Error('class not found'), { status: 404 });

  let dest = await promotionDestination(pool, srcCls);
  if (!dest) throw Object.assign(new Error('No promotion destination for ' + srcCls.name), { status: 400 });
  let sections = (await destinationSections(pool, dest.id)).sections;
  const isClass8 = /class\s*8\b/i.test(String(srcCls.name));
  if (isClass8) {
    dest = await getPendingGroupClass9();
    sections = [dest];
  }
  if (!sections.length) throw Object.assign(new Error('Destination class has no sections'), { status: 400 });
  const sectionNames = sections.map(s => s.section || s.group_name);

  const review = await reviewPromotion(classId, eventId);
  const promoted = review.review.filter(r => r.eligible);

  // Q9 + user decision: a grouped source class (Class 9/10, section == group)
  // must promote students WITHIN their own group, not redistribute them across
  // every destination group. A plain sectioned class (6-8) balances across all
  // sections.
  const grouped = isGroupedClass(srcCls.name);
  let assignments;
  if (grouped) {
    // Each student's destination group == their own group; rolls are assigned
    // per-group below (rollCounter is keyed by section, so each group restarts).
    assignments = promoted.map((st, i) => ({
      rank_index: i,
      section: sectionNames.includes(st.old_section || '') ? st.old_section : sectionNames[0],
    }));
  } else {
    assignments = snakeAssign(promoted, sectionNames);
  }
  const sectionOfClass = {};
  for (const s of sections) sectionOfClass[s.section || s.group_name] = s.id;

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query(
      `INSERT INTO promotion_runs (event_id, from_class_id, algorithm, total_promoted, sections_count, status)
       VALUES (?,?,?,?,?, 'balanced')
       ON CONFLICT (event_id, from_class_id)
       DO UPDATE SET algorithm=EXCLUDED.algorithm, total_promoted=EXCLUDED.total_promoted,
                     sections_count=EXCLUDED.sections_count, status='balanced'`,
      [eventId, classId, algorithm, promoted.length, sectionNames.length]);
    let runId;
    const [[runRow]] = await conn.query(
      'SELECT id FROM promotion_runs WHERE event_id=? AND from_class_id=?', [eventId, classId]);
    runId = runRow.id;

    await conn.query('DELETE FROM section_allocations WHERE run_id=?', [runId]);
    const rollCounter = {};
    for (let i = 0; i < promoted.length; i++) {
      const st = promoted[i];
      const sec = assignments[i].section;
      rollCounter[sec] = (rollCounter[sec] || 0) + 1;
      await conn.query(
        `INSERT INTO section_allocations
           (run_id, student_id, from_class_id, from_section, to_class_id, to_section,
            combined_rank, assigned_roll, allocated_by)
         VALUES (?,?,?,?,?,?,?,?, 'auto')`,
        [runId, st.student_id, classId, st.old_section, sectionOfClass[sec], sec,
         st.combined_rank, rollCounter[sec]]);
    }
    await conn.commit();
    const [alloc] = await pool.query(
      `SELECT sa.*, s.name FROM section_allocations sa JOIN students s ON s.id=sa.student_id
        WHERE sa.run_id=? ORDER BY sa.to_section, sa.assigned_roll`, [runId]);
    return {
      run_id: runId, algorithm, dest_class: dest, sections: sectionNames,
      total_promoted: promoted.length,
      retained: review.review.filter(r => !r.eligible).map(r => ({ student_id: r.student_id, name: r.name, decision: r.decision })),
      allocations: alloc,
    };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

/** Apply a balanced run: move students + set rolls + write promotions. */
async function executeRun(runId, userId) {
  const [[run]] = await pool.query('SELECT * FROM promotion_runs WHERE id=?', [runId]);
  if (!run) throw Object.assign(new Error('run not found'), { status: 404 });
  const [alloc] = await pool.query('SELECT * FROM section_allocations WHERE run_id=? ORDER BY to_section, assigned_roll', [runId]);
  const [[srcCls]] = await pool.query('SELECT id, name FROM classes WHERE id=?', [run.from_class_id]);
  const [[ev]] = await pool.query('SELECT id, year, session_id FROM exam_events WHERE id=?', [run.event_id]);
  const [[targetSession]] = ev
    ? await pool.query('SELECT id FROM sessions WHERE name=?', [String(Number(ev.year) + 1)])
    : [[], []];
  if (!targetSession) throw Object.assign(new Error('Next academic session is not provisioned'), { status: 400 });

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    for (const a of alloc) {
      await conn.query(
        'UPDATE students SET class_id=?, section=?, roll=?, session_id=? WHERE id=?',
        [a.to_class_id, a.to_section, a.assigned_roll, targetSession.id, a.student_id]);
      await conn.query(
        `INSERT INTO promotions
           (student_id, event_id, class_id, from_class, to_class, promoted_roll, decision,
            final_gpa, recorded_by, run_id, from_section, to_section, combined_rank, section_position,
            destination_session_id, passing_year)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT (student_id, event_id)
         DO UPDATE SET to_class=EXCLUDED.to_class, promoted_roll=EXCLUDED.promoted_roll,
                       decision=EXCLUDED.decision, run_id=EXCLUDED.run_id,
                       from_section=EXCLUDED.from_section, to_section=EXCLUDED.to_section,
                       combined_rank=EXCLUDED.combined_rank, section_position=EXCLUDED.section_position,
                       destination_session_id=EXCLUDED.destination_session_id`,
        [a.student_id, run.event_id, run.from_class_id, srcCls.name,
         (await conn.query('SELECT name FROM classes WHERE id=?', [a.to_class_id]))[0][0].name,
         a.assigned_roll, 'promoted', 0, userId, runId, a.from_section, a.to_section,
          a.combined_rank, a.assigned_roll, targetSession.id, ev ? ev.year : null]);
    }
    await conn.query(
      `UPDATE promotion_runs SET status='executed', executed_by=?, executed_at=NOW() WHERE id=?`,
      [userId, runId]);
    await conn.commit();
    return { ok: true, moved: alloc.length };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

// ------------------------------------------------------------------
// 4. CLASS 9 GROUP ENGINE (Q9 mechanic 3)
// ------------------------------------------------------------------

/** Graduated Class 8 pool with eligibility for each Class 9 group. */
async function groupPool(class8Id, eventId) {
  const [[cls]] = await pool.query('SELECT id, name FROM classes WHERE id=?', [class8Id]);
  if (!cls || !/class\s*8\b/i.test(String(cls.name))) {
    throw Object.assign(new Error('Waiting for Group Approval only accepts Class 8 promotion results.'), { status: 400 });
  }
  const [[event]] = await pool.query(
    `SELECT id, name, year, is_published FROM exam_events WHERE id=?`, [eventId]);
  if (!event || Number(event.is_published) !== 1) {
    throw Object.assign(new Error('Class 8-এর published promotion result বেছে নিন।'), { status: 400 });
  }
  const [rows] = await pool.query(
    `SELECT p.student_id, p.promoted_roll, s.name, s.student_code, p.decision,
            gs.status AS group_status, gs.to_group
       FROM promotions p JOIN students s ON s.id=p.student_id
       LEFT JOIN group_selections gs ON gs.student_id=p.student_id AND gs.from_class_id=p.class_id
      WHERE p.event_id=? AND p.class_id=? AND p.decision IN ('promoted','conditional','grace_promoted','admin_override')
        AND (p.destination_session_id IS NULL OR p.destination_session_id=s.session_id)
        AND s.class_id=(SELECT pending.id FROM classes pending WHERE LOWER(TRIM(pending.name))='class 9'
          AND (LOWER(TRIM(COALESCE(pending.section,'')))='pending group' OR LOWER(TRIM(COALESCE(pending.group_name,'')))='pending group')
          ORDER BY pending.id LIMIT 1)
      ORDER BY p.promoted_roll, s.id`, [eventId, class8Id]);
  const ranked = [];
  for (const row of rows) {
    if (row.group_status === 'confirmed') continue;
    const result = await computeResult(row.student_id, eventId);
    if (!result) continue;
    ranked.push({
      student_id: row.student_id, name: row.name, student_code: row.student_code,
      roll: row.promoted_roll, total_marks_obtained: Number(result.total_marks || 0),
      final_gpa: Number(result.final_gpa || 0), final_grade: gradeBand(result.final_gpa), decision: row.decision,
      eligible_groups: ['Arts', 'Commerce', 'Science'],
    });
  }
  ranked.sort((a, b) => gradeBandRank(b.final_grade) - gradeBandRank(a.final_grade) ||
    b.total_marks_obtained - a.total_marks_obtained ||
    randomMeritKey(event.id, a.student_id).localeCompare(randomMeritKey(event.id, b.student_id)));
  ranked.forEach((row, index) => { row.combined_rank = index + 1; });
  return { total: ranked.length, students: ranked, class: cls, event };
}

/** Shared Admin/Class 9-teacher queue, sorted once by the same merit rule. */
async function pendingGroupApprovals() {
  const [sources] = await pool.query(
    `SELECT DISTINCT p.class_id AS from_class_id, p.event_id
       FROM promotions p JOIN classes c ON c.id=p.class_id
       JOIN students s ON s.id=p.student_id
      WHERE LOWER(TRIM(c.name))='class 8'
        AND s.class_id=(SELECT pending.id FROM classes pending WHERE LOWER(TRIM(pending.name))='class 9'
          AND (LOWER(TRIM(COALESCE(pending.section,'')))='pending group' OR LOWER(TRIM(COALESCE(pending.group_name,'')))='pending group')
          ORDER BY pending.id LIMIT 1)
        AND p.decision IN ('promoted','conditional','grace_promoted','admin_override')
        AND (p.destination_session_id IS NULL OR p.destination_session_id=s.session_id)
        AND EXISTS (SELECT 1 FROM exam_events ev WHERE ev.id=p.event_id AND ev.is_published=1)
        AND NOT EXISTS (SELECT 1 FROM group_selections gs WHERE gs.student_id=p.student_id
                          AND gs.from_class_id=p.class_id AND gs.status='confirmed')
      ORDER BY p.event_id DESC, p.class_id`);
  const students = [];
  for (const source of sources) {
    const result = await groupPool(source.from_class_id, source.event_id);
    for (const student of result.students) students.push({
      ...student, from_class_id: source.from_class_id, event_id: source.event_id,
      event: result.event,
    });
  }
  students.sort((a, b) => gradeBandRank(b.final_grade) - gradeBandRank(a.final_grade) ||
    Number(b.total_marks_obtained) - Number(a.total_marks_obtained) ||
    randomMeritKey(a.event_id, a.student_id).localeCompare(randomMeritKey(b.event_id, b.student_id)));
  students.forEach((row, index) => { row.combined_rank = index + 1; });
  return { students, total: students.length };
}

function gradeBand(gpa) {
  const value = Number(gpa || 0);
  if (value >= 5) return 'A+';
  if (value >= 4) return 'A';
  if (value >= 3.5) return 'A-';
  if (value >= 3) return 'B';
  if (value >= 2) return 'C';
  if (value >= 1) return 'D';
  return 'F';
}
function gradeBandRank(value) { return ({ 'A+':7, A:6, 'A-':5, B:4, C:3, D:2, F:1 })[value] || 0; }
// Stable pseudo-random tiebreak: equal-grade/equal-marks students are picked
// without favoring roll/name, while every reload keeps the same published rank.
function randomMeritKey(eventId, studentId) {
  return crypto.createHash('sha256').update(`merit:${eventId}:${studentId}`).digest('hex');
}

/** Assign one student to a Class 9 group; returns destination class. */
async function assignGroup(studentId, fromClassId, toGroup, userId, choices = {}) {
  const canonicalGroup = /arts|humanit/i.test(String(toGroup)) ? 'Arts'
    : /commerce|business/i.test(String(toGroup)) ? 'Commerce'
    : /science/i.test(String(toGroup)) ? 'Science' : null;
  if (!canonicalGroup) throw Object.assign(new Error('Arts, Commerce অথবা Science group বেছে নিন।'), { status: 400 });
  const aliases = canonicalGroup === 'Arts' ? ['%arts%', '%humanit%']
    : canonicalGroup === 'Commerce' ? ['%commerce%', '%business%'] : ['%science%'];
  const [[dest]] = await pool.query(
    `SELECT id, name, section, group_name FROM classes
      WHERE name='Class 9' AND (
        LOWER(COALESCE(group_name,'')) LIKE ? OR LOWER(COALESCE(section,'')) LIKE ? OR
        LOWER(COALESCE(group_name,'')) LIKE ? OR LOWER(COALESCE(section,'')) LIKE ?
      ) ORDER BY id LIMIT 1`,
    [aliases[0], aliases[0], aliases[1] || aliases[0], aliases[1] || aliases[0]]);
  if (!dest) throw Object.assign(new Error('No Class 9 group "' + toGroup + '"'), { status: 400 });
  const curriculum = await validateStudentCurriculum(dest.id, choices);
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    // Serialize approvals that affect the same destination roster. This keeps
    // unique (class_id, roll) safe while the whole stream is merit-ranked.
    await conn.query('SELECT id FROM classes WHERE id=? FOR UPDATE', [dest.id]);
    const [[student]] = await conn.query(
      `SELECT s.id, s.class_id, s.session_id, s.religion, s.roll
         FROM students s WHERE s.id=? FOR UPDATE`, [studentId]);
    if (!student) throw Object.assign(new Error('Student not found'), { status: 404 });
    const [[pendingClass]] = await conn.query(
      `SELECT id FROM classes WHERE LOWER(TRIM(name))='class 9'
        AND (LOWER(TRIM(COALESCE(section,'')))='pending group' OR LOWER(TRIM(COALESCE(group_name,'')))='pending group')
        ORDER BY id LIMIT 1`);
    if (!pendingClass || Number(student.class_id) !== Number(pendingClass.id)) {
      const [[already]] = await conn.query(
        `SELECT gs.to_group, gs.to_class_id, s.roll FROM group_selections gs
           JOIN students s ON s.id=gs.student_id
          WHERE gs.student_id=? AND gs.from_class_id=? AND gs.status='confirmed'`,
        [studentId, fromClassId]);
      if (already && already.to_group === canonicalGroup) {
        await conn.commit();
        return { id: already.to_class_id, group_name: canonicalGroup, roll: already.roll, already_approved: true };
      }
      throw Object.assign(new Error('শিক্ষার্থীকে আগে Pending Group Class 9-এ promote করতে হবে।'), { status: 409 });
    }
    const [[promotion]] = await conn.query(
      `SELECT event_id, destination_session_id, decision FROM promotions
        WHERE student_id=? AND class_id=? AND decision IN ('promoted','conditional','grace_promoted','admin_override')
          AND (destination_session_id IS NULL OR destination_session_id=?)
        ORDER BY id DESC LIMIT 1`, [studentId, fromClassId, student.session_id]);
    if (!promotion || !['promoted','conditional','grace_promoted','admin_override'].includes(String(promotion.decision))) {
      throw Object.assign(new Error('শুধু promoted Class 8 শিক্ষার্থীর group approval করা যাবে।'), { status: 409 });
    }

    // Keep prior-class enrollments as the immutable curriculum snapshot used
    // by historical results; add destination-class choices without deleting it.
    const [subjects] = await conn.query('SELECT id, name, is_optional, is_fourth_subject, is_elective FROM subjects WHERE class_id=?', [dest.id]);
    const chosen = [];
    for (const [choice, mandatory] of [[curriculum.compulsory_subject, true], [curriculum.optional_subject, false]]) {
      if (!choice) continue;
      const sub = subjects.find(item => canonicalSubject(item.name) === choice ||
        (choice === 'Agriculture' && /agriculture/i.test(item.name)) ||
        (choice === 'Higher Mathematics' && /higher\s*math/i.test(item.name)) ||
        (choice === 'Home Science' && /home\s*(science|economics)/i.test(item.name)) ||
        (choice === 'Civics' && /civics/i.test(item.name)) ||
        (choice === 'Economics' && /economics/i.test(item.name)));
      if (!sub) throw Object.assign(new Error(`Class 9 ${canonicalGroup}-এ ${choice} subject setup করা নেই।`), { status: 400 });
      chosen.push({ ...sub, mandatory });
    }
    for (const sub of chosen) {
      await conn.query(
        `INSERT INTO student_subjects (student_id, subject_id, is_mandatory, is_fourth_subject, is_elective, assigned_by)
         VALUES (?,?,?,?,?,?) ON CONFLICT (student_id,subject_id) DO UPDATE SET
          is_mandatory=EXCLUDED.is_mandatory, is_fourth_subject=EXCLUDED.is_fourth_subject,
          is_elective=EXCLUDED.is_elective, assigned_by=EXCLUDED.assigned_by`,
        [studentId, sub.id, sub.mandatory ? 1 : 0, sub.mandatory ? 0 : 1, sub.mandatory ? 0 : 1, userId]);
    }
    // Preserve religion-specific subject enrollment in the destination class.
    for (const sub of subjects.filter(s => /religion|islam|hindu|christian|buddh/i.test(s.name))) {
      const n = String(sub.name).toLowerCase(), r = String(student.religion || '').toLowerCase();
      const matches = /hindu/.test(n) ? /hindu/.test(r) : /christian/.test(n) ? /christian/.test(r)
        : /buddh/.test(n) ? /buddh/.test(r) : /islam|muslim/.test(n) ? /islam|muslim/.test(r) : true;
      if (matches) await conn.query(
        `INSERT INTO student_subjects (student_id, subject_id, is_mandatory, is_fourth_subject, is_elective, assigned_by)
         VALUES (?,?,1,0,0,?) ON CONFLICT (student_id,subject_id) DO NOTHING`, [studentId, sub.id, userId]);
    }
    const targetSessionId = promotion.destination_session_id || student.session_id;
    await conn.query(
      `UPDATE students SET class_id=?, section=?, roll=0, session_id=?, optional_subject=?, compulsory_subject=? WHERE id=?`,
      [dest.id, dest.section || dest.group_name || canonicalGroup, targetSessionId, curriculum.optional_subject, curriculum.compulsory_subject, studentId]);
    await conn.query(
      `INSERT INTO group_selections (student_id, from_class_id, to_group, to_class_id, selected_by, status)
       VALUES (?,?,?,?,?, 'confirmed') ON CONFLICT (student_id, from_class_id) DO UPDATE SET
         to_group=EXCLUDED.to_group, to_class_id=EXCLUDED.to_class_id, selected_by=EXCLUDED.selected_by,
         selected_at=NOW(), status='confirmed'`, [studentId, fromClassId, canonicalGroup, dest.id, userId]);

    // Keep the promotion workflow dashboard aligned with the student's real
    // destination after the second-stage group decision (the first-stage
    // promotion correctly points to Pending Group until this moment).
    if (targetSessionId) {
      await conn.query(
        `UPDATE student_promotion_status SET target_class_id=?, status='promoted', updated_at=NOW()
          WHERE student_id=? AND target_session_id=?`, [dest.id, studentId, targetSessionId]);
    }
    await conn.query(
      `UPDATE promotion_history SET to_class_id=?
        WHERE id=(SELECT id FROM (SELECT id FROM promotion_history
          WHERE student_id=? AND from_class_id=? ORDER BY id DESC LIMIT 1) latest)`, [dest.id, studentId, fromClassId]);

    const [cohort] = await conn.query(
      `SELECT s.id, s.roll, gs.from_class_id FROM students s
       JOIN group_selections gs ON gs.student_id=s.id AND gs.to_group=? AND gs.status='confirmed'
       WHERE s.class_id=?`, [canonicalGroup, dest.id]);
    const ranked = [];
    for (const row of cohort) {
      const [[sourcePromotion]] = await conn.query(
        `SELECT event_id FROM promotions WHERE student_id=? AND class_id=?
          AND decision IN ('promoted','conditional','grace_promoted','admin_override') ORDER BY id DESC LIMIT 1`,
        [row.id, row.from_class_id]);
      const eventForStudent = sourcePromotion && sourcePromotion.event_id;
      const result = eventForStudent ? await computeResult(row.id, eventForStudent, {
        group_name: canonicalGroup,
        compulsory_subject: row.id === Number(studentId) ? curriculum.compulsory_subject : undefined,
        optional_subject: row.id === Number(studentId) ? curriculum.optional_subject : undefined,
      }) : null;
      const gpa = result ? Number(result.final_gpa || 0) : -1;
      ranked.push({ id: row.id, roll: row.roll, gpa, grade: result ? gradeBand(gpa) : null,
        total: result ? Number(result.total_marks || 0) : -1, event_id: eventForStudent, from_class_id: row.from_class_id });
    }
    ranked.sort((a,b) => gradeBandRank(b.grade) - gradeBandRank(a.grade) ||
      b.total - a.total || randomMeritKey(a.event_id, a.id).localeCompare(randomMeritKey(b.event_id, b.id)));
    for (let i = 0; i < ranked.length; i++) {
      const row = ranked[i];
      await conn.query('UPDATE students SET roll=? WHERE id=?', [-(i + 1), row.id]);
    }
    for (let i = 0; i < ranked.length; i++) {
      const row = ranked[i], roll = i + 1;
      await conn.query('UPDATE students SET roll=? WHERE id=?', [roll, row.id]);
      if (row.event_id) await conn.query(
        `UPDATE promotions SET to_class=?, to_section=?, promoted_roll=? WHERE student_id=? AND event_id=?`,
        [dest.name, dest.group_name || dest.section || canonicalGroup, roll, row.id, row.event_id]);
    }
    await conn.commit();
    return { ...dest, group_name: canonicalGroup, roll: ranked.find(r => r.id === Number(studentId)) ? ranked.findIndex(r => r.id === Number(studentId)) + 1 : null };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally { conn.release(); }
}

/** Re-number rolls inside one class by current merit (marks-independent order preserved). */
async function resequenceRolls(conn, classId) {
  const [rows] = await conn.query(
    `SELECT id FROM students WHERE class_id=? AND (status IS NULL OR status='active') ORDER BY roll NULLS LAST, id`, [classId]);
  let n = 0;
  for (const r of rows) { n++; await conn.query('UPDATE students SET roll=? WHERE id=?', [n, r.id]); }
  return n;
}

/** Admin group transfer: move a student between Class 9 groups + resequence. */
async function transferGroup(studentId, toGroup, reason, userId) {
  const [[stu]] = await pool.query('SELECT id, name, class_id, section, roll FROM students WHERE id=?', [studentId]);
  if (!stu) throw Object.assign(new Error('student not found'), { status: 404 });
  const [[fromCls]] = await pool.query('SELECT id, name, section, group_name FROM classes WHERE id=?', [stu.class_id]);
  const [[dest]] = await pool.query(
    `SELECT id, name, section, group_name FROM classes
      WHERE name=? AND (group_name=? OR section=?) ORDER BY id LIMIT 1`,
    [fromCls.name, toGroup, toGroup]);
  if (!dest) throw Object.assign(new Error('destination group not found'), { status: 400 });

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query('UPDATE students SET class_id=?, section=? WHERE id=?',
      [dest.id, dest.section || dest.group_name, studentId]);
    const newRoll = await resequenceRolls(conn, dest.id);
    await resequenceRolls(conn, fromCls.id);
    await conn.query(
      `INSERT INTO group_transfers
         (student_id, from_group, to_group, from_class_id, to_class_id, reason,
          previous_roll, new_roll, executed_by)
       VALUES (?,?,?,?,?,?,?,?,?)`,
      [studentId, fromCls.group_name || fromCls.section, dest.group_name || dest.section,
       fromCls.id, dest.id, reason, stu.roll, newRoll, userId]);
    await conn.commit();
    return { ok: true, to_class_id: dest.id, to_group: dest.group_name || dest.section, new_roll: newRoll };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = {
  isGroupedClass, promotionDestination, destinationSections, getPendingGroupClass9,
  computeMerit, decide, reviewPromotion,
  snakeAssign, balanceRun, executeRun,
  groupPool, pendingGroupApprovals, assignGroup, transferGroup, resequenceRolls,
};
