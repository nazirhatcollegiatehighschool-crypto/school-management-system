const test = require('node:test');
const assert = require('node:assert/strict');
const { isValidPromotionStatusPair } = require('../lib/promotion_status');

test('promotion status and decision must describe the same outcome', () => {
  assert.equal(isValidPromotionStatusPair('approved', 'promoted'), true);
  assert.equal(isValidPromotionStatusPair('retained', 'retained'), true);
  assert.equal(isValidPromotionStatusPair('retained', 'promoted'), false);
  assert.equal(isValidPromotionStatusPair('approved', 'retained'), false);
});
