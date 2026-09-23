/*
 * NCTB subject reseed — cleanup + official class-wise structure
 * ==============================================================
 * 1. Deletes ALL existing subjects (cascade removes exams/marks/ct_marks/
 *    homework/routines that referenced them).
 * 2. Preserves: teacher->subject assignments (via name match),
 *    per-student subject allocations (student_subjects, name match),
 *    Religion aliases (subject_aliases rebuilt -> Religion & Moral Education).
 * 3. Inserts official NCTB structure:
 *    - Class 6-8 (General track)  : 13 subjects / class
 *    - Class 9-10 + SSC Batch   : core(9) + track + optional 4th pool
 *      Science: +BGS,Physics,Chemistry,Biology  -> 16 (4th: Agric, HomeSci, HigherMath)
 *      Commerce:+GenSci,Accounting,Finance&Banking,BusinessEnt -> 15 (4th: Agric, HomeSci)
 *      Arts:    +GenSci,Hist&WorldCiv,Geography,Economics*,Civics* -> 16 (4th: Agric, HomeSci)
 *      (* = elective pool). Higher Mathematics is a 4th-pool subject for the
 *      SCIENCE track ONLY (not Commerce/Arts).
 *
 * Usage:  MSYS_NO_PATHCONV=1 DATABASE_URL='<pg conn>' DB_SSL=false \
 *         node seed_nctb_subjects.js
 */
const { Pool } = require('pg');
const p = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DB_SSL === 'false' ? false : { rejectUnauthorized: false },
});

// subject spec: [name, subject_code, full_marks, cq, mcq, practical]
const CORE_68 = [
  ['Bangla 1st', 101, 100, 70, 30, null],
  ['Bangla 2nd', 102, 100, 70, 30, null],
  ['English 1st', 107, 100, 70, 30, null],
  ['English 2nd', 108, 100, 70, 30, null],
  ['Mathematics', 109, 100, 70, 30, null],
  ['Science', 127, 100, 70, 30, null],
  ['Information and Communication Technology (ICT)', 174, 100, 70, 30, null],
  ['Bangladesh & Global Studies', 110, 100, 70, 30, null],
  ['Work & Life-Oriented Education', null, 100, 70, 30, null],
  ['Physical Education & Health', null, 100, 70, 30, null],
  ['Arts & Crafts', null, 100, 70, 30, null],
  ['Agriculture Studies', null, 100, 70, 30, null],
  ['Religion & Moral Education', 111, 100, 70, 30, null],
];

const T9_CORE = [
  ['Bangla 1st', 101, 100, 70, 30, null],
  ['Bangla 2nd', 102, 100, 70, 30, null],
  ['English 1st', 107, 100, 70, 30, null],
  ['English 2nd', 108, 100, 70, 30, null],
  ['Mathematics', 109, 100, 70, 30, null],
  ['Information and Communication Technology (ICT)', 174, 100, 70, 30, null],
  ['Religion & Moral Education', 111, 100, 70, 30, null],
  ['Physical Education & Health', null, 100, 70, 30, null],
  ['Career Education', null, 100, 70, 30, null],
];

const SCIENCE_EXTRA = [
  ['Bangladesh & Global Studies', 110, 100, 70, 30, null],
  ['Physics', 136, 100, 50, 25, 25],
  ['Chemistry', 137, 100, 50, 25, 25],
  ['Biology', 138, 100, 50, 25, 25],
];
const ARTS_EXTRA = [
  ['General Science', 127, 100, 70, 30, null],
  ['History of Bangladesh & World Civilization', 153, 100, 70, 30, null],
  ['Geography & Environment', null, 100, 70, 30, null],
  ['Economics', 141, 100, 70, 30, null],
  ['Civics & Citizenship', 140, 100, 70, 30, null],
];
const COMMERCE_EXTRA = [
  ['General Science', 127, 100, 70, 30, null],
  ['Accounting', 142, 100, 70, 30, null],
  ['Finance & Banking', 144, 100, 70, 30, null],
  ['Business Entrepreneurship', 143, 100, 70, 30, null],
];
const FOURTH_POOL = [
  ['Agriculture Studies', null, 100, 70, 30, null],
  ['Home Science', null, 100, 70, 30, null],
];
// Higher Mathematics is a 4th-pool subject for the SCIENCE track only.
const FOURTH_POOL_SCIENCE = [
  ...FOURTH_POOL,
  ['Higher Mathematics', 139, 100, 70, 30, null],
];

const ELECTIVE_NAMES = new Set(['Economics', 'Civics & Citizenship']);

// old subject name -> new name when the brand changed
function renameOld(oldName, hasGroup) {
  if (oldName === 'General Science' && !hasGroup) return 'Science';
  if (oldName === 'Religion' || oldName === 'Religion & Moral Education') return 'Religion & Moral Education';
  if (oldName === 'ICT') return 'Information and Communication Technology (ICT)';
  return oldName;
}

(async () => {
  const client = await p.connect();
  try {
    await client.query('BEGIN');

    // ----- snapshot data needed for preserve/remap -----
    const oldSS = (await client.query(
      `SELECT ss.student_id, s.id AS subject_id, s.name, s.class_id, ss.is_mandatory,
              ss.is_fourth_subject, ss.is_elective, ss.assigned_by
       FROM student_subjects ss JOIN subjects s ON ss.subject_id = s.id`
    )).rows;
    const oldTeacher = (await client.query(
      `SELECT id, class_id, name, teacher_id FROM subjects WHERE teacher_id IS NOT NULL`
    )).rows;
    const countsBefore = (await client.query(
      `SELECT (SELECT count(*) FROM subjects) subjects,
              (SELECT count(*) FROM student_subjects) student_subjects,
              (SELECT count(*) FROM subject_aliases) aliases,
              (SELECT count(*) FROM exams) exams,
              (SELECT count(*) FROM marks) marks,
              (SELECT count(*) FROM ct_marks) ct_marks,
              (SELECT count(*) FROM homework) homework,
              (SELECT count(*) FROM routines) routines`
    )).rows[0];

    // ----- CLEANUP -----
    await client.query('DELETE FROM subject_aliases');
    await client.query('DELETE FROM student_subjects');
    await client.query('DELETE FROM subjects'); // cascades exams/marks/ct_marks/homework/routines

    // ----- classes -----
    const classes = (await client.query(
      'SELECT id, name, section, group_name FROM classes ORDER BY id'
    )).rows;

    // ----- INSERT -----
    const insertSubj = `INSERT INTO subjects
      (name, class_id, full_marks, group_name, is_optional, excluded_from_gpa,
       cq_full, mcq_full, practical_full, subject_code, is_fourth_subject, is_elective, sort_order)
      VALUES ($1,$2,$3,$4,$5,0,$6,$7,$8,$9,$10,$11,$12)`;
    let inserted = 0;
    for (const c of classes) {
      const track = c.group_name ? String(c.group_name) : 'Compulsory';
      let list;
      if (!c.group_name) list = CORE_68;
      else {
        const extras = track === 'Science' ? SCIENCE_EXTRA
          : track === 'Commerce' ? COMMERCE_EXTRA
          : ARTS_EXTRA;
        const pool = track === 'Science' ? FOURTH_POOL_SCIENCE : FOURTH_POOL;
        list = [...T9_CORE, ...extras, ...pool];
      }
      let order = 0;
      for (const [name, code, full, cq, mcq, pr] of list) {
        const tracked = !!c.group_name;
        const isCore = tracked && order < T9_CORE.length;
        const isPool = tracked && (FOURTH_POOL.some(f => f[0] === name) || FOURTH_POOL_SCIENCE.some(f => f[0] === name));
        const isElective = tracked && ELECTIVE_NAMES.has(name);
        const grp = isCore ? 'Compulsory' : track;
        await client.query(insertSubj, [
          name, c.id, full, grp, isPool || isElective ? 1 : 0,
          cq, mcq, pr, code, isPool ? 1 : 0, isElective ? 1 : 0, order,
        ]);
        order++;
        inserted++;
      }
    }

    // ----- preserve teacher->subject assignments (name match) -----
    const newSubjects = (await client.query(
      'SELECT id, class_id, name FROM subjects'
    )).rows;
    const byClassAndName = new Map();
    for (const s of newSubjects) {
      const k = `${s.class_id}|${s.name}`;
      byClassAndName.set(k, s.id);
    }
    let assigned = 0;
    for (const s of oldTeacher) {
      const cls = classes.find(c => c.id === s.class_id);
      const hasGroup = !!(cls && cls.group_name);
      const target = renameOld(s.name, hasGroup);
      const id = byClassAndName.get(`${s.class_id}|${target}`);
      if (id != null) {
        await client.query('UPDATE subjects SET teacher_id = $1 WHERE id = $2', [s.teacher_id, id]);
        assigned++;
      }
    }

    // ----- preserve per-student subject allocations -----
    let keptSS = 0, droppedSS = 0;
    for (const r of oldSS) {
      const cls = classes.find(c => c.id === r.class_id);
      const hasGroup = !!(cls && cls.group_name);
      const target = renameOld(r.name, hasGroup);
      const id = byClassAndName.get(`${r.class_id}|${target}`);
      if (id == null) { droppedSS++; continue; }
      await client.query(
        `INSERT INTO student_subjects (student_id, subject_id, is_mandatory, is_fourth_subject, is_elective, assigned_by)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [r.student_id, id, r.is_mandatory, r.is_fourth_subject, r.is_elective, r.assigned_by]
      );
      keptSS++;
    }

    // ----- rebuild Religion aliases for every class's Religion & Moral Education subject -----
    let aliases = 0;
    for (const s of newSubjects) {
      if (s.name !== 'Religion & Moral Education') continue;
      for (const [field, alias] of [['Islam', 'Islam & Moral Education'], ['Hindu', 'Hindu Religion & Moral Education']]) {
        await client.query(
          `INSERT INTO subject_aliases (subject_id, alias_name, student_field, field_value, class_id)
           VALUES ($1,$2,'religion',$3,$4)`,
          [s.id, alias, field, s.class_id]
        );
        aliases++;
      }
    }

    // ----- reset sequence -----
    const maxId = (await client.query('SELECT COALESCE(MAX(id),1) m FROM subjects')).rows[0].m;
    await client.query(`SELECT setval(pg_get_serial_sequence('subjects','id'), $1)`, [maxId]);

    await client.query('COMMIT');

    // ----- report -----
    const classes68 = classes.filter(c => !c.group_name);
    const tracked = classes.filter(c => c.group_name);
    const perClass = (await client.query(
      `SELECT c.name, c.section, c.group_name, count(s.id) n FROM classes c
       LEFT JOIN subjects s ON s.class_id = c.id GROUP BY c.id ORDER BY c.id`
    )).rows;
    const teachersStill = (await client.query(
      `SELECT count(*) n FROM users t WHERE role='teacher' AND EXISTS (
         SELECT 1 FROM subjects s WHERE s.teacher_id = t.id)`
    )).rows[0].n;
    const subjectsByTeacher = (await client.query(
      `SELECT t.id, t.name AS teacher, count(s.id) n FROM users t
       LEFT JOIN subjects s ON s.teacher_id = t.id
       WHERE t.role='teacher'
       GROUP BY t.id ORDER BY t.id`
    )).rows;

    console.log('=== BEFORE (wiped) ===');
    console.table(countsBefore);
    console.log('=== AFTER ===');
    console.log('subjects inserted:', inserted);
    console.log('classes 6-8 per row:', perClass.filter(r => !r.group_name).map(r => `${r.name} ${r.section}=${r.n}`).join(', '));
    console.log('tracked classes:', perClass.filter(r => r.group_name).map(r => `${r.name} ${r.section}=${r.n}`).join(', '));
    console.log('teachers with >=1 subject now:', teachersStill);
    console.log('student_subjects kept:', keptSS, 'dropped:', droppedSS);
    console.log('aliases inserted:', aliases);
    console.log('=== subjects per teacher ===');
    console.table(subjectsByTeacher);
    console.log('=== Class 6 A sample ===');
    console.table((await client.query(
      `SELECT id, name, is_optional, is_fourth_subject, is_elective, sort_order, teacher_id FROM subjects WHERE class_id=1 ORDER BY sort_order`
    )).rows);
    console.log('=== Class 9 Science sample ===');
    console.table((await client.query(
      `SELECT id, name, group_name, is_optional, is_fourth_subject, is_elective, sort_order FROM subjects WHERE class_id=10 ORDER BY sort_order`
    )).rows);
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('FAILED (rolled back):', e);
    process.exit(1);
  } finally {
    client.release();
    await p.end();
  }
})();