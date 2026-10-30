const test = require('node:test');
const assert = require('node:assert/strict');
const { routineSubjectScopeSql } = require('../lib/teacher_routine_access');

test('routine access requires the teacher, subject, and exact class scope', () => {
  const scope = routineSubjectScopeSql();

  assert.match(scope, /teacher_routine\.teacher_id = \?/);
  assert.match(scope, /teacher_routine\.subject_id = sub\.id/);
  assert.match(scope, /teacher_routine_section\.class_id = c\.id/);
  assert.match(scope, /teacher_routine_section\.section = c\.section/);
  assert.match(scope, /teacher_routine_group\.class_id = c\.id/);
  assert.match(scope, /teacher_routine_group\.group_name = c\.group_name/);
});

test('routine access scope supports explicit aliases for each exam query', () => {
  const scope = routineSubjectScopeSql({ classAlias: 'cls', subjectAlias: 'subject' });

  assert.match(scope, /teacher_routine\.subject_id = subject\.id/);
  assert.match(scope, /teacher_routine_section\.class_id = cls\.id/);
  assert.match(scope, /teacher_routine_group\.group_name = cls\.group_name/);
});
