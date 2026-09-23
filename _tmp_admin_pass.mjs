import pg from 'pg';
import bcrypt from 'bcryptjs';
import 'dotenv/config';
const BASE = process.env.BASE_URL;
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.DB_SSL === 'false' ? false : undefined });
const NEWP = process.env.NEWP;
try {
  const [[admin]] = await pool.query("SELECT id, username FROM users WHERE role='admin' ORDER BY id LIMIT 1");
  if (!admin) throw new Error('no admin user');
  const hash = await bcrypt.hash(NEWP, 10);
  await pool.query('UPDATE users SET password_hash=? WHERE id=?', [hash, admin.id]);
  console.log('Updated password for admin id=' + admin.id);
  // verify login round-trip
  const r = await fetch(BASE + '/api/auth/login', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: admin.username, password: NEWP })
  });
  const d = await r.json();
  console.log('login verification:', r.ok && d.token ? 'PASS ✓' : 'FAIL: ' + JSON.stringify(d));
} finally { await pool.end(); }
