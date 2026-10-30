const test = require('node:test');
const assert = require('node:assert/strict');
const {
  decideByGrace,
  decidePromotionByGrace,
  normalizeSubjectFamily,
} = require('../lib/promotion_grace');

test('mandatory failures on selected grace subjects are auto-approved; optional failures are ignored', () => {
  const result = decideByGrace({
    selectedSubjectNames: ['Bangla 1st'],
    families: [
      { subject: 'Bangla', letter_grade: 'F', is_optional: false },
      { subject: 'Higher Mathematics', letter_grade: 'F', is_optional: true },
      { subject: 'English', letter_grade: 'A', is_optional: false },
    ],
  });
  assert.equal(result.status, 'approved');
  assert.equal(result.autoGrace, true);
  assert.deepEqual(result.graceFailed, ['Bangla']);
});

test('any unselected mandatory failure stays in the classwise review queue', () => {
  const result = decideByGrace({
    selectedSubjectNames: ['Bangla'],
    families: [
      { subject: 'Bangla', letter_grade: 'F', is_optional: false },
      { subject: 'English', letter_grade: 'F', is_optional: false },
    ],
  });
  assert.equal(result.status, 'not_eligible');
  assert.equal(result.autoGrace, false);
  assert.deepEqual(result.ungracedFailed, ['English']);
});

test('a passing student remains eligible for the normal promotion review', () => {
  const result = decideByGrace({
    selectedSubjectNames: [],
    families: [{ subject: 'Bangla', letter_grade: 'A', is_optional: false }],
  });
  assert.equal(result.status, 'eligible');
  assert.equal(result.autoGrace, false);
});

test('paper variants map to the same subject family', () => {
  assert.equal(normalizeSubjectFamily('Bangla 1st'), normalizeSubjectFamily('Bangla'));
  assert.equal(normalizeSubjectFamily('English Second'), normalizeSubjectFamily('English'));
});

test('an absent student cannot be promoted by the event grace rule', () => {
  const result = decidePromotionByGrace({
    selectedSubjectNames: [],
    resultStatus: 'ABSENT',
    families: [{ subject: 'Bangla', letter_grade: 'A', is_optional: false }],
  });
  assert.equal(result.status, 'not_eligible');
  assert.equal(result.decision, 'retained');
  assert.equal(result.eligible, false);
  assert.equal(result.autoGrace, false);
});

test('an empty result cannot be promoted as an all-pass result', () => {
  const result = decidePromotionByGrace({
    selectedSubjectNames: [],
    resultStatus: 'ABSENT',
    families: [],
  });
  assert.equal(result.status, 'not_eligible');
  assert.equal(result.decision, 'retained');
});
