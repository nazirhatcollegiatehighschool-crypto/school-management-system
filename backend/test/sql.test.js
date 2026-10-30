const test = require('node:test');
const assert = require('node:assert/strict');
const { inClause } = require('../lib/sql');

test('inClause uses equality for one value', () => {
  assert.deepEqual(inClause('e.session_id', [42]), {
    sql: 'e.session_id = ?',
    params: [42],
  });
});

test('inClause keeps separate placeholders for multiple values', () => {
  assert.deepEqual(inClause('c.id', [3, 7]), {
    sql: 'c.id IN (?,?)',
    params: [3, 7],
  });
});

test('inClause produces a false predicate for an empty value list', () => {
  assert.deepEqual(inClause('c.id', []), {
    sql: '1=0',
    params: [],
  });
});

test('inClause ignores null and undefined values', () => {
  assert.deepEqual(inClause('c.id', [null, 5, undefined]), {
    sql: 'c.id = ?',
    params: [5],
  });
});
