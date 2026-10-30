const test = require('node:test');
const assert = require('node:assert/strict');
const { loadStudentActivities } = require('../lib/student_activities');

test('published Class Test names and marks are included in the student session activity feed', async () => {
  const queries = [];
  const pool = {
    async query(sql, params) {
      queries.push({ sql, params });
      if (sql.includes('FROM marks mk JOIN exams ex')) {
        return [[{
          exam_name: 'Class Test 2',
          exam_kind: 'other',
          year: 2026,
          subject_name: 'Mathematics',
          marks: 18,
          total: 25,
          absent: false,
        }]];
      }
      return [[]];
    },
  };

  const activities = await loadStudentActivities(pool, {
    studentId: 91,
    classId: 7,
    eventId: 42,
    year: 2026,
    to: '2026-11-12',
  });

  assert.deepEqual(activities.class_tests, [{
    exam_name: 'Class Test 2',
    exam_kind: 'other',
    year: 2026,
    subject_name: 'Mathematics',
    marks: 18,
    total: 25,
    absent: false,
  }]);
  const classTestQuery = queries.find(query => query.sql.includes('FROM marks mk JOIN exams ex'));
  assert.ok(classTestQuery.sql.includes("ex.status='published'"));
  assert.deepEqual(classTestQuery.params, [91, 2026, 42]);
});

test('uniform reports stay separate and missing days are counted once even for legacy rows', async () => {
  const pool = {
    async query(sql) {
      if (sql.includes('FROM student_uniform_reports')) return [[
        { report_date: '2026-06-01', subject_name: 'Uniform', status: 'এনেছে', note: null },
        { report_date: '2026-06-02', subject_name: 'Uniform', status: 'আনেনি', note: 'No uniform' },
      ]];
      if (sql.includes('legacy_uniform_reports') || sql.includes('SELECT DISTINCT report_date, uniform_brought')) return [[
        { report_date: '2026-06-02', uniform_brought: false, note: 'Old mixed report' },
        { report_date: '2026-06-03', uniform_brought: false, note: null },
      ]];
      if (sql.includes('FROM attendance m')) return [[]];
      return [[]];
    },
  };

  const activities = await loadStudentActivities(pool, {
    studentId: 91, classId: 7, eventId: 42, year: 2026, to: '2026-06-30',
  });

  assert.equal(activities.uniform_reports.length, 3);
  assert.equal(activities.uniform_missing_count, 2);
  assert.deepEqual(activities.uniform_reports.map(row => row.report_date), [
    '2026-06-03', '2026-06-02', '2026-06-01',
  ]);
  assert.equal(Object.hasOwn(activities, 'legacy_uniform_reports'), false);
});
