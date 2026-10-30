const crypto = require('crypto');

function createCronAuthorizer({
  getSecret = () => process.env.CRON_SECRET,
  isProduction = () => process.env.NODE_ENV === 'production' || Boolean(process.env.VERCEL),
} = {}) {
  return function authorizeCron(req, res, next) {
    const secret = getSecret();
    if (!secret) {
      if (!isProduction()) return next();
      return res.status(503).json({ error: 'CRON_SECRET is required in production.' });
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
