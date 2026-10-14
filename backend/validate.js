/* Central input validation helpers — server-side data integrity */

// NCTB component validation: each component (CQ/MCQ/Practical/Written/CA)
// is validated against its own full marks; the plain `marks` total is
// validated against the subject/event total. All fields optional —
// the teacher fills whichever structure the admin configured.
function validateComponentValue(v, full, label) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  const f = Number(full);
  if (!Number.isFinite(n)) return `${label} must be a number`;
  if (n < 0) return `${label} cannot be negative`;
  if (Number.isFinite(f) && f > 0 && n > f) return `${label} cannot exceed ${f}`;
  return null;
}

function validateMarksRecord(r, layout) {
  const errs = [];
  const totalFull = layout && layout.full_marks != null
    ? Number(layout.full_marks)
    : Number(r.total !== undefined && r.total !== null && r.total !== '' ? r.total : 100);
  const labels = { cq: 'CQ', mcq: 'MCQ', practical: 'Practical', written: 'Written', ca: 'CA (ধারাবাহিক)' };
  const comps = ['cq', 'mcq', 'practical', 'written', 'ca'];
  let hasAnyComponent = false;
  for (const k of comps) {
    if (r[k] !== undefined && r[k] !== null && r[k] !== '') {
      hasAnyComponent = true;
      const fullKey = k + '_full';
      const full = layout && layout[fullKey] != null ? Number(layout[fullKey]) : null;
      const e = validateComponentValue(r[k], full, labels[k]);
      if (e) errs.push(`Student ${r.student_id}: ${e}`);
    }
  }
  // Component-wise records: sum must not exceed the subject total.
  if (hasAnyComponent) {
    const sum = comps.reduce((s, k) => s + (r[k] === undefined || r[k] === null || r[k] === '' ? 0 : Number(r[k])), 0);
    if (Number.isFinite(totalFull) && totalFull > 0 && sum > totalFull) {
      errs.push(`Student ${r.student_id}: component total ${sum} exceeds subject total (${totalFull})`);
    }
  } else {
    const e = validateMarksValue(r.marks, totalFull);
    if (e) errs.push(`Student ${r.student_id}: ${e}`);
  }
  if (r.comment && String(r.comment).length > 255) errs.push('Comment too long (max 255)');
  return errs;
}

function validateMarksValue(marks, total) {
  const m = Number(marks);
  const t = Number(total || 100);
  if (!Number.isFinite(m)) return 'Marks must be a number';
  if (m < 0) return 'Marks cannot be negative';
  if (m > t) return `Marks cannot exceed total (${t})`;
  if (!Number.isFinite(t) || t <= 0) return 'Total must be a positive number';
  return null;
}

function validateStudent(body) {
  const errors = [];
  if (body.roll !== undefined) {
    const r = Number(body.roll);
    if (!Number.isInteger(r) || r < 1 || r > 999) errors.push('Roll must be between 1 and 999');
  }
  if (body.name !== undefined && (!String(body.name).trim() || String(body.name).length > 100)) {
    errors.push('Name is required (max 100 chars)');
  }
  if (body.guardian_phone && !/^[0-9+\-\s]{6,20}$/.test(String(body.guardian_phone))) {
    errors.push('Invalid phone number');
  }
  if (body.dob && isNaN(Date.parse(body.dob))) errors.push('Invalid date of birth');
  return errors;
}

module.exports = { validateMarksValue, validateComponentValue, validateMarksRecord, validateStudent };