const router = require('express').Router();
const pool = require('../db');
const { auth } = require('../middleware/auth');

const DAYS = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
const DAY_KEYS = { Sunday: 0, Monday: 1, Tuesday: 2, Wednesday: 3, Thursday: 4 };

// ------------------------------------------------------------------
// helpers
// ------------------------------------------------------------------

async function hydrateRoutines(rows) {
  const out = [];
  for (const r of rows) {
    const [subjects] = await pool.query(
      'SELECT id, name, class_id, group_name, teacher_id, subject_code FROM subjects WHERE id = ?', [r.subject_id]
    );
    const [sections] = await pool.query(
      'SELECT rs.class_id, rs.section, c.name AS class_name FROM routine_sections rs JOIN classes c ON rs.class_id = c.id WHERE rs.routine_id = ? ORDER BY c.name, rs.section',
      [r.id]
    );
    const [groups] = await pool.query(
      'SELECT rg.class_id, rg.group_name, c.name AS class_name FROM routine_groups rg JOIN classes c ON rg.class_id = c.id WHERE rg.routine_id = ? ORDER BY c.name, rg.group_name',
      [r.id]
    );
    out.push({
      id: r.id,
      teacher_id: r.teacher_id,
      day: r.day,
      day_name: DAYS[r.day + 1],
      time_slot_id: r.time_slot_id,
      slot_order: r.slot_order,
      slot_label: r.slot_label,
      start_time: r.start_time,
      end_time: r.end_time,
      notes: r.notes,
      room: r.room,
      subject: subjects[0] || null,
      sections: sections,
      groups: groups
    });
  }
  return out;
}

async function getSlots() {
  const [rows] = await pool.query(
    'SELECT id, slot_order, label, start_time, end_time, is_break FROM time_slots ORDER BY slot_order'
  );
  return rows;
}

// Conflict check: same teacher assigned to two distinct classes at the same slot/day.
// A period is "merged" (allowed) when the classes are identical sets during merge — here
// we simply allow scheduling multiple classes in ONE routine entry (multi-section), and
// flag crossings where ANOTHER routine entry for the same teacher+day+slot exists unless
// it belongs to the same entry (grouped) or we are updating this entry.
async function findConflicts(teacherId, day, timeSlotId, excludeId) {
  const [rows] = await pool.query(
    `SELECT id, teacher_id, day, time_slot_id, subject_id
     FROM routines WHERE teacher_id = ? AND day = ? AND time_slot_id = ? AND id <> ?`,
    [teacherId, day, timeSlotId, excludeId || -1]
  );
  return rows;
}

// Subject assignment strictly follows the routine: a teacher stays assigned
// to a subject ONLY while at least one of their routine entries uses it.
// When the last such entry goes away, the subject is auto-unassigned.
async function unassignSubjectIfUnused(db, teacherId, subjectId) {
  if (!teacherId || !subjectId) return false;
  const [left] = await db.query(
    'SELECT id FROM routines WHERE teacher_id=? AND subject_id=? LIMIT 1',
    [teacherId, subjectId]);
  if (left.length > 0) return false;
  const [r] = await db.query(
    'UPDATE subjects SET teacher_id=NULL WHERE id=? AND teacher_id=?',
    [subjectId, teacherId]);
  return (r.affectedRows || 0) > 0;
}

// ------------------------------------------------------------------
// GET shared data (slots + subjects + classes) — used by all apps
// ------------------------------------------------------------------
router.get('/slots', auth(['admin', 'teacher']), async (req, res) => {
  try {
    res.json(await getSlots());
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ------------------------------------------------------------------
// TEACHER routes — manage own routine
// ------------------------------------------------------------------

router.get('/teacher/mine', auth('teacher'), async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT r.*, ts.slot_order, ts.label AS slot_label, ts.start_time, ts.end_time
       FROM routines r JOIN time_slots ts ON r.time_slot_id = ts.id
       WHERE r.teacher_id = ? ORDER BY r.day, ts.slot_order`,
      [req.user.id]
    );
    res.json(await hydrateRoutines(rows));
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/teacher', auth('teacher'), async (req, res) => {
  const { day, time_slot_id, subject_id, sections, groups, notes, room } = req.body || {};
  const dayNum = DAY_KEYS[day] ?? day;
  if (dayNum === undefined || dayNum === null || dayNum < 0 || dayNum > 4) {
    return res.status(400).json({ error: 'day must be Sunday..Thursday (0..4)' });
  }
  if (!time_slot_id || !subject_id) {
    return res.status(400).json({ error: 'time_slot_id and subject_id required' });
  }
  if ((!Array.isArray(sections) || sections.length === 0) && (!Array.isArray(groups) || groups.length === 0)) {
    return res.status(400).json({ error: 'At least one section or group required' });
  }
  try {
    const [subj] = await pool.query('SELECT id, class_id, teacher_id FROM subjects WHERE id = ?', [subject_id]);
    if (!subj[0]) return res.status(400).json({ error: 'Subject not found' });

    // auto-assign this subject to the teacher on their first pick
    if (!subj[0].teacher_id || Number(subj[0].teacher_id) !== Number(req.user.id)) {
      await pool.query('UPDATE subjects SET teacher_id = ? WHERE id = ?', [req.user.id, subject_id]);
    }

    // --- teacher pick: MULTI-section / MULTI-group is the primary flow ---
    // A NEW rule: same subject at the same (day, period) is NOT a conflict when the
    // second teacher is scheduling ADDITIONAL classes for THAT SAME subject (co-teaching /
    // combined class). This bypasses the hard block that previously returned 409.
    const [subjectInfo] = await pool.query(
      'SELECT id, name, class_id FROM subjects WHERE id = ?', [subject_id]);
    if (!subjectInfo[0]) return res.status(400).json({ error: 'Subject not found' });

    const ownBlocks = await findConflicts(req.user.id, dayNum, time_slot_id, null);
    const sameSubjectOnly = ownBlocks.filter(r => String(r.subject_id) === String(subject_id));
    const otherSubjects = ownBlocks.filter(r => String(r.subject_id) !== String(subject_id));
    // record is "combined with" when every existing own-block carries the SAME subject
    const isCombined = otherSubjects.length === 0 && sameSubjectOnly.length > 0;
    if (ownBlocks.length > 0 && !isCombined) {
      return res.status(409).json({ error: 'Conflict: another period already scheduled for this teacher at that time' });
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const [result] = await conn.query(
        'INSERT INTO routines (teacher_id, subject_id, day, time_slot_id, notes, room) VALUES (?,?,?,?,?,?)',
        [req.user.id, subject_id, dayNum, time_slot_id, notes || null, room || null]
      );
      const rid = result.insertId;
      for (const s of sections || []) {
        await conn.query('INSERT INTO routine_sections (routine_id, class_id, section) VALUES (?,?,?)',
          [rid, s.class_id, s.section]);
      }
      for (const g of groups || []) {
        await conn.query('INSERT INTO routine_groups (routine_id, class_id, group_name) VALUES (?,?,?)',
          [rid, g.class_id, g.group_name]);
      }
      await conn.commit();
      res.status(201).json({ id: rid });
    } catch (e) {
      await conn.rollback();
      res.status(500).json({ error: 'Server error' });
      return;
    } finally {
      conn.release();
    }
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/teacher/:id', auth('teacher'), async (req, res) => {
  const { day, time_slot_id, subject_id, sections, groups, notes, room } = req.body || {};
  const dayNum = DAY_KEYS[day] ?? day;
  try {
    const [own] = await pool.query('SELECT id, subject_id FROM routines WHERE id = ? AND teacher_id = ?', [req.params.id, req.user.id]);
    if (!own[0]) return res.status(403).json({ error: 'Not your routine entry' });
    const oldSubjectId = own[0].subject_id;
    const [subj] = await pool.query('SELECT id, class_id, teacher_id FROM subjects WHERE id = ?', [subject_id]);
    if (!subj[0]) return res.status(400).json({ error: 'Subject not found' });

    // auto-assign this subject to the teacher on their pick
    if (!subj[0].teacher_id || Number(subj[0].teacher_id) !== Number(req.user.id)) {
      await pool.query('UPDATE subjects SET teacher_id = ? WHERE id = ?', [req.user.id, subject_id]);
    }

    const conflicts = await findConflicts(req.user.id, dayNum, time_slot_id, Number(req.params.id));
    if (conflicts.length > 0) {
      return res.status(409).json({ error: 'Conflict: another period already scheduled for this teacher at that time' });
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      await conn.query(
        'UPDATE routines SET day=?, time_slot_id=?, subject_id=?, notes=?, room=? WHERE id=?',
        [dayNum, time_slot_id, subject_id, notes || null, room || null, req.params.id]
      );
      await conn.query('DELETE FROM routine_sections WHERE routine_id=?', [req.params.id]);
      await conn.query('DELETE FROM routine_groups WHERE routine_id=?', [req.params.id]);
      for (const s of sections || []) {
        await conn.query('INSERT INTO routine_sections (routine_id, class_id, section) VALUES (?,?,?)',
          [req.params.id, s.class_id, s.section]);
      }
      for (const g of groups || []) {
        await conn.query('INSERT INTO routine_groups (routine_id, class_id, group_name) VALUES (?,?,?)',
          [req.params.id, g.class_id, g.group_name]);
      }
      await conn.commit();
      // If the edit swapped to a different subject, the old one is no longer
      // in this teacher's routine -> unassign it when fully unused.
      let unassigned = false;
      if (Number(oldSubjectId) !== Number(subject_id)) {
        unassigned = await unassignSubjectIfUnused(pool, req.user.id, oldSubjectId);
      }
      res.json({ ok: true, subject_unassigned: unassigned });
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/teacher/:id', auth('teacher'), async (req, res) => {
  try {
    const [own] = await pool.query(
      `SELECT r.id, r.day, r.time_slot_id, s.name AS subject_name, u.name AS teacher_name
       FROM routines r JOIN subjects s ON r.subject_id = s.id
       JOIN users u ON r.teacher_id = u.id
       WHERE r.id = ? AND r.teacher_id = ?`, [req.params.id, req.user.id]);
    if (!own[0]) return res.status(403).json({ error: 'Not your routine entry' });

    const [pending] = await pool.query(
      `SELECT id FROM routine_delete_requests WHERE routine_id = ? AND status = 'pending'`, [req.params.id]);
    if (pending[0]) return res.status(409).json({ error: 'A delete request for this period is already pending approval' });

    const [sections] = await pool.query(
      `SELECT c.name AS class_name, rs.section FROM routine_sections rs JOIN classes c ON rs.class_id = c.id WHERE rs.routine_id = ?`, [req.params.id]);
    const [groups] = await pool.query(
      `SELECT c.name AS class_name, rg.group_name FROM routine_groups rg JOIN classes c ON rg.class_id = c.id WHERE rg.routine_id = ?`, [req.params.id]);
    const details = [
      ...sections.map(s => `${s.class_name} (${s.section})`),
      ...groups.map(g => `${g.class_name} (${g.group_name})`),
    ].join(', ');
    const classDetails = details || '—';

    const [rq] = await pool.query(
      `INSERT INTO routine_delete_requests (routine_id, teacher_id, subject_name, class_details, day, time_slot_id)
       VALUES (?,?,?,?,?,?)`,
      [req.params.id, req.user.id, own[0].subject_name, classDetails, own[0].day, own[0].time_slot_id]);

    await pool.query(
      `INSERT INTO notifications (title, body, type, target_type, created_by)
       VALUES (?,?,?,?,?)`,
      ['Routine delete approval needed',
       `${own[0].teacher_name} wants to remove: ${own[0].subject_name}${classDetails !== '—' ? ' — ' + classDetails : ''}. Review in the Routine page.`,
       'special', 'teacher', req.user.id]);

    res.status(202).json({ requested: true, id: rq.insertId });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/teacher/delete-requests', auth('teacher'), async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT id, routine_id, subject_name, class_details, day, time_slot_id, status, created_at, decided_at
       FROM routine_delete_requests WHERE teacher_id = ? ORDER BY id DESC LIMIT 50`, [req.user.id]);
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// shared insert-with-sections/groups used by admin create/update (teacher_id supplied)
async function insertRoutine(teacherId, subjectId, dayNum, timeSlotId, sections, groups, notes, room) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [result] = await conn.query(
      'INSERT INTO routines (teacher_id, subject_id, day, time_slot_id, notes, room) VALUES (?,?,?,?,?,?)',
      [teacherId, subjectId, dayNum, timeSlotId, notes || null, room || null]
    );
    const rid = result.insertId;
    for (const s of sections || []) {
      await conn.query('INSERT INTO routine_sections (routine_id, class_id, section) VALUES (?,?,?)', [rid, s.class_id, s.section]);
    }
    for (const g of groups || []) {
      await conn.query('INSERT INTO routine_groups (routine_id, class_id, group_name) VALUES (?,?,?)', [rid, g.class_id, g.group_name]);
    }
    await conn.commit();
    conn.release();
    return rid;
  } catch (e) {
    conn.release();
    throw e;
  }
}

router.post('/admin', auth('admin'), async (req, res) => {
  const { teacher_id, day, time_slot_id, subject_id, sections, groups, notes, room } = req.body || {};
  const dayNum = DAY_KEYS[day] ?? day;
  if (!teacher_id || dayNum === undefined || dayNum === null || dayNum < 0 || dayNum > 4) {
    return res.status(400).json({ error: 'teacher_id and day required (Sunday..Thursday 0..4)' });
  }
  if (!time_slot_id || !subject_id) {
    return res.status(400).json({ error: 'time_slot_id and subject_id required' });
  }
  if ((!Array.isArray(sections) || sections.length === 0) && (!Array.isArray(groups) || groups.length === 0)) {
    return res.status(400).json({ error: 'At least one section or group required' });
  }
  try {
    const [subj] = await pool.query('SELECT id FROM subjects WHERE id = ? AND teacher_id = ?', [subject_id, teacher_id]);
    if (!subj[0]) return res.status(400).json({ error: 'Subject is not assigned to that teacher' });
    const [tch] = await pool.query("SELECT id FROM users WHERE id = ? AND role='teacher'", [teacher_id]);
    if (!tch[0]) return res.status(400).json({ error: 'Teacher not found' });
    const conflicts = await findConflicts(teacher_id, dayNum, time_slot_id, null);
    if (conflicts.length > 0) {
      return res.status(409).json({ error: 'Conflict: another period already scheduled for that teacher at that time' });
    }
    const rid = await insertRoutine(teacher_id, subject_id, dayNum, time_slot_id, sections, groups, notes, room);
    res.status(201).json({ id: rid });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/admin/:id', auth('admin'), async (req, res) => {
  const { teacher_id, day, time_slot_id, subject_id, sections, groups, notes, room } = req.body || {};
  const dayNum = DAY_KEYS[day] ?? day;
  if (!teacher_id || dayNum === undefined || dayNum === null || dayNum < 0 || dayNum > 4) {
    return res.status(400).json({ error: 'teacher_id and day required (Sunday..Thursday 0..4)' });
  }
  try {
    const [subj] = await pool.query('SELECT id FROM subjects WHERE id = ? AND teacher_id = ?', [subject_id, teacher_id]);
    if (!subj[0]) return res.status(400).json({ error: 'Subject is not assigned to that teacher' });
    const conflicts = await findConflicts(teacher_id, dayNum, time_slot_id, Number(req.params.id));
    if (conflicts.length > 0) {
      return res.status(409).json({ error: 'Conflict: another period already scheduled for that teacher at that time' });
    }
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      await conn.query(
        'UPDATE routines SET teacher_id=?, day=?, time_slot_id=?, subject_id=?, notes=?, room=? WHERE id=?',
        [teacher_id, dayNum, time_slot_id, subject_id, notes || null, room || null, req.params.id]
      );
      await conn.query('DELETE FROM routine_sections WHERE routine_id=?', [req.params.id]);
      await conn.query('DELETE FROM routine_groups WHERE routine_id=?', [req.params.id]);
      for (const s of sections || []) {
        await conn.query('INSERT INTO routine_sections (routine_id, class_id, section) VALUES (?,?,?)', [req.params.id, s.class_id, s.section]);
      }
      for (const g of groups || []) {
        await conn.query('INSERT INTO routine_groups (routine_id, class_id, group_name) VALUES (?,?,?)', [req.params.id, g.class_id, g.group_name]);
      }
      await conn.commit();
      conn.release();
      res.json({ ok: true });
    } catch (e) {
      conn.release();
      res.status(500).json({ error: 'Server error' });
    }
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// teacher subject list with class info (for the routine subject dropdown)
router.get('/teacher/subjects', auth('teacher'), async (req, res) => {
  try {
    // every subject of every class — the teacher may pick any subject; it is
    // auto-assigned to them on saving the period (see teacher POST/PUT above).
    const [rows] = await pool.query(
      `SELECT sub.id, sub.name, sub.class_id, sub.group_name, sub.teacher_id,
              c.name AS class_name, c.section, c.group_name AS class_group
       FROM subjects sub JOIN classes c ON sub.class_id = c.id
       ORDER BY c.name, c.section, sub.name`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/admin/delete-requests', auth('admin'), async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT d.*, u.name AS teacher_name
       FROM routine_delete_requests d JOIN users u ON d.teacher_id = u.id
       ORDER BY (d.status = 'pending') DESC, d.id DESC LIMIT 200`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/admin/delete-requests/:id/approve', auth('admin'), async (req, res) => {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [rq] = await conn.query('SELECT * FROM routine_delete_requests WHERE id = ? FOR UPDATE', [req.params.id]);
    if (!rq[0]) { await conn.rollback(); return res.status(404).json({ error: 'Request not found' }); }
    if (rq[0].status !== 'pending') { await conn.rollback(); return res.status(400).json({ error: 'Request already ' + rq[0].status }); }
    const [gone] = await conn.query('SELECT teacher_id, subject_id FROM routines WHERE id = ?', [rq[0].routine_id]);
    await conn.query('DELETE FROM routine_sections WHERE routine_id = ?', [rq[0].routine_id]);
    await conn.query('DELETE FROM routine_groups WHERE routine_id = ?', [rq[0].routine_id]);
    await conn.query('DELETE FROM routines WHERE id = ?', [rq[0].routine_id]);
    let unassigned = false;
    if (gone[0]) unassigned = await unassignSubjectIfUnused(conn, gone[0].teacher_id, gone[0].subject_id);
    await conn.query("UPDATE routine_delete_requests SET status = 'approved', decided_at = now() WHERE id = ?", [rq[0].id]);
    await conn.commit();
    conn.release();
    res.json({ ok: true, subject_unassigned: unassigned });
  } catch (e) {
    try { await conn.rollback(); } catch (_) {}
    conn.release();
    console.error(e);
    res.status(500).json({ error: 'Server error' });
  }
});

router.post('/admin/delete-requests/:id/reject', auth('admin'), async (req, res) => {
  try {
    const [rq] = await pool.query('SELECT * FROM routine_delete_requests WHERE id = ?', [req.params.id]);
    if (!rq[0]) return res.status(404).json({ error: 'Request not found' });
    if (rq[0].status !== 'pending') return res.status(400).json({ error: 'Request already ' + rq[0].status });
    await pool.query("UPDATE routine_delete_requests SET status = 'rejected', decided_at = now() WHERE id = ?", [rq[0].id]);
    res.json({ ok: true, routine_id: rq[0].routine_id });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ------------------------------------------------------------------
// ADMIN routes — full routine matrix + management + aliases + time slots
// ------------------------------------------------------------------

router.get('/all', auth('admin'), async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT r.*, ts.slot_order, ts.label AS slot_label, ts.start_time, ts.end_time,
              u.name AS teacher_name
       FROM routines r
       JOIN time_slots ts ON r.time_slot_id = ts.id
       LEFT JOIN users u ON r.teacher_id = u.id
       ORDER BY r.day, ts.slot_order, u.name`
    );
    const sessions = await hydrateRoutines(rows);
    const [teachers] = await pool.query(
      "SELECT id, name, username FROM users WHERE role='teacher' ORDER BY name"
    );
    res.json({ routines: sessions, teachers, slots: await getSlots() });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.get('/conflicts', auth('admin'), async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT r.teacher_id, u.name AS teacher_name, r.day, r.time_slot_id,
              ts.label AS slot_label, ts.start_time, ts.end_time,
              COUNT(*) AS cnt
       FROM routines r
       JOIN time_slots ts ON r.time_slot_id = ts.id
       JOIN users u ON r.teacher_id = u.id
       GROUP BY r.teacher_id, u.name, r.day, r.time_slot_id, ts.label, ts.start_time, ts.end_time
       HAVING COUNT(*) > 1
       ORDER BY r.day, r.time_slot_id, u.name`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// admin can delete any routine entry
router.delete('/admin/:id', auth('admin'), async (req, res) => {
  try {
    const [gone] = await pool.query('SELECT teacher_id, subject_id FROM routines WHERE id=?', [req.params.id]);
    if (!gone[0]) return res.status(404).json({ error: 'Routine entry not found' });
    await pool.query('DELETE FROM routine_sections WHERE routine_id=?', [req.params.id]);
    await pool.query('DELETE FROM routine_groups WHERE routine_id=?', [req.params.id]);
    await pool.query('DELETE FROM routines WHERE id=?', [req.params.id]);
    const unassigned = await unassignSubjectIfUnused(pool, gone[0].teacher_id, gone[0].subject_id);
    res.json({ ok: true, subject_unassigned: unassigned });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ---- time slots CRUD ----
router.get('/admin/slots', auth('admin'), async (req, res) => {
  try { res.json(await getSlots()); } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/admin/slots', auth('admin'), async (req, res) => {
  const { slot_order, label, start_time, end_time, is_break } = req.body || {};
  if (!slot_order || !label) return res.status(400).json({ error: 'slot_order and label required' });
  try {
    const [result] = await pool.query(
      'INSERT INTO time_slots (slot_order, label, start_time, end_time, is_break) VALUES (?,?,?,?,?)',
      [slot_order, label, start_time || null, end_time || null, is_break ? 1 : 0]
    );
    res.status(201).json({ id: result.insertId });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/admin/slots/:id', auth('admin'), async (req, res) => {
  const { slot_order, label, start_time, end_time, is_break } = req.body || {};
  try {
    await pool.query(
      'UPDATE time_slots SET slot_order=?, label=?, start_time=?, end_time=?, is_break=? WHERE id=?',
      [slot_order, label, start_time || null, end_time || null, is_break ? 1 : 0, req.params.id]
    );
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/admin/slots/:id', auth('admin'), async (req, res) => {
  try {
    await pool.query('DELETE FROM time_slots WHERE id=?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ---- subject aliases ----
router.get('/admin/aliases', auth(['admin', 'teacher']), async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT sa.*, s.name AS subject_name, c.name AS class_name
       FROM subject_aliases sa
       JOIN subjects s ON sa.subject_id = s.id
       LEFT JOIN classes c ON sa.class_id = c.id
       ORDER BY s.name, sa.field_value`
    );
    res.json(rows);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/admin/aliases', auth('admin'), async (req, res) => {
  const { subject_id, alias_name, student_field, field_value, class_id } = req.body || {};
  if (!subject_id || !alias_name || !field_value) return res.status(400).json({ error: 'subject_id, alias_name, field_value required' });
  try {
    const [result] = await pool.query(
      'INSERT INTO subject_aliases (subject_id, alias_name, student_field, field_value, class_id) VALUES (?,?,?,?,?)',
      [subject_id, alias_name, student_field || 'religion', field_value, class_id || null]
    );
    res.status(201).json({ id: result.insertId });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.put('/admin/aliases/:id', auth('admin'), async (req, res) => {
  const { alias_name, field_value } = req.body || {};
  try {
    await pool.query('UPDATE subject_aliases SET alias_name=?, field_value=? WHERE id=?',
      [alias_name, field_value, req.params.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.delete('/admin/aliases/:id', auth('admin'), async (req, res) => {
  try {
    await pool.query('DELETE FROM subject_aliases WHERE id=?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

// ------------------------------------------------------------------
// GUARDIAN / STUDENT route — personalised routine with subject aliasing
// ------------------------------------------------------------------

router.get('/student', auth('guardian'), async (req, res) => {
  try {
    const [links] = await pool.query(
      "SELECT student_id FROM guardian_links WHERE guardian_id = ? OR EXISTS (SELECT 1 FROM students st WHERE st.id = guardian_links.student_id AND st.guardian_id = ?)",
      [req.user.id, req.user.id]
    );
    const studentIds = links.map(l => l.student_id);
    if (studentIds.length === 0) {
      // fallback: any student whose guardian_id matches this user
      const [direct] = await pool.query('SELECT id FROM students WHERE guardian_id = ?', [req.user.id]);
      direct.forEach(s => studentIds.push(s.id));
    }
    if (studentIds.length === 0) return res.status(404).json({ error: 'No linked students' });
    const [students] = await pool.query(
      'SELECT id, name, religion, class_id FROM students WHERE id IN (?) ORDER BY id', [studentIds]
    );
    const out = [];
    for (const st of students) {
      const [cls] = await pool.query('SELECT section, group_name FROM classes WHERE id = ?', [st.class_id]);
      const sec = cls[0]?.section;
      const grp = cls[0]?.group_name;
      const [routines] = await pool.query(
        `SELECT DISTINCT r.*, ts.slot_order, ts.label AS slot_label, ts.start_time, ts.end_time
         FROM routines r
         JOIN time_slots ts ON r.time_slot_id = ts.id
         LEFT JOIN routine_sections rs ON rs.routine_id = r.id
         LEFT JOIN routine_groups rg ON rg.routine_id = r.id
         WHERE (rs.class_id = ? AND rs.section = ?) OR (rg.class_id = ? AND rg.group_name = ?)
         ORDER BY ts.slot_order`,
        [st.class_id, sec, st.class_id, grp]
      );
      const hydrated = await hydrateRoutinesForStudent(routines, st, st.class_id);
      out.push({ student: st, routine: hydrated });
    }
    res.json(out);
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

async function hydrateRoutinesForStudent(rows, student, classId) {
  const out = [];
  for (const r of rows) {
    const [subjects] = await pool.query(
      'SELECT id, name, group_name FROM subjects WHERE id = ?', [r.subject_id]
    );
    const subj = subjects[0];
    let displayName = subj ? subj.name : 'Unknown';
    if (subj) {
      const [aliases] = await pool.query(
        `SELECT alias_name FROM subject_aliases
         WHERE subject_id = ? AND student_field = 'religion' AND field_value = ?
           AND (class_id IS NULL OR class_id = ?)
         ORDER BY (CASE WHEN class_id IS NULL THEN 1 ELSE 0 END) LIMIT 1`,
        [subj.id, student.religion || '', classId]
      );
      if (aliases[0]) displayName = aliases[0].alias_name;
    }
    out.push({
      id: r.id,
      day: r.day,
      day_name: DAYS[r.day + 1],
      time_slot_id: r.time_slot_id,
      slot_order: r.slot_order,
      slot_label: r.slot_label,
      start_time: r.start_time,
      end_time: r.end_time,
      subject: { id: r.subject_id, name: displayName, base_name: subj?.name }
    });
  }
  return out;
}

module.exports = router;