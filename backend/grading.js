/* SSC Board Grading Engine — MySQL port of transcript-generator grading.js */
const pool = require('./db');

const FAMILY_OF = {
  'Bangla 1st': 'Bangla', 'Bangla 2nd': 'Bangla',
  'English 1st': 'English', 'English 2nd': 'English'
};
const FOURTH_FAMILIES = new Set(['Higher Mathematics', 'Agriculture', 'Agriculture Studies', 'Home Science']);
const LAB_SUBJECTS = ['Physics', 'Chemistry', 'Biology', 'Higher Mathematics'];
const COMPONENT_MIN = { 70: 23, 50: 17, 30: 10, 25: 8 };

function familyOf(name) { return FAMILY_OF[name] || name; }

function getGrading(mark) {
  if (mark >= 80) return { letter_grade: 'A+', grade_point: 5.0 };
  if (mark >= 70) return { letter_grade: 'A', grade_point: 4.0 };
  if (mark >= 60) return { letter_grade: 'A-', grade_point: 3.5 };
  if (mark >= 50) return { letter_grade: 'B', grade_point: 3.0 };
  if (mark >= 40) return { letter_grade: 'C', grade_point: 2.0 };
  if (mark >= 33) return { letter_grade: 'D', grade_point: 1.0 };
  return { letter_grade: 'F', grade_point: 0.0 };
}

function componentPass(value, full) {
  const min = COMPONENT_MIN[full] != null ? COMPONENT_MIN[full] : full / 3;
  return Number(value) >= min;
}

function classLevelOf(className) {
  const m = String(className || '').match(/\d+/);
  return m ? m[0] : '6';
}

function isSectionClass(cls) { return ['9', '10'].indexOf(String(cls)) === -1; }

function layoutFor(classLevel, subject, maxes) {
  const sName = String((subject && subject.name) || '');
  if (maxes && (maxes.cq_full != null || maxes.mcq_full != null || maxes.practical_full != null)) {
    const parts = [];
    if (maxes.cq_full != null) parts.push({ key: 'cq', full: Number(maxes.cq_full) });
    if (maxes.mcq_full != null) parts.push({ key: 'mcq', full: Number(maxes.mcq_full) });
    if (maxes.practical_full != null) parts.push({ key: 'practical', full: Number(maxes.practical_full) });
    if (parts.length === 1) return [{ key: 'mark', full: parts[0].full }];
    if (parts.length > 1) return parts;
  }
  if (isSectionClass(classLevel)) return [{ key: 'mark', full: Number((subject && subject.full_marks) || 100) }];
  if (/ict/i.test(sName)) return [{ key: 'written', full: 25 }, { key: 'practical', full: 25 }];
  if (/^english/i.test(sName)) return [{ key: 'mark', full: Number((subject && subject.full_marks) || 100) }];
  if (LAB_SUBJECTS.some(l => sName.toLowerCase().includes(l.toLowerCase()))) {
    return [{ key: 'cq', full: 50 }, { key: 'mcq', full: 25 }, { key: 'practical', full: 25 }];
  }
  return [{ key: 'cq', full: 70 }, { key: 'mcq', full: 30 }];
}

function gradePaper(classLevel, row, subject, maxes) {
  const layout = layoutFor(classLevel, subject, maxes);
  const fullTotal = layout.reduce((s, c) => s + c.full, 0);
  if (row.absent) {
    return { total: 0, full: fullTotal, scaled: 0, letter_grade: 'F', grade_point: 0, absent: true, comp_fail: false };
  }
  const hasComponents = row.cq != null || row.mcq != null || row.practical != null || row.written != null;
  let total = 0, full = 0, compFail = false;
  if (layout.length === 1 || !hasComponents) {
    total = Number(row.marks != null ? row.marks : 0);
    full = Number(subject.full_marks || fullTotal || 100);
  } else {
    layout.forEach(c => {
      const v = Number(row[c.key] != null ? row[c.key] : 0);
      total += v;
      full += c.full;
      if (!componentPass(v, c.full)) compFail = true;
    });
  }
  const scaled = full > 0 ? +((total / full) * 100).toFixed(2) : 0;
  const g = getGrading(scaled);
  return {
    total, full, scaled,
    letter_grade: compFail ? 'F' : g.letter_grade,
    grade_point: compFail ? 0.0 : g.grade_point,
    absent: false, comp_fail: compFail
  };
}

async function computeResult(studentId, eventId) {
  const [[stu]] = await pool.query(
    `SELECT s.id, s.class_id, c.name AS class_name, c.group_name
     FROM students s JOIN classes c ON s.class_id = c.id WHERE s.id = ?`, [studentId]);
  if (!stu) return null;
  const cls = classLevelOf(stu.class_name);

  const [papers] = await pool.query(
    `SELECT m.*, e.subject_id, sub.name AS subject_name, sub.full_marks, sub.is_optional,
            sub.excluded_from_gpa, sub.cq_full, sub.mcq_full, sub.practical_full
     FROM marks m
     JOIN exams e ON m.exam_id = e.id
     JOIN subjects sub ON e.subject_id = sub.id
     WHERE m.student_id = ? AND e.event_id = ?
       AND e.class_id = ?`,
    [studentId, eventId, stu.class_id]
  );
  if (papers.length === 0) return null;

  // Per-student subject allocation (NCTB): drives 4th-subject + elective handling.
  const [mapRows] = await pool.query(
    'SELECT subject_id, is_mandatory, is_fourth_subject, is_elective FROM student_subjects WHERE student_id = ?',
    [studentId]
  );
  const subMap = new Map(mapRows.map(r => [r.subject_id, r]));
  const hasMap = mapRows.length > 0;

  const fams = {};
  papers.forEach(p => {
    const f = familyOf(p.subject_name);
    (fams[f] = fams[f] || []).push(p);
  });

  let failed = false, fourthAbsent = false, mainPoints = 0, mainCount = 0, fourthGp = null;
  const familyRows = [];

  for (const fam of Object.keys(fams)) {
    const rows = fams[fam];
    const subj0 = rows[0];
    if (subj0.excluded_from_gpa) continue;
    // A subject counts as the 4th subject only when the student's allocation says so.
    // Fallback for legacy records (no student_subjects row): subject marked optional.
    const isFourth = rows.some(r => {
      const m = subMap.get(r.subject_id);
      if (m) return !!m.is_fourth_subject;
      return hasMap ? false : !!r.is_optional;
    });
    const present = rows.filter(r => !r.absent);
    if (!present.length) {
      if (isFourth) fourthAbsent = true;
      familyRows.push({ subject: fam, total: 0, full: 0, scaled: 0, letter_grade: 'Absent', grade_point: 0, absent: true, is_optional: subj0.is_optional, papers: rows.map(r => r.subject_name) });
      continue;
    }
    let total = 0, full = 0, compFail = false;
    const paperDetails = [];
    rows.forEach(r => {
      if (r.absent) { full += Number(r.full_marks || 100); return; }
      const subjObj = { name: r.subject_name, full_marks: r.full_marks };
      const g = gradePaper(cls, r, subjObj, { cq_full: r.cq_full, mcq_full: r.mcq_full, practical_full: r.practical_full });
      total += g.total;
      full += g.full;
      if (g.letter_grade === 'F') compFail = true;
      paperDetails.push({
        subject_name: r.subject_name, marks: r.marks, cq: r.cq, mcq: r.mcq,
        practical: r.practical, written: r.written, absent: !!r.absent,
        letter_grade: g.letter_grade, grade_point: g.grade_point
      });
    });
    const scaled = full > 0 ? +((total / full) * 100).toFixed(2) : 0;
    const base = getGrading(scaled);
    const letter = compFail ? 'F' : base.letter_grade;
    const gp = compFail ? 0.0 : base.grade_point;
    if (letter === 'F' && !isFourth) failed = true;
    if (isFourth) {
      if (fourthGp == null || gp > fourthGp) fourthGp = gp;
    } else { mainPoints += gp; mainCount++; }
    familyRows.push({
      subject: fam, total, full, scaled, letter_grade: letter, grade_point: gp,
      absent: false, is_optional: subj0.is_optional,
      papers: rows.map(r => r.subject_name), paper_details: paperDetails
    });
  }

  if (!mainCount) return null;
  const optFams = Object.keys(fams).filter(f => fams[f].some(r => r.is_optional));
  if (!fourthAbsent && optFams.length && !fams[optFams[0]]) fourthAbsent = true;

  const totalGpaWithout4th = +(mainPoints / mainCount).toFixed(2);
  const gpa4thBonus = fourthGp != null ? +Math.max(0, fourthGp - 2).toFixed(2) : 0;
  const finalGpa = failed || fourthAbsent ? 0.0
    : Math.min(5.0, +((mainPoints + gpa4thBonus) / mainCount).toFixed(2));

  familyRows.sort((a, b) => (a.is_optional - b.is_optional) || a.subject.localeCompare(b.subject));

  return {
    student_id: studentId,
    total_gpa_without_4th: totalGpaWithout4th,
    gpa_4th_bonus: gpa4thBonus,
    final_gpa: finalGpa,
    result_status: failed ? 'FAILED' : (fourthAbsent ? 'ABSENT' : 'PASSED'),
    families: familyRows
  };
}

module.exports = { familyOf, getGrading, computeResult, gradePaper, layoutFor, classLevelOf };