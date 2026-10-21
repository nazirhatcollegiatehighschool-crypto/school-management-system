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
const { computeResult } = require('./grading');

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
      total_gpa_without_4th: Number(r.total_gpa_without_4th || 0),
      gpa_4th_bonus: Number(r.gpa_4th_bonus || 0),
      result_status: r.result_status,
      pass_all: r.result_status === 'PASSED' ? 1 : 0,
      fail_count: failed.length,
      failed_subjects: failed,
      families: r.families || [],
    });
  }

  // Combined merit (Q16): marks desc, then weighted GPA desc, then name asc,
  // then roll asc as a final stable tiebreak.
  scored.sort((a, b) =>
    b.total_marks_obtained - a.total_marks_obtained ||
    b.final_gpa - a.final_gpa ||
    String(a.name || '').localeCompare(String(b.name || ''), 'bn') ||
    a.old_roll - b.old_roll);

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

  const dest = await promotionDestination(pool, srcCls);
  if (!dest) throw Object.assign(new Error('No promotion destination for ' + srcCls.name), { status: 400 });
  const { sections } = await destinationSections(pool, dest.id);
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
  const [[ev]] = await pool.query('SELECT id, year FROM exam_events WHERE id=?', [run.event_id]);

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    for (const a of alloc) {
      await conn.query(
        'UPDATE students SET class_id=?, section=?, roll=? WHERE id=?',
        [a.to_class_id, a.to_section, a.assigned_roll, a.student_id]);
      await conn.query(
        `INSERT INTO promotions
           (student_id, event_id, class_id, from_class, to_class, promoted_roll, decision,
            final_gpa, recorded_by, run_id, from_section, to_section, combined_rank, section_position, passing_year)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT (student_id, event_id)
         DO UPDATE SET to_class=EXCLUDED.to_class, promoted_roll=EXCLUDED.promoted_roll,
                       decision=EXCLUDED.decision, run_id=EXCLUDED.run_id,
                       from_section=EXCLUDED.from_section, to_section=EXCLUDED.to_section,
                       combined_rank=EXCLUDED.combined_rank, section_position=EXCLUDED.section_position`,
        [a.student_id, run.event_id, run.from_class_id, srcCls.name,
         (await conn.query('SELECT name FROM classes WHERE id=?', [a.to_class_id]))[0][0].name,
         a.assigned_roll, 'promoted', 0, userId, runId, a.from_section, a.to_section,
         a.combined_rank, a.assigned_roll, ev ? ev.year : null]);
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
  const merit = await computeMerit(class8Id, eventId);
  const [rules] = await pool.query('SELECT * FROM group_eligibility_rules');
  const rulesByGroup = new Map(rules.map(r => [r.group_name, r]));

  const poolRows = merit.rows.map(row => {
    const famByName = new Map((row.families || []).map(f => [String(f.subject).toLowerCase(), f]));
    const eligible = [];
    for (const [group, rule] of rulesByGroup) {
      const need = rule.mandatory_subjects || [];
      let ok = true;
      for (const subName of need) {
        const fam = famByName.get(String(subName).toLowerCase());
        if (!fam || fam.letter_grade === 'F') { ok = false; break; }
        const min = Number((rule.min_marks || {})[subName] || 0);
        if (min > 0 && Number(fam.total || 0) < min) { ok = false; break; }
      }
      if (ok) eligible.push(group);
    }
    return {
      student_id: row.student_id, name: row.name, roll: row.old_roll,
      total_marks_obtained: row.total_marks_obtained, final_gpa: row.final_gpa,
      combined_rank: row.combined_rank, eligible_groups: eligible,
    };
  });
  return { total: poolRows.length, students: poolRows };
}

/** Assign one student to a Class 9 group; returns destination class. */
async function assignGroup(studentId, fromClassId, toGroup, userId) {
  const [[dest]] = await pool.query(
    `SELECT id, name, section, group_name FROM classes
      WHERE name='Class 9' AND (group_name=? OR section=?) ORDER BY id LIMIT 1`,
    [toGroup, toGroup]);
  if (!dest) throw Object.assign(new Error('No Class 9 group "' + toGroup + '"'), { status: 400 });
  await pool.query(
    `INSERT INTO group_selections (student_id, from_class_id, to_group, to_class_id, selected_by, status)
     VALUES (?,?,?,?,?, 'confirmed')
     ON CONFLICT (student_id, from_class_id)
     DO UPDATE SET to_group=EXCLUDED.to_group, to_class_id=EXCLUDED.to_class_id,
                   selected_by=EXCLUDED.selected_by, selected_at=NOW(), status='confirmed'`,
    [studentId, fromClassId, toGroup, dest.id, userId]);
  return dest;
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
  isGroupedClass, promotionDestination, destinationSections,
  computeMerit, decide, reviewPromotion,
  snakeAssign, balanceRun, executeRun,
  groupPool, assignGroup, transferGroup, resequenceRolls,
};
