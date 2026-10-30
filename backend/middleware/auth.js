require('dotenv').config();
const jwt = require('jsonwebtoken');

// Keep a predictable key only for local development. A production deployment
// without its configured signing secret must fail closed instead of issuing
// forgeable sessions with a public default.
const JWT_SECRET = process.env.JWT_SECRET ||
  (process.env.NODE_ENV === 'production' || process.env.VERCEL
    ? null
    : 'school_management_secret_key_2026');

function signToken(user) {
  if (!JWT_SECRET) {
    throw Object.assign(new Error('JWT_SECRET is required in production'), { code: 'JWT_SECRET_MISSING' });
  }
  return jwt.sign(
    { id: user.id, role: user.role, username: user.username, name: user.name },
    JWT_SECRET,
    { expiresIn: '7d' }
  );
}

function matchesRole(required, actual) {
  if (!required) return true;
  const list = Array.isArray(required) ? required : [required];
  return list.includes(actual);
}

function requireJwtConfiguration(req, res, next) {
  if (!JWT_SECRET) return res.status(503).json({ error: 'Authentication is not configured.' });
  next();
}

function auth(roles) {
  return (req, res, next) => {
    if (!JWT_SECRET) return res.status(503).json({ error: 'Authentication is not configured.' });
    const header = req.headers.authorization || '';
    // PDF/print downloads can't send headers (url_launcher/browser) — allow ?token= fallback.
    const qToken = req.query && typeof req.query.token === 'string' ? req.query.token : null;
    const token = header.startsWith('Bearer ') ? header.slice(7) : qToken;
    if (!token) return res.status(401).json({ error: 'No token provided' });
    try {
      const decoded = jwt.verify(token, JWT_SECRET);
      if (!matchesRole(roles, decoded.role)) {
        return res.status(403).json({ error: 'Access denied' });
      }
      req.user = decoded;
      next();
    } catch (e) {
      return res.status(401).json({ error: 'Invalid or expired session. Please login again.' });
    }
  };
}

module.exports = { signToken, auth, requireJwtConfiguration, JWT_SECRET };
