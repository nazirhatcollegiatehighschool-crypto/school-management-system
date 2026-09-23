/* Central input validation helpers — server-side data integrity */

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

module.exports = { validateMarksValue, validateStudent };