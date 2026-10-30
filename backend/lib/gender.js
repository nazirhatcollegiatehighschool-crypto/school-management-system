'use strict';

// Normalize a free-text gender value to the canonical DB spelling
// (Male / Female / Other). Guards against typos such as 'femal' that
// previously slipped in through free-text inputs and broke filters.
const GENDER_MAP = new Map([
  ['male', 'Male'],
  ['m', 'Male'],
  ['female', 'Female'],
  ['femal', 'Female'],
  ['females', 'Female'],
  ['femail', 'Female'],
  ['girl', 'Female'],
  ['other', 'Other'],
]);

function normalizeGender(value) {
  const v = (value ?? '').toString().trim();
  if (!v) return null;
  const hit = GENDER_MAP.get(v.toLowerCase());
  if (hit) return hit;
  // Accept exact canonical spellings in any casing; keep unknown values
  // as-is (trimmed) so existing data is never silently rewritten.
  const lower = v.toLowerCase();
  for (const canonical of ['Male', 'Female', 'Other']) {
    if (canonical.toLowerCase() === lower) return canonical;
  }
  return v;
}

module.exports = { normalizeGender };
