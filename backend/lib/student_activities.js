'use strict';

// Optional, session-bounded activity feeds used by result transcript PDFs.
// Each feed is isolated because older deployments may not have every table.
async function loadStudentActivities(pool, { studentId, classId, eventId, year, to }) {
  const sessionYear = Number(year) || new Date().getFullYear();
  const from = `${sessionYear}-01-01`;
  const end = String(to || `${sessionYear}-12-31`).slice(0, 10);
  const activities = { from, to: end, attendance: [], daily_reports: [], uniform_reports: [], uniform_missing_count: 0, class_tests: [], homework: [] };
  const run = async (key, sql, params) => {
    try { const [rows] = await pool.query(sql, params); activities[key] = rows; }
    catch (_) { /* optional feed; result remains available */ }
  };
  await Promise.all([
    run('attendance', `SELECT date, session, status, final_state, remark FROM attendance
      WHERE student_id=? AND date BETWEEN ? AND ? ORDER BY date, session`, [studentId, from, end]),
    run('daily_reports', `SELECT report_date, subject_name, homework_status, learning_status, performance, uniform_brought, note
      FROM student_daily_reports WHERE student_id=? AND report_date BETWEEN ? AND ?
      ORDER BY report_date DESC, subject_name`, [studentId, from, end]),
    run('legacy_uniform_reports', `SELECT DISTINCT report_date, uniform_brought, note
      FROM student_daily_reports WHERE student_id=? AND report_date BETWEEN ? AND ?
        AND uniform_brought=FALSE ORDER BY report_date DESC`, [studentId, from, end]),
    run('uniform_reports', `SELECT report_date, 'Uniform' AS subject_name,
      CASE WHEN uniform_brought THEN 'এনেছে' ELSE 'আনেনি' END AS status, note
      FROM student_uniform_reports WHERE student_id=? AND report_date BETWEEN ? AND ?
      ORDER BY report_date DESC`, [studentId, from, end]),
    run('class_tests', `SELECT ev.name AS exam_name, ev.exam_kind, ev.year, su.name AS subject_name,
      mk.marks, mk.total, mk.absent FROM marks mk JOIN exams ex ON ex.id=mk.exam_id
      JOIN exam_events ev ON ev.id=ex.event_id JOIN subjects su ON su.id=ex.subject_id
      WHERE mk.student_id=? AND ev.year=? AND ev.id<>? AND ex.status='published'
      ORDER BY ev.created_at DESC, su.sort_order, su.name`, [studentId, sessionYear, eventId]),
    run('homework', `SELECT h.title, h.description, h.due_date, su.name AS subject_name
      FROM homework h LEFT JOIN subjects su ON su.id=h.subject_id
      WHERE h.class_id=? AND h.created_at BETWEEN ? AND ? ORDER BY h.created_at DESC, h.id DESC`, [classId, from, end]),
  ]);
  const currentUniformDates = new Set(activities.uniform_reports.map(row => String(row.report_date).slice(0, 10)));
  activities.uniform_reports.push(...activities.legacy_uniform_reports
    .filter(row => !currentUniformDates.has(String(row.report_date).slice(0, 10)))
    .map(row => ({ ...row, subject_name: 'Uniform', status: 'আনেনি' })));
  delete activities.legacy_uniform_reports;
  activities.uniform_reports.sort((a, b) => String(b.report_date).localeCompare(String(a.report_date)));
  const missingUniformDates = new Set([
    ...activities.daily_reports.filter(row => row.uniform_brought === false || row.uniform_brought === 0)
      .map(row => String(row.report_date).slice(0, 10)),
    ...activities.uniform_reports.filter(row => row.status === 'আনেনি')
      .map(row => String(row.report_date).slice(0, 10)),
  ]);
  activities.uniform_missing_count = missingUniformDates.size;
  // A locked fifth-period register is the authoritative end-of-day snapshot.
  // Students present in the morning with no departure row stayed through P5.
  try {
    const [stayed] = await pool.query(`SELECT m.date, 'p5' AS session, 'p5_stayed' AS status,
        NULL AS final_state, NULL AS remark
      FROM attendance m
      JOIN attendance_lock l ON l.class_id=? AND l.date=m.date AND l.session='p5' AND l.locked=1
      WHERE m.student_id=? AND m.session='morning' AND m.status='present'
        AND m.date BETWEEN ? AND ?
        AND NOT EXISTS (SELECT 1 FROM attendance p WHERE p.student_id=m.student_id
          AND p.date=m.date AND p.session='p5')`, [classId, studentId, from, end]);
    activities.attendance.push(...stayed);
    activities.attendance.sort((a, b) => String(a.date).localeCompare(String(b.date)) ||
      String(a.session).localeCompare(String(b.session)));
  } catch (_) { /* attendance-lock schema may be absent on older deployments */ }
  return activities;
}

module.exports = { loadStudentActivities };
