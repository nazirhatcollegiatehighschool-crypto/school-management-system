const pool = require('../db.js');

/**
 * Unified Exam Session Dashboard API
 * Returns complete exam session data for admin dashboard:
 * - Event info (canonical + custom)
 * - Class coverage with progress
 * - Subject exams per class with entry status
 * - Overall entry progress percentage
 */

async function getUnifiedExamDashboard(req, res) {
  try {
    const { session_id, published } = req.query;
    
    // Build WHERE clause
    const whereClauses = [];
    const params = [];
    
    if (session_id) {
      whereClauses.push('e.session_id = ?');
      params.push(session_id);
    }
    
    if (published === '1' || published === '0') {
      whereClauses.push('e.is_published = ?');
      params.push(Number(published));
    }
    
    const whereSql = whereClauses.length ? 'WHERE ' + whereClauses.join(' AND ') : '';
    
    // 1. Get all events with counts
    const [events] = await pool.query(
      `SELECT e.*, s.name AS session_name,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id = e.id) AS exam_count,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id = e.id AND x.status = 'published') AS published_count,
        (SELECT COUNT(DISTINCT x.class_id) FROM exams x WHERE x.event_id = e.id) AS class_count,
        (SELECT COUNT(DISTINCT m.student_id) FROM marks m JOIN exams x ON x.id = m.exam_id WHERE x.event_id = e.id) AS students_with_marks,
        (SELECT COUNT(*) FROM students s2 JOIN exams x ON x.class_id = s2.class_id WHERE x.event_id = e.id) AS total_students,
        (SELECT COUNT(*) FROM exams x WHERE x.event_id = e.id AND x.entry_open = 1 AND x.status <> 'published') AS entry_open_count,
        (SELECT MAX(x.entry_deadline) FROM exams x WHERE x.event_id = e.id) AS entry_deadline
       FROM exam_events e LEFT JOIN sessions s ON e.session_id = s.id
       ${whereSql}
       ORDER BY e.is_published ASC, (e.year IS NULL), e.year DESC, e.id DESC`,
      params
    );
    
    // 2. For each event, get detailed class coverage
    for (const ev of events) {
      const [classes] = await pool.query(
        `SELECT c.id AS class_id, c.name AS class_name, c.section, c.group_name,
          (SELECT COUNT(*) FROM students st WHERE st.class_id = c.id) AS student_count,
          (SELECT COUNT(DISTINCT m.student_id) FROM marks m JOIN exams x ON x.id = m.exam_id WHERE x.event_id = ? AND x.class_id = c.id) AS students_with_marks,
          (SELECT COUNT(*) FROM marks m JOIN exams x ON x.id = m.exam_id WHERE x.event_id = ? AND x.class_id = c.id) AS marks_count,
          (SELECT COUNT(*) FROM exams x WHERE x.event_id = ? AND x.class_id = c.id) AS subject_count,
          (SELECT COUNT(DISTINCT x.subject_id) FROM exams x JOIN marks m ON m.exam_id = x.id WHERE x.event_id = ? AND x.class_id = c.id) AS subjects_with_marks,
          (SELECT COUNT(*) FROM subjects sub WHERE sub.class_id = c.id) AS assigned_subjects,
          (SELECT COUNT(*) FROM subjects sub WHERE sub.class_id = c.id
            AND NOT EXISTS (SELECT 1 FROM exams x JOIN marks m ON m.exam_id = x.id
                            WHERE x.event_id = ? AND x.class_id = c.id AND x.subject_id = sub.id)) AS pending_subjects
         FROM classes c
         WHERE c.id IN (SELECT DISTINCT class_id FROM exams WHERE event_id = ?)
         ORDER BY c.name, c.section, c.group_name`,
        [ev.id, ev.id, ev.id, ev.id, ev.id, ev.id]
      );
      
      // 3. For each class, get subject exams with entry status
      for (const cls of classes) {
        const [subjects] = await pool.query(
          `SELECT x.id AS exam_id, x.name, x.exam_type, x.status, x.entry_open, x.entry_deadline, x.entry_status,
            sub.name AS subject_name, sub.full_marks, sub.cq_full, sub.mcq_full, sub.practical_full, sub.written_full, sub.ca_full,
            u.name AS subject_teacher_name,
            (SELECT COUNT(*) FROM marks m WHERE m.exam_id = x.id) AS entered_count,
            (SELECT COUNT(*) FROM students s WHERE s.class_id = ?) AS student_count
           FROM exams x JOIN subjects sub ON sub.id = x.subject_id
           LEFT JOIN users u ON u.id = sub.teacher_id
           WHERE x.event_id = ? AND x.class_id = ? ORDER BY sub.name`,
          [cls.class_id, ev.id, cls.class_id]
        );
        
        cls.subjects = subjects.map(s => ({
          ...s,
          entered_count: Number(s.entered_count),
          student_count: Number(s.student_count),
          submitted: Number(s.entered_count) > 0,
          exam_published: s.status === 'published',
          entry_open: s.entry_open == null ? 1 : Number(s.entry_open),
          components: [
            ...(s.cq_full != null ? [{ key: 'cq', label: 'CQ', full: Number(s.cq_full) }] : []),
            ...(s.mcq_full != null ? [{ key: 'mcq', label: 'MCQ', full: Number(s.mcq_full) }] : []),
            ...(s.practical_full != null ? [{ key: 'practical', label: 'Practical', full: Number(s.practical_full) }] : []),
            ...(s.written_full != null ? [{ key: 'written', label: 'Written', full: Number(s.written_full) }] : []),
            ...(s.ca_full != null ? [{ key: 'ca', label: 'CA', full: Number(s.ca_full) }] : []),
          ],
        }));
      }
      
      // Calculate progress
      classes.forEach(c => {
        const subjTotal = Math.max(Number(c.assigned_subjects || 0), Number(c.subject_count || 0));
        const subjDone = Number(c.subjects_with_marks || 0);
        const stuTotal = Number(c.student_count || 0);
        const stuDone = Number(c.students_with_marks || 0);
        c.subject_progress = subjTotal ? `${subjDone}/${subjTotal} Subject Marks Submitted` : '0/0';
        c.student_progress = stuTotal ? `${stuDone}/${stuTotal} Students Have Marks` : '0/0';
        c.subject_pct = subjTotal ? Math.round(subjDone / subjTotal * 100) : 0;
        c.student_pct = stuTotal ? Math.round(stuDone / stuTotal * 100) : 0;
        c.ready = subjTotal > 0 && subjDone >= subjTotal && stuTotal > 0 && stuDone >= stuTotal;
      });
      
      const eventReady = classes.some(c => c.ready) && classes
        .filter(c => Number(c.student_count || 0) > 0).every(c => c.ready);
      
      ev.classes = classes;
      ev.event_ready = eventReady;
    }
    
    res.json({ events, sessions: await pool.query('SELECT id, name, is_active FROM sessions ORDER BY name DESC').then(r => r[0]) });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
}

module.exports = { getUnifiedExamDashboard };
