const test = require('node:test');
const assert = require('node:assert/strict');
const { getGrading, gradePaper, layoutFor } = require('../grading');

test('SSC letter-grade thresholds follow the board 0-5 scale', () => {
  assert.deepEqual(getGrading(80), { letter_grade: 'A+', grade_point: 5.0 });
  assert.deepEqual(getGrading(70), { letter_grade: 'A', grade_point: 4.0 });
  assert.deepEqual(getGrading(60), { letter_grade: 'A-', grade_point: 3.5 });
  assert.deepEqual(getGrading(50), { letter_grade: 'B', grade_point: 3.0 });
  assert.deepEqual(getGrading(40), { letter_grade: 'C', grade_point: 2.0 });
  assert.deepEqual(getGrading(33), { letter_grade: 'D', grade_point: 1.0 });
  assert.deepEqual(getGrading(32.99), { letter_grade: 'F', grade_point: 0.0 });
});

test('Class 9-10 component marks require a pass in each component', () => {
  const subject = { name: 'Physics', full_marks: 100 };
  const layout = layoutFor(10, subject, {
    cq_full: 50,
    mcq_full: 25,
    practical_full: 25,
  });
  assert.deepEqual(layout, [
    { key: 'cq', full: 50 },
    { key: 'mcq', full: 25 },
    { key: 'practical', full: 25 },
  ]);

  const failedComponent = gradePaper(
    10,
    { marks: 67, cq: 16, mcq: 25, practical: 25 },
    subject,
    { cq_full: 50, mcq_full: 25, practical_full: 25 },
  );
  assert.equal(failedComponent.letter_grade, 'F');
  assert.equal(failedComponent.grade_point, 0);

  const passedComponents = gradePaper(
    10,
    { marks: 35, cq: 17, mcq: 10, practical: 8 },
    subject,
    { cq_full: 50, mcq_full: 25, practical_full: 25 },
  );
  assert.equal(passedComponents.letter_grade, 'D');
  assert.equal(passedComponents.grade_point, 1);
});

test('Class 9-10 theory components apply 23/70 and 10/30 pass marks', () => {
  const subject = { name: 'General Science', full_marks: 100 };
  const layout = { cq_full: 70, mcq_full: 30 };
  const fail = gradePaper(10, { marks: 33, cq: 22, mcq: 30 }, subject, layout);
  assert.equal(fail.letter_grade, 'F');
  assert.equal(fail.grade_point, 0);

  const pass = gradePaper(10, { marks: 33, cq: 23, mcq: 10 }, subject, layout);
  assert.equal(pass.letter_grade, 'D');
  assert.equal(pass.grade_point, 1);
});
