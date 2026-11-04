const test = require('node:test');
const assert = require('node:assert/strict');
const { buildCompletionUpdate } = require('../lib/guardian_profile');

test('guardian profile completion binds PostgreSQL boolean fields as booleans', () => {
  const dob = new Date('2015-04-03T00:00:00.000Z');
  const update = buildCompletionUpdate({
    name: 'Test Student',
    dob: '2015-04-03',
    receives_scholarship: true,
    birth_cert_no: '1234567890',
  }, dob);

  assert.deepEqual(update.assignments, [
    'name=?', 'dob=?', 'birth_cert_no=?', 'receives_scholarship=?',
    'birth_cert_placeholder=?', 'guardian_profile_locked_at=NOW()',
  ]);
  assert.deepEqual(update.params, [
    'Test Student', '2015-04-03', '1234567890', true, false,
  ]);
  assert.equal(typeof update.params[3], 'boolean');
  assert.equal(typeof update.params[4], 'boolean');
});

test('guardian profile completion retains an explicit no-scholarship value', () => {
  const update = buildCompletionUpdate({ receives_scholarship: false }, new Date());
  assert.deepEqual(update.assignments, [
    'receives_scholarship=?', 'birth_cert_placeholder=?', 'guardian_profile_locked_at=NOW()',
  ]);
  assert.deepEqual(update.params, [false, false]);
});
