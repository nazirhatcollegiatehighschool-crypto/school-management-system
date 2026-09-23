require('dotenv').config();
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'school_management_secret_key_2026';

function signToken(user) {
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

function auth(roles) {
  return (req, res, next) => {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
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

module.exports = { signToken, auth, JWT_SECRET };