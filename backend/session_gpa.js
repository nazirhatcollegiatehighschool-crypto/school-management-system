// ------------------------------------------------------------------
// Session GPA — folds several exam kinds into ONE session result.
//
// Each exam kind carries a weight_pct from exam_catalog (Q2: global %
// per kind, per band). For a student we take the most recent PUBLISHED
// event of each kind they have marks in, grade it with the existing
// single-event engine (computeResult), then take the weighted mean.
//
//   session_gpa = Σ (kind_gpa × weight_pct) / Σ (weight_pct used)
//
// Normalising by the weights actually available matters mid-session:
// after only CA and Half-Yearly the student still gets a meaningful
// number instead of being scaled down as if Annual were already zero.
// `coverage` reports how much of the full weight has data so callers
// (report cards) can label it "provisional" vs "final".
// ------------------------------------------------------------------

const pool = require('./db');
const { computeResult } = require('./grading');
const { loadCatalog, bandOfClass } = require('./exam_catalog');

/**
 * Session GPA for one student.
 * Returns {
 *   session_gpa, coverage, kinds:[{kind,event_id,event_name,gpa,weight_pct}],
 *   total_marks_obtained, total_marks_full, pass_all, families
 * } or null when the student has no graded published event in the session.
 */
async function sessionGpa(studentId, sessionId) {
  const [[stu]] = await pool.query(
    'SELECT id, class_id, name FROM students WHERE id=?', [studentId]);
  if (!stu) return null;

  const band = bandOfClass(
    (await pool.query('SELECT name FROM classes WHERE id=?', [stu.class_id]))[0][0]?.name
  );
  const cat = await loadCatalog();
  const weights = cat[band] || {};

  // Published events of this session in which the student actually has marks.
  const [evs] = await pool.query(
    `SELECT DISTINCT e.id, e.name, e.exam_kind, e.start_date
       FROM marks m
       JOIN exams x ON x.id = m.exam_id
       JOIN exam_events e ON e.id = x.event_id
      WHERE m.student_id = ? AND e.session_id = ? AND e.is_published = 1`,
    [studentId, sessionId]
  );
  const byKind = {};
  for (const e of evs) {
    if (!weights[e.exam_kind]) continue;            // ignore kinds outside the catalog
    const cur = byKind[e.exam_kind];
    const ts = new Date(e.start_date || 0).getTime() || 0;
    if (!cur || ts >= cur.ts) byKind[e.exam_kind] = { ...e, ts };
  }
  const kinds = Object.keys(byKind);
  if (kinds.length === 0) return null;

  let num = 0, den = 0;
  let obtained = 0, full = 0;
  let passAll = true;
  const familyRows = [];

  for (const kind of kinds) {
    const ev = byKind[kind];
    const r = await computeResult(studentId, ev.id);
    if (!r) continue;
    const w = Number(weights[kind] ? weights[kind].weight_pct : 0);
    num += Number(r.final_gpa || 0) * w;
    den += w;
    obtained += Number(r.total_marks || 0);
    full += Number(r.total_full || 0);
    if (r.result_status !== 'PASSED') passAll = false;
    for (const f of (r.families || [])) familyRows.push({ ...f, exam_kind: kind });
  }

  const totalWeight = Object.values(weights).reduce((s, w) => s + Number(w.weight_pct || 0), 0);
  return {
    session_gpa: den > 0 ? +(num / den).toFixed(2) : 0,
    coverage: totalWeight > 0 ? +(den / totalWeight).toFixed(2) : 0,
    kinds: kinds.map(k => {
      const ev = byKind[k];
      return {
        kind: k, event_id: ev.id, event_name: ev.name,
        weight_pct: Number(weights[k].weight_pct),
      };
    }),
    total_marks_obtained: +obtained.toFixed(2),
    total_marks_full: +full.toFixed(2),
    pass_all: passAll,
    families: familyRows,
  };
}

module.exports = { sessionGpa };
