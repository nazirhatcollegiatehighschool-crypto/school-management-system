const router = require('express').Router();
const pool = require('../db');
const { auth } = require('../middleware/auth');
const { computeResult } = require('../grading');
const PDFDocument = require('pdfkit');

// Result computation, tabulation and marksheets are school-wide admin operations.
// Teachers enter marks through /api/teacher — they must NOT compute/tabulate
// arbitrary classes or read arbitrary student marksheets.
router.use(auth('admin'));

router.get('/events', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT e.*, s.name AS session_name,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id = e.id) AS exam_count
       FROM exam_events e LEFT JOIN sessions s ON e.session_id = s.id
       ORDER BY e.id DESC`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/events', async (req, res) => {
  const { name, session_id, start_date } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name required' });
  try {
    const [result] = await pool.query(
      'INSERT INTO exam_events (name, session_id, start_date, created_by) VALUES (?,?,?,?)',
      [name, session_id || 1, start_date || null, req.user.id]
    );
    res.status(201).json({ id: result.insertId });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/events/:id', async (req, res) => {
  try {
    await pool.query('UPDATE exams SET event_id=NULL WHERE event_id=?', [req.params.id]);
    await pool.query('DELETE FROM exam_events WHERE id=?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/events/:id', async (req, res) => {
  const { name, session_id, start_date } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name required' });
  try {
    await pool.query(
      'UPDATE exam_events SET name=?, session_id=?, start_date=? WHERE id=?',
      [name, session_id || 1, start_date || null, req.params.id]
    );
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/results/compute', async (req, res) => {
  const { event_id, class_id } = req.body || {};
  if (!event_id || !class_id) return res.status(400).json({ error: 'event_id and class_id required' });
  try {
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
    res.json({ ok: true, students: students.length, computed, with_marks: withMarks });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

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
        final_gpa: r ? r.final_gpa : stu.final_gpa,
        result_status: r ? r.result_status : stu.result_status
      });
    }
    const subjects = Array.from(famSet);
    rows.forEach((row, i) => { row._families = subjects.map(s => row.families[s] || null); });
    const ranked = [...rows].filter(x => x.final_gpa != null).sort((a, b) =>
      b.final_gpa - a.final_gpa ||
      rows.reduce((s, x) => s + (x.families ? 0 : 0), 0));
    rows.forEach(row => {
      row.position = null;
    });
    const sortedForRank = [...rows].filter(r => r.final_gpa != null && r.result_status === 'PASSED')
      .sort((a, b) => b.final_gpa - a.final_gpa);
    sortedForRank.forEach((r, i) => { r.position = i + 1; });
    res.json({ subjects, rows });
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
      'SELECT teacher_remarks FROM results WHERE student_id=? AND exam_id=?',
      [student.id, req.params.eventId]
    );
    const [settingsRows] = await pool.query('SELECT setting_key, setting_value FROM app_settings');
    const settings = {};
    settingsRows.forEach(s => { settings[s.setting_key] = s.setting_value; });
    res.json({ student, event, result, remarks: saved ? saved.teacher_remarks : null, settings });
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