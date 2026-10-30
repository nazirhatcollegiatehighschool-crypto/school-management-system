const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeClassInput, validateClassInput } = require('../lib/class_management');

test('partial class edits preserve the existing group and teacher assignment', () => {
  const value = normalizeClassInput(
    { section: 'B' },
    { name: 'Class 9', section: 'A', group_name: 'Science', teacher_id: 12 },
  );
  assert.deepEqual(value, {
    name: 'Class 9', section: 'B', group_name: 'Science', teacher_id: 12,
  });
  assert.deepEqual(validateClassInput(value), []);
});

test('classes 9 and 10 require a supported academic group', () => {
  const missing = normalizeClassInput({ name: 'Class 10', section: 'A' });
  assert.match(validateClassInput(missing).join(' '), /require.*group/i);
  const typo = normalizeClassInput({
    name: 'Class 9', section: 'A', group_name: 'NonScience',
  });
  assert.match(validateClassInput(typo).join(' '), /require.*group/i);

  const valid = normalizeClassInput({
    name: 'Class 10', section: 'A', group_name: 'Humanities', teacher_id: '4',
  });
  assert.deepEqual(validateClassInput(valid), []);
  assert.equal(valid.teacher_id, 4);
});

test('class names, sections, and teacher IDs are validated before writes', () => {
  const invalid = normalizeClassInput({
    name: 'X'.repeat(31), section: 'A'.repeat(21), teacher_id: 'not-an-id',
  });
  const errors = validateClassInput(invalid).join(' ');
  assert.match(errors, /Class name must be 30/);
  assert.match(errors, /Section must be 20/);
  assert.match(errors, /valid class teacher/);
});
