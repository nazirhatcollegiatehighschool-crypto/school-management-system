const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildStudentUpdate,
  toDatabaseBoolean,
  validateStudentProfileFields,
} = require('../lib/student_update');

test('student profile updates leave omitted fields untouched', () => {
  const update = buildStudentUpdate({ name: 'Updated Student', roll: 12 }, {});
  assert.deepEqual(update, { name: 'Updated Student', roll: 12 });
  assert.equal(Object.hasOwn(update, 'student_code'), false);
  assert.equal(Object.hasOwn(update, 'guardian_email'), false);
});

test('student profile updates can explicitly clear nullable fields', () => {
  const update = buildStudentUpdate({ dob: null, guardian_email: null }, {});
  assert.deepEqual(update, { dob: null, guardian_email: null });
});

test('saving a real birth registration number clears the temporary-number lock', () => {
  const update = buildStudentUpdate(
    { birth_cert_no: '20120101001234567' },
    {},
  );
  assert.equal(update.birth_cert_no, '20120101001234567');
  assert.equal(update.birth_cert_placeholder, false);
});

test('an unspecified student status is not overwritten with null', () => {
  const update = buildStudentUpdate({ status: null, name: 'Unchanged Status' }, {});
  assert.deepEqual(update, { name: 'Unchanged Status' });
});

test('profile update handles scholarship false and curriculum choices explicitly', () => {
  const update = buildStudentUpdate(
    { receives_scholarship: false, optional_subject: 'Agriculture' },
    { optional_subject: 'Agriculture', compulsory_subject: null },
  );
  assert.deepEqual(update, {
    receives_scholarship: false,
    optional_subject: 'Agriculture',
    compulsory_subject: null,
  });
});

test('boolean database fields are normalized to PostgreSQL booleans', () => {
  assert.equal(toDatabaseBoolean(true), true);
  assert.equal(toDatabaseBoolean(1), true);
  assert.equal(toDatabaseBoolean('true'), true);
  assert.equal(toDatabaseBoolean(false), false);
  assert.equal(toDatabaseBoolean(0), false);
  assert.equal(toDatabaseBoolean('false'), false);
});

test('student profile fields respect database text limits', () => {
  assert.deepEqual(validateStudentProfileFields({
    name: 'Student Name',
    address: 'A'.repeat(255),
    birth_cert_no: '1'.repeat(50),
  }), []);
  assert.deepEqual(validateStudentProfileFields({ address: 'A'.repeat(256) }), [
    'address cannot exceed 255 characters',
  ]);
});

test('student profile updates reject values incompatible with database columns', () => {
  assert.deepEqual(validateStudentProfileFields({
    gender: { value: 'Male' },
    receives_scholarship: 'yes',
    dob: 20260101,
  }), [
    'gender must be text',
    'dob must be a date string',
    'receives_scholarship must be a boolean',
  ]);
});
