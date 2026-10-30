'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeGender } = require('../lib/gender');

test('normalizes female spelling variants to the database canonical value', () => {
  for (const value of ['Female', 'female', 'FEMAL', 'femail', 'females']) {
    assert.equal(normalizeGender(value), 'Female');
  }
});

test('preserves unknown gender values and treats empty values as absent', () => {
  assert.equal(normalizeGender('Nonbinary'), 'Nonbinary');
  assert.equal(normalizeGender('  '), null);
});
