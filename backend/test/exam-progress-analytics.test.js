const test = require('node:test');
const assert = require('node:assert/strict');
const pool = require('../db');
const { getAnalytics } = require('../lib/exam_progress');

test('class analytics join each result to the class represented by its marks', async () => {
  const originalQuery = pool.query;
  const queries = [];
  pool.query = async (sql) => {
    queries.push(sql);
    if (sql.startsWith('SELECT id,name FROM sessions')) {
      return [[{ id: 1, name: '2026' }], null];
    }
    if (sql.includes('SELECT DISTINCT e.id AS event_id')) return [[], null];
    if (sql.includes('SELECT e.id AS event_id,e.name AS exam_name')) return [[], null];
    if (sql.includes('COUNT(DISTINCT r.student_id) AS students')) return [[], null];
    throw new Error('Unexpected analytics query');
  };
  const response = {
    json(body) {
      this.body = body;
      return this;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
  };

  try {
    await getAnalytics({ query: { session_id: '1' } }, response);
    const classStatsQuery = queries.at(-1);
    assert.match(classStatsQuery, /SELECT DISTINCT x\.event_id,x\.class_id,m\.student_id/);
    assert.match(classStatsQuery, /x\.student_id=r\.student_id/);
  } finally {
    pool.query = originalQuery;
  }
});
