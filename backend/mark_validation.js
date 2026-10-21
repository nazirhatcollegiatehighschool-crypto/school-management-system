// ------------------------------------------------------------------
// Mark-entry validation shared by the teacher SUBMIT endpoint and the
// admin APPROVE endpoint (Q4: hard-block both).
//
// Two independent rules:
//   1. COMPLETE - every enrolled student must have either a mark or the
//      absent flag. A blank cell is not "0", it is missing data, and
//      grading a blank as 0 silently invents an F.
//   2. IN RANGE - no component may exceed its subject full (cq > cq_full
//      is always a data error). OCR capture makes this far more likely.
//
// Returns { ok, errors:[{student_id, student_name, field, message}],
//           complete, in_range }
// ------------------------------------------------------------------

const pool = require('./db');

function asNum(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : NaN;
}

/**
 * @param examId      exam row id
 * @param opts.strict when true (submit/approve) missing students are fatal;
 *                    when false (autosave) they are only reported.
 */
async function validateExamMarks(examId, opts = {}) {
  const strict = opts.strict !== false;

  const [[exam]] = await pool.query(
    `SELECT e.id, e.class_id, e.subject_id, sub.name AS subject_name, sub.full_marks,
            sub.cq_full, sub.mcq_full, sub.practical_full, sub.written_full, sub.ca_full
       FROM exams e JOIN subjects sub ON sub.id = e.subject_id
      WHERE e.id = ?`, [examId]);
  if (!exam) return { ok: false, errors: [{ field: 'exam', message: 'Exam not found' }], complete: false, in_range: true };

  const full = {
    cq: asNum(exam.cq_full), mcq: asNum(exam.mcq_full), practical: asNum(exam.practical_full),
    written: asNum(exam.written_full), ca: asNum(exam.ca_full),
  };
  const hasComponents = Object.values(full).some(v => v !== null && v !== undefined);
  const totalFull = asNum(exam.full_marks) || 100;

  // Enrolled students (mirrors GET /exams/:id eligibility logic).
  const [[enrollCount]] = await pool.query(
    `SELECT COUNT(*) AS c FROM student_subjects ss
       JOIN students s ON s.id = ss.student_id
      WHERE ss.subject_id = ? AND s.class_id = ?`,
    [exam.subject_id, exam.class_id]);
  let students;
  if (enrollCount && Number(enrollCount.c) > 0) {
    [students] = await pool.query(
      `SELECT s.id, s.name, s.roll FROM students s
        JOIN student_subjects ss ON ss.student_id = s.id AND ss.subject_id = ?
       WHERE s.class_id = ? AND (s.status IS NULL OR s.status='active') ORDER BY s.roll`,
      [exam.subject_id, exam.class_id]);
  } else {
    [students] = await pool.query(
      `SELECT id, name, roll FROM students WHERE class_id=? AND (status IS NULL OR status='active') ORDER BY roll`,
      [exam.class_id]);
  }

  const [marks] = await pool.query(
    'SELECT student_id, marks, total, cq, mcq, practical, written, ca, absent FROM marks WHERE exam_id=?',
    [examId]);
  const byStudent = new Map(marks.map(m => [String(m.student_id), m]));

  const errors = [];
  for (const s of students) {
    const m = byStudent.get(String(s.id));
    if (!m) {
      if (strict) errors.push({ student_id: s.id, student_name: s.name, field: 'all', message: `Roll ${s.roll}: কোনো নম্বর বা absent flag নেই` });
      continue;
    }
    if (Number(m.absent) === 1) continue;             // absent is a valid terminal state

    if (hasComponents) {
      let anyValue = false;
      for (const key of ['cq', 'mcq', 'practical', 'written', 'ca']) {
        if (full[key] === null || full[key] === undefined) continue;  // component not used by this subject
        const v = asNum(m[key]);
        if (v === null) {
          if (strict) errors.push({ student_id: s.id, student_name: s.name, field: key, message: `Roll ${s.roll}: ${key.toUpperCase()} খালি` });
          continue;
        }
        anyValue = true;
        if (Number.isNaN(v)) { errors.push({ student_id: s.id, student_name: s.name, field: key, message: `Roll ${s.roll}: ${key.toUpperCase()} সংখ্যা নয়` }); continue; }
        if (v < 0 || v > Number(full[key])) {
          errors.push({ student_id: s.id, student_name: s.name, field: key, message: `Roll ${s.roll}: ${key.toUpperCase()} = ${v}, সর্বোচ্চ ${full[key]}` });
        }
      }
      if (!anyValue && strict) {
        errors.push({ student_id: s.id, student_name: s.name, field: 'all', message: `Roll ${s.roll}: কোনো component পূরণ হয়নি` });
      }
    } else {
      const v = asNum(m.marks);
      if (v === null) {
        if (strict) errors.push({ student_id: s.id, student_name: s.name, field: 'marks', message: `Roll ${s.roll}: নম্বর খালি` });
      } else if (Number.isNaN(v) || v < 0 || v > totalFull) {
        errors.push({ student_id: s.id, student_name: s.name, field: 'marks', message: `Roll ${s.roll}: নম্বর = ${m.marks}, সর্বোচ্চ ${totalFull}` });
      }
    }
  }

  const complete = !errors.some(e => /খালি|নেই|পূরণ/.test(e.message));
  const inRange = !errors.some(e => /সর্বোচ্চ|সংখ্যা নয়/.test(e.message));
  return {
    ok: errors.length === 0,
    errors: errors.slice(0, 200),
    error_count: errors.length,
    complete, in_range: inRange,
    total_students: students.length,
    marked_students: marks.length,
  };
}

module.exports = { validateExamMarks };
