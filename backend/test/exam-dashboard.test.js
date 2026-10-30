const test = require('node:test');
const assert = require('node:assert/strict');
const pool = require('../db');
const { getUnifiedExamDashboard } = require('../lib/exam_dashboard');

async function runDashboard(sessions, eventStates) {
  const originalQuery = pool.query;
  const queries = [];
  pool.query = async (sql, params) => {
    queries.push({ sql, params });
    if (sql.startsWith('SELECT id, name, is_active FROM sessions')) {
      return [sessions, null];
    }
    if (sql.startsWith('SELECT name FROM sessions')) {
      return [[{ name: '2026' }], null];
    }
    if (sql.includes('SELECT e.year, e.exam_kind')) {
      return [eventStates, null];
    }
    if (sql.includes('SELECT e.*, s.name AS session_name')) {
      return [[], null];
    }
    throw new Error('Unexpected dashboard query');
  };

  const response = {
    json(data) {
      this.body = data;
      return this;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
  };

  try {
    await getUnifiedExamDashboard({ query: {} }, response);
    return { queries, response };
  } finally {
    pool.query = originalQuery;
  }
}

test('dashboard uses equality for a single open session', async () => {
  const { queries, response } = await runDashboard(
    [{ id: 1, name: '2026', is_active: 1 }],
    [],
  );
  const eventQuery = queries.find(({ sql }) =>
    sql.includes('SELECT e.*, s.name AS session_name'));

  assert.equal(response.statusCode, undefined);
  assert.match(eventQuery.sql, /e\.session_id = \?/);
  assert.doesNotMatch(eventQuery.sql, /e\.session_id IN \(\?\)/);
  assert.deepEqual(eventQuery.params, [1]);
});

test('dashboard keeps expanded placeholders for multiple open sessions', async () => {
  const { queries, response } = await runDashboard(
    [
      { id: 1, name: '2026', is_active: 1 },
      { id: 2, name: '2027', is_active: 0 },
    ],
    [{ year: 2026, exam_kind: 'test', is_published: 1, session_name: '2026' }],
  );
  const eventQuery = queries.find(({ sql }) =>
    sql.includes('SELECT e.*, s.name AS session_name'));

  assert.equal(response.statusCode, undefined);
  assert.match(eventQuery.sql, /e\.session_id IN \(\?,\?\)/);
  assert.deepEqual(eventQuery.params, [1, 2]);
});
