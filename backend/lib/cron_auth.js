const crypto = require('crypto');

function createCronAuthorizer({
  getSecret = () => process.env.CRON_SECRET,
  allowUnauthenticated = () => process.env.ALLOW_UNAUTHENTICATED_CRON === '1',
} = {}) {
  return function authorizeCron(req, res, next) {
    const secret = getSecret();
    if (!secret) {
      // Fail closed by default. The local server is reachable through a public
      // tunnel, so "not production" cannot be treated as a trusted caller.
      // Operators who explicitly need secret-less local cron calls can set
      // ALLOW_UNAUTHENTICATED_CRON=1.
      if (allowUnauthenticated()) return next();
      return res.status(503).json({ error: 'CRON_SECRET is not configured.' });
    }
    const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const provided = Buffer.from(token);
    const expected = Buffer.from(secret);
    if (provided.length !== expected.length || !crypto.timingSafeEqual(provided, expected)) {
      return res.status(401).json({ error: 'Unauthorized cron request.' });
    }
    next();
  };
}

module.exports = { createCronAuthorizer };
