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

test('cron requests fail closed in production when CRON_SECRET is missing', () => {
  let nextCalled = false;
  const res = responseProbe();
  createCronAuthorizer({ getSecret: () => '', isProduction: () => true })(
    { headers: {} }, res, () => { nextCalled = true; });
  assert.equal(res.statusCode, 503);
  assert.equal(nextCalled, false);
});

test('cron rejects missing or incorrect bearer tokens', () => {
  for (const authorization of [undefined, 'Bearer incorrect']) {
    let nextCalled = false;
    const res = responseProbe();
    createCronAuthorizer({ getSecret: () => 'test-only-secret', isProduction: () => true })(
      { headers: { authorization } }, res, () => { nextCalled = true; });
    assert.equal(res.statusCode, 401);
    assert.equal(nextCalled, false);
  }
});

test('cron accepts the configured bearer token', () => {
  let nextCalled = false;
  const res = responseProbe();
  createCronAuthorizer({ getSecret: () => 'test-only-secret', isProduction: () => true })(
    { headers: { authorization: 'Bearer test-only-secret' } }, res, () => { nextCalled = true; });
  assert.equal(res.statusCode, null);
  assert.equal(nextCalled, true);
});

test('cron allows an unset secret only outside production and Vercel', () => {
  let nextCalled = false;
  createCronAuthorizer({ getSecret: () => '', isProduction: () => false })(
    { headers: {} }, responseProbe(), () => { nextCalled = true; });
  assert.equal(nextCalled, true);
});
