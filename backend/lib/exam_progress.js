const pool = require('../db.js');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const csv = require('csv-parser');

// Entry Progress Tracking API
async function getEntryProgress(req, res) {
  try {
    const { event_id, class_id, teacher_id } = req.query;
    
    let where = 'WHERE 1=1';
    const params = [];
    
    if (event_id) {
      where += ' AND e.event_id = ?';
      params.push(event_id);
    }
    if (class_id) {
      where += ' AND e.class_id = ?';
      params.push(class_id);
    }
    if (teacher_id) {
      where += ' AND sub.teacher_id = ?';
      params.push(teacher_id);
    }
    
    const [progress] = await pool.query(
      `SELECT e.id AS exam_id, e.name, e.event_id, e.class_id, e.subject_id, e.status, e.entry_open, e.entry_deadline,
        c.name AS class_name, c.section, c.group_name,
        sub.name AS subject_name, sub.full_marks,
        u.name AS teacher_name,
        (SELECT COUNT(*) FROM marks m WHERE m.exam_id = e.id) AS entered_count,
        (SELECT COUNT(*) FROM students s WHERE s.class_id = e.class_id) AS student_count,
        ROUND(
          (SELECT COUNT(*) FROM marks m WHERE m.exam_id = e.id) * 100.0 / 
          NULLIF((SELECT COUNT(*) FROM students s WHERE s.class_id = e.class_id), 0)
        , 2) AS progress_pct
       FROM exams e
       JOIN classes c ON c.id = e.class_id
       JOIN subjects sub ON sub.id = e.subject_id
       LEFT JOIN users u ON u.id = sub.teacher_id
       ${where}
       ORDER BY c.name, c.section, sub.name`,
      params
    );
    
    res.json(progress);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
}

// Bulk Mark Import API
async function importMarks(req, res) {
  try {
    if (!req.file) return res.status(400).json({ error: 'CSV file required' });
    
    const { exam_id, component_mode } = req.body;
    if (!exam_id) return res.status(400).json({ error: 'exam_id required' });
    
    const [[exam]] = await pool.query('SELECT * FROM exams WHERE id=?', [exam_id]);
    if (!exam) return res.status(404).json({ error: 'Exam not found' });
    
    const [[sub]] = await pool.query('SELECT * FROM subjects WHERE id=?', [exam.subject_id]);
    if (!sub) return res.status(404).json({ error: 'Subject not found' });
    
    // Parse CSV
    const results = [];
    const errors = [];
    
    await new Promise((resolve, reject) => {
      fs.createReadStream(req.file.path)
        .pipe(csv())
        .on('data', (row) => results.push(row))
        .on('end', resolve)
        .on('error', reject);
    });
    
    // Validate and prepare records
    const records = [];
    for (let i = 0; i < results.length; i++) {
      const row = results[i];
      const student_code = String(row.student_code || row.Student_Code || row.code || '').trim();
      const roll = Number(row.roll || row.Roll || row.roll_no);
      const marks = row.marks !== undefined && row.marks !== '' ? Number(row.marks) : null;
      const cq = row.cq !== undefined && row.cq !== '' ? Number(row.cq) : null;
      const mcq = row.mcq !== undefined && row.mcq !== '' ? Number(row.mcq) : null;
      const practical = row.practical !== undefined && row.practical !== '' ? Number(row.practical) : null;
      const written = row.written !== undefined && row.written !== '' ? Number(row.written) : null;
      const ca = row.ca !== undefined && row.ca !== '' ? Number(row.ca) : null;
      const comment = row.comment || row.Comment || null;
      
      if (!student_code && !roll) {
        errors.push({ row: i + 1, error: 'student_code or roll required' });
        continue;
      }
      
      // Find student
      let student;
      if (student_code) {
        const [[s]] = await pool.query(
          'SELECT id FROM students WHERE student_code=? AND class_id=?',
          [student_code, exam.class_id]
        );
        student = s;
      } else if (roll) {
        const [[s]] = await pool.query(
          'SELECT id FROM students WHERE roll=? AND class_id=?',
          [roll, exam.class_id]
        );
        student = s;
      }
      
      if (!student) {
        errors.push({ row: i + 1, error: 'Student not found in this class' });
        continue;
      }
      
      // Validate marks
      const total = sub.full_marks || 100;
      if (marks !== null && (marks < 0 || marks > total)) {
        errors.push({ row: i + 1, error: `Marks ${marks} out of range (0-${total})` });
        continue;
      }
      
      if (component_mode) {
        const comps = { cq: sub.cq_full, mcq: sub.mcq_full, practical: sub.practical_full, written: sub.written_full, ca: sub.ca_full };
        for (const [comp, val] of Object.entries({ cq, mcq, practical, written, ca })) {
          if (val !== null && comps[comp] !== null && (val < 0 || val > comps[comp])) {
            errors.push({ row: i + 1, error: `${comp.toUpperCase()} ${val} out of range (0-${comps[comp]})` });
            break;
          }
        }
      }
      
      records.push({ student_id: student.id, marks, total, cq, mcq, practical, written, ca, comment });
    }
    
    if (!records.length) {
      return res.status(400).json({ error: 'No valid records', errors });
    }
    
    // Bulk upsert
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      
      for (const r of records) {
        const effectiveMarks = r.marks !== null ? r.marks : ((r.cq || 0) + (r.mcq || 0) + (r.practical || 0) + (r.written || 0) + (r.ca || 0));
        
        const [existing] = await conn.query('SELECT id, edit_until FROM marks WHERE student_id=? AND exam_id=?', [r.student_id, exam_id]);
        
        if (existing.length > 0) {
          const editUntil = existing[0].edit_until;
          const editable = editUntil && new Date(editUntil) > new Date();
          if (!editable) {
            throw Object.assign(new Error(`Mark for student ${r.student_id} is locked`), { status: 403 });
          }
          await conn.query(
            `UPDATE marks SET marks=?, total=?, cq=?, mcq=?, practical=?, written=?, ca=?, comment=?, recorded_by=?, recorded_at=NOW(), edit_until=DATE_ADD(NOW(), INTERVAL 5 HOUR) WHERE id=?`,
            [effectiveMarks, r.total, r.cq, r.mcq, r.practical, r.written, r.ca, r.comment, req.user.id, existing[0].id]
          );
        } else {
          await conn.query(
            `INSERT INTO marks (student_id, exam_id, marks, total, cq, mcq, practical, written, ca, comment, recorded_by, recorded_at, edit_until)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,NOW(),DATE_ADD(NOW(), INTERVAL 5 HOUR))`,
            [r.student_id, exam_id, effectiveMarks, r.total, r.cq, r.mcq, r.practical, r.written, r.ca, r.comment, req.user.id]
          );
        }
      }
      
      await conn.commit();
      res.json({ ok: true, imported: records.length, errors });
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
  finally {
    if (req.file) fs.unlinkSync(req.file.path);
  }
}

// Marksheet Template API
async function getMarksheetTemplate(req, res) {
  try {
    const [rows] = await pool.query('SELECT * FROM marksheet_templates ORDER BY is_default DESC, id');
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
}

async function saveMarksheetTemplate(req, res) {
  try {
    const { name, is_default, layout_json, grading_scale_json, branding_json } = req.body || {};
    if (!name) return res.status(400).json({ error: 'name required' });
    
    if (is_default) {
      await pool.query('UPDATE marksheet_templates SET is_default=0 WHERE is_default=1');
    }
    
    const [r] = await pool.query(
      `INSERT INTO marksheet_templates (name, is_default, layout_json, grading_scale_json, branding_json, created_by)
       VALUES (?,?,?,?,?,?)`
      , [name, is_default ? 1 : 0, JSON.stringify(layout_json), JSON.stringify(grading_scale_json), JSON.stringify(branding_json), req.user.id]
    );
    res.status(201).json({ id: r.insertId });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
}

// Exam Scheduling/Calendar API
async function getExamCalendar(req, res) {
  try {
    const { session_id, year, month } = req.query;
    
    let where = 'WHERE 1=1';
    const params = [];
    
    if (session_id) {
      where += ' AND e.session_id = ?';
      params.push(session_id);
    }
    if (year) {
      where += ' AND e.year = ?';
      params.push(year);
    }
    
    const [events] = await pool.query(
      `SELECT e.id, e.name, e.exam_kind, e.year, e.exam_date, e.result_date, e.is_published,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id = e.id) AS exam_count
       FROM exam_events e ${where} ORDER BY e.exam_date, e.id`,
      params
    );
    
    res.json(events);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
}

async function updateExamDates(req, res) {
  try {
    const { id } = req.params;
    const { exam_date, result_date, start_date } = req.body || {};
    
    const updates = [];
    const params = [];
    
    if (exam_date !== undefined) { updates.push('exam_date=?'); params.push(exam_date || null); }
    if (result_date !== undefined) { updates.push('result_date=?'); params.push(result_date || null); }
    if (start_date !== undefined) { updates.push('start_date=?'); params.push(start_date || null); }
    
    if (!updates.length) return res.status(400).json({ error: 'Nothing to update' });
    
    params.push(id);
    await pool.query(`UPDATE exam_events SET ${updates.join(', ')} WHERE id=?`, params);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
}

// Analytics API
async function getAnalytics(req, res) {
  try {
    const { event_id, class_id, session_id, compare_session_id } = req.query;
    
    // Overall pass % per class
    const [classStats] = await pool.query(
      `SELECT c.id, c.name, c.section, c.group_name,
        COUNT(DISTINCT s.id) AS total_students,
        COUNT(DISTINCT CASE WHEN r.result_status = 'PASSED' THEN s.id END) AS passed,
        ROUND(COUNT(DISTINCT CASE WHEN r.result_status = 'PASSED' THEN s.id END) * 100.0 / 
              NULLIF(COUNT(DISTINCT s.id), 0), 2) AS pass_pct,
        ROUND(AVG(r.final_gpa), 2) AS avg_gpa
       FROM classes c
       LEFT JOIN students s ON s.class_id = c.id
       LEFT JOIN results r ON r.student_id = s.id ${event_id ? 'AND r.exam_id = ' + event_id : ''}
       ${class_id ? 'WHERE c.id = ' + class_id : ''}
       GROUP BY c.id, c.name, c.section, c.group_name
       ORDER BY c.name, c.section`,
      []
    );
    
    // Subject-wise pass % per class
    const [subjectStats] = await pool.query(
      `SELECT c.id AS class_id, c.name AS class_name, c.section,
        sub.name AS subject_name,
        COUNT(DISTINCT s.id) AS total,
        COUNT(DISTINCT CASE WHEN r.final_gpa IS NOT NULL THEN s.id END) AS with_result,
        ROUND(AVG(r.final_gpa), 2) AS avg_gpa
       FROM classes c
       LEFT JOIN students s ON s.class_id = c.id
       LEFT JOIN exams e ON e.class_id = c.id ${event_id ? 'AND e.event_id = ' + event_id : ''}
       LEFT JOIN subjects sub ON sub.id = e.subject_id
       LEFT JOIN marks m ON m.exam_id = e.id AND m.student_id = s.id
       LEFT JOIN results r ON r.student_id = s.id ${event_id ? 'AND r.exam_id = ' + event_id : ''}
       ${class_id ? 'WHERE c.id = ' + class_id : ''}
       GROUP BY c.id, c.name, c.section, sub.name
       ORDER BY c.name, c.section, sub.name`,
      []
    );
    
    // Teacher workload
    const [teacherStats] = await pool.query(
      `SELECT u.id, u.name, u.phone,
        COUNT(DISTINCT sub.id) AS subject_count,
        COUNT(DISTINCT e.id) AS exam_count,
        COUNT(DISTINCT m.student_id) AS marks_entered
       FROM users u
       LEFT JOIN subjects sub ON sub.teacher_id = u.id
       LEFT JOIN exams e ON e.subject_id = sub.id ${event_id ? 'AND e.event_id = ' + event_id : ''}
       LEFT JOIN marks m ON m.exam_id = e.id
       WHERE u.role = 'teacher'
       GROUP BY u.id, u.name, u.phone
       ORDER BY marks_entered DESC`,
      []
    );
    
    res.json({ classStats, subjectStats, teacherStats });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
}

// Automated Workflows - Auto-create subject exams
async function autoCreateSubjectExams(req, res) {
  try {
    const { event_id } = req.body || {};
    if (!event_id) return res.status(400).json({ error: 'event_id required' });
    
    const [[ev]] = await pool.query('SELECT * FROM exam_events WHERE id=?', [event_id]);
    if (!ev) return res.status(404).json({ error: 'Event not found' });
    
    // Which classes this exam kind applies to:
    //   Test / Pre-Test        -> Class 10 only
    //   Annual / Half Yearly   -> Class 6, 7, 8, 9 (not Class 10)
    //   other / custom         -> classes already attached to the event,
    //                             else every class that has subjects.
    let classes = [];
    const kind = ev.exam_kind;
    if (kind === 'special_model_test') {
      [classes] = await pool.query(
        `SELECT DISTINCT id, name FROM classes WHERE name = 'SSC Batch' ORDER BY name`);
    } else if (kind === 'test' || kind === 'pretest') {
      [classes] = await pool.query(
        `SELECT DISTINCT id, name FROM classes WHERE name = 'Class 10' ORDER BY name`);
    } else if (kind === 'annual' || kind === 'half_yearly') {
      [classes] = await pool.query(
        `SELECT DISTINCT id, name FROM classes
         WHERE name IN ('Class 6','Class 7','Class 8','Class 9') ORDER BY name`);
    } else {
      [classes] = await pool.query(
        `SELECT DISTINCT c.id, c.name FROM classes c
         JOIN exams x ON x.class_id = c.id WHERE x.event_id = ? ORDER BY c.name`,
        [event_id]);
      if (!classes.length) {
        [classes] = await pool.query(
          `SELECT DISTINCT c.id, c.name FROM classes c
           JOIN subjects sub ON sub.class_id = c.id ORDER BY c.name`);
      }
    }
    
    let created = 0;
    for (const cls of classes) {
      const [subjects] = await pool.query(
        `SELECT s.id, s.name FROM subjects s WHERE s.class_id = ? ORDER BY s.name`,
        [cls.id]
      );
      
      for (const sub of subjects) {
        const [[existing]] = await pool.query(
          'SELECT id FROM exams WHERE event_id=? AND class_id=? AND subject_id=?',
          [event_id, cls.id, sub.id]
        );
        
        if (!existing) {
          const examType = ev.exam_kind && ['half_yearly', 'annual', 'pretest', 'test'].includes(ev.exam_kind) ? ev.exam_kind : 'class_test';
          await pool.query(
            `INSERT INTO exams (name, exam_type, class_id, subject_id, source, created_by, event_id, status, entry_open)
             VALUES (?,?,?,?,?,?,?,?,?)`,
            [`${ev.name} - ${sub.name}`, examType, cls.id, sub.id, 'admin', req.user.id, event_id, 'draft', 1]
          );
          created++;
        }
      }
    }

    // Record the event <-> class mapping (used by teacher/guardian gating).
    if (classes.length) {
      try {
        const vals = classes.map(() => '(?,?)').join(',');
        const params = [];
        for (const cls of classes) { params.push(Number(event_id), cls.id); }
        await pool.query(
          `INSERT IGNORE INTO exam_event_classes (event_id, class_id) VALUES ${vals}`, params);
      } catch (e) { /* table may not exist on older schema */ }
    }
    
    res.json({ ok: true, created, classes: classes.length });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
}

// Conflict Validation API
async function validateConflicts(req, res) {
  try {
    const { event_id } = req.query;
    if (!event_id) return res.status(400).json({ error: 'event_id required' });
    
    const conflicts = [];
    
    // 1. Missing subject exams for classes in event
    const [missingSubjects] = await pool.query(
      `SELECT c.id AS class_id, c.name, c.section, sub.name AS subject_name
       FROM classes c
       JOIN subjects sub ON sub.class_id = c.id
       LEFT JOIN exams e ON e.event_id = ? AND e.class_id = c.id AND e.subject_id = sub.id
       WHERE c.id IN (SELECT DISTINCT class_id FROM exams WHERE event_id = ?)
         AND e.id IS NULL
       ORDER BY c.name, sub.name`,
      [event_id, event_id]
    );
    if (missingSubjects.length) {
      conflicts.push({ type: 'missing_subject_exam', count: missingSubjects.length, details: missingSubjects });
    }
    
    // 2. Duplicate exams (same event, class, subject)
    const [duplicates] = await pool.query(
      `SELECT event_id, class_id, subject_id, COUNT(*) AS cnt
       FROM exams WHERE event_id = ? GROUP BY event_id, class_id, subject_id HAVING COUNT(*) > 1`,
      [event_id]
    );
    if (duplicates.length) {
      conflicts.push({ type: 'duplicate_exam', count: duplicates.length, details: duplicates });
    }
    
    // 3. Teacher conflicts (same teacher assigned to multiple subjects in same class)
    const [teacherConflicts] = await pool.query(
      `SELECT c.id AS class_id, c.name, c.section, u.name AS teacher_name, COUNT(*) AS subject_count
       FROM subjects s JOIN classes c ON c.id = s.class_id JOIN users u ON u.id = s.teacher_id
       WHERE s.teacher_id IS NOT NULL
       GROUP BY c.id, c.name, c.section, u.id, u.name
       HAVING COUNT(*) > 1
       ORDER BY c.name`,
      []
    );
    if (teacherConflicts.length) {
      conflicts.push({ type: 'teacher_multiple_subjects', count: teacherConflicts.length, details: teacherConflicts });
    }
    
    // 4. Classes with no students
    const [emptyClasses] = await pool.query(
      `SELECT c.id, c.name, c.section FROM classes c
       LEFT JOIN students s ON s.class_id = c.id
       WHERE c.id IN (SELECT DISTINCT class_id FROM exams WHERE event_id = ?)
       GROUP BY c.id, c.name, c.section
       HAVING COUNT(s.id) = 0`,
      [event_id]
    );
    if (emptyClasses.length) {
      conflicts.push({ type: 'empty_class', count: emptyClasses.length, details: emptyClasses });
    }
    
    // 5. Subjects with no assigned teacher
    const [unassignedSubjects] = await pool.query(
      `SELECT c.id AS class_id, c.name, c.section, sub.name AS subject_name
       FROM subjects sub JOIN classes c ON c.id = sub.class_id
       WHERE sub.teacher_id IS NULL
         AND c.id IN (SELECT DISTINCT class_id FROM exams WHERE event_id = ?)
       ORDER BY c.name, sub.name`,
      [event_id]
    );
    if (unassignedSubjects.length) {
      conflicts.push({ type: 'unassigned_subject', count: unassignedSubjects.length, details: unassignedSubjects });
    }
    
    res.json({ event_id, conflicts, has_conflicts: conflicts.length > 0 });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
}

module.exports = {
  getEntryProgress, importMarks, getMarksheetTemplate, saveMarksheetTemplate,
  getExamCalendar, updateExamDates, getAnalytics, autoCreateSubjectExams, validateConflicts
};