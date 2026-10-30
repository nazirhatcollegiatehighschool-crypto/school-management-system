const test = require('node:test');
const assert = require('node:assert/strict');
const { dhakaEndEpoch, isExpired } = require('../lib/attendance_access');

test('attendance expiry converts a Dhaka wall time to UTC correctly', () => {
  assert.equal(dhakaEndEpoch('2026-10-30', '15:30:00'), Date.UTC(2026, 9, 30, 9, 30));
});

test('attendance expiry rejects malformed or impossible date/time values', () => {
  assert.equal(dhakaEndEpoch('2026-02-30', '15:30'), null);
  assert.equal(dhakaEndEpoch('2026-10-30', '24:00'), null);
  assert.equal(dhakaEndEpoch('not-a-date', 'x'), null);
});

test('pending requests expire at the boundary and decided requests stay decided', () => {
  assert.equal(isExpired({ status: 'pending', expires_at_epoch: 100 }, 100), true);
  assert.equal(isExpired({ status: 'pending', expires_at_epoch: 101 }, 100), false);
  assert.equal(isExpired({ status: 'accepted', expires_at_epoch: 1 }, 100), false);
  assert.equal(isExpired({ status: 'expired', expires_at_epoch: 1000 }, 100), true);
});
