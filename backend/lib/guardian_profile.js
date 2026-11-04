'use strict';

const COMPLETION_FIELDS = [
  'name', 'dob', 'birth_cert_no', 'religion', 'receives_scholarship',
  'guardian_name', 'guardian_phone', 'father_name', 'mother_name',
  'address', 'gender', 'blood_group',
];

function buildCompletionUpdate(clean, dob) {
  const assignments = [];
  const params = [];
  for (const key of COMPLETION_FIELDS) {
    if (clean[key] === undefined) continue;
    assignments.push(`${key}=?`);
    params.push(key === 'receives_scholarship'
      ? Boolean(clean[key])
      : key === 'dob'
        ? dob.toISOString().slice(0, 10)
        : String(clean[key]).trim());
  }
  // Bind booleans, rather than integer literals: PostgreSQL uses BOOLEAN and
  // the local MariaDB mirror stores the same fields as TINYINT(1).
  assignments.push('birth_cert_placeholder=?');
  params.push(false);
  assignments.push('guardian_profile_locked_at=NOW()');
  return { assignments, params };
}

module.exports = { COMPLETION_FIELDS, buildCompletionUpdate };
