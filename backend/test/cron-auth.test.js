const test = require('node:test');
const assert = require('node:assert/strict');
const { createCronAuthorizer } = require('../lib/cron_auth');

function responseProbe() {
  return {
    statusCode: null,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

test('cron requests fail closed when CRON_SECRET is missing', () => {
  let nextCalled = false;
  const res = responseProbe();
  createCronAuthorizer({ getSecret: () => '', allowUnauthenticated: () => false })(
    { headers: {} }, res, () => { nextCalled = true; });
  assert.equal(res.statusCode, 503);
  assert.equal(nextCalled, false);
});

test('cron rejects missing or incorrect bearer tokens', () => {
  for (const authorization of [undefined, 'Bearer incorrect']) {
    let nextCalled = false;
    const res = responseProbe();
    createCronAuthorizer({ getSecret: () => 'test-only-secret', allowUnauthenticated: () => false })(
      { headers: { authorization } }, res, () => { nextCalled = true; });
    assert.equal(res.statusCode, 401);
    assert.equal(nextCalled, false);
  }
});

test('cron accepts the configured bearer token', () => {
  let nextCalled = false;
  const res = responseProbe();
  createCronAuthorizer({ getSecret: () => 'test-only-secret', allowUnauthenticated: () => false })(
    { headers: { authorization: 'Bearer test-only-secret' } }, res, () => { nextCalled = true; });
  assert.equal(res.statusCode, null);
  assert.equal(nextCalled, true);
});

test('cron only allows a missing secret with an explicit opt-in', () => {
  let nextCalled = false;
  createCronAuthorizer({ getSecret: () => '', allowUnauthenticated: () => true })(
    { headers: {} }, responseProbe(), () => { nextCalled = true; });
  assert.equal(nextCalled, true);
});
