const test = require('node:test');
const assert = require('node:assert/strict');
const { studentMatchesSubject, isReligionSubject, defaultClassCurriculum } = require('../lib/subject_access');

test('optional subject students only match their enrolled subject', () => {
  assert.equal(studentMatchesSubject({ optional_subject: 'Home Science' }, 'Home Science'), true);
  assert.equal(studentMatchesSubject({ optional_subject: 'Agriculture' }, 'Home Science'), false);
  assert.equal(studentMatchesSubject({ compulsory_subject: 'Economics' }, 'Economics'), true);
  assert.equal(studentMatchesSubject({ compulsory_subject: 'Civics' }, 'Economics'), false);
  assert.equal(studentMatchesSubject({ optional_subject: null, compulsory_subject: null }, 'Home Science'), false);
  assert.equal(studentMatchesSubject({ optional_subject: 'Higher Mathematics' }, 'Home Science'), false);
  assert.equal(studentMatchesSubject({ optional_subject: 'Agriculture' }, 'Home Science'), false);
  assert.equal(studentMatchesSubject({ optional_subject: 'Home Science' }, 'Agriculture'), false);
});

test('Class 9-10 untouched curriculum uses gender and group defaults', () => {
  const arts = { class_name: 'Class 10', group_name: 'Arts' };
  const commerce = { class_name: 'Class 9', section: 'Commerce' };
  const science = { class_name: 'Class 10', group_name: 'Science' };
  assert.equal(studentMatchesSubject({ optional_subject: null, gender: 'Female' }, 'Home Science', arts), true);
  assert.equal(studentMatchesSubject({ optional_subject: null, gender: 'Male' }, 'Agriculture', commerce), true);
  assert.equal(studentMatchesSubject({ optional_subject: null, gender: 'Female' }, 'Agriculture', commerce), false);
  assert.equal(studentMatchesSubject({ optional_subject: null, gender: 'Male' }, 'Higher Mathematics', science), true);
  assert.equal(studentMatchesSubject({ optional_subject: null, gender: 'Female' }, 'Higher Mathematics', science), true);
  assert.equal(studentMatchesSubject({ optional_subject: null, gender: 'Other' }, 'Higher Mathematics', science), false);
  assert.equal(studentMatchesSubject({ optional_subject: null, gender: 'Female' }, 'Economics', arts), true);
});

test('religion subjects match canonical religion values', () => {
  assert.equal(isReligionSubject('Islam and Moral Education'), true);
  assert.equal(studentMatchesSubject({ religion: 'Islam' }, 'Islam and Moral Education'), true);
  assert.equal(studentMatchesSubject({ religion: 'Muslim' }, 'Islam and Moral Education'), true);
  assert.equal(studentMatchesSubject({ religion: 'Hinduism' }, 'Islam and Moral Education'), false);
  assert.equal(studentMatchesSubject({ religion: 'Hindu' }, 'Hindu Dharma'), true);
});
