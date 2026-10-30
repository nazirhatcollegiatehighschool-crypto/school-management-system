const test = require('node:test');
const assert = require('node:assert/strict');
const pool = require('../db');
const { eventPublishGate } = require('../routes/results');

test('publication gate includes unopened subjects in required coverage', async () => {
  const originalQuery = pool.query;
  const queries = [];
  pool.query = async (sql) => {
    queries.push(sql);
    if (sql.startsWith('SELECT exam_kind, session_id, year')) {
      return [[{ exam_kind: 'annual', session_id: 1, year: 2026 }], null];
    }
    if (sql.includes('SELECT c.id, c.name, c.section')) {
      return [[{
        id: 7,
        name: 'Class 10',
        section: 'A',
        students: 2,
        students_done: 1,
        subjects: 3,
        subjects_done: 2,
        not_approved: 0,
      }], null];
    }
    throw new Error('Unexpected publication-gate query');
  };

  try {
    const missing = await eventPublishGate(42);
    const gateQuery = queries[1];

    assert.doesNotMatch(gateQuery, /entry_open\s*=\s*1/);
    assert.deepEqual(missing, [{
      class_id: 7,
      class_name: 'Class 10 (A)',
      gaps: ['1 subject-এর marks বাকি', '1 জন student-এর marks বাকি'],
    }]);
  } finally {
    pool.query = originalQuery;
  }
});
