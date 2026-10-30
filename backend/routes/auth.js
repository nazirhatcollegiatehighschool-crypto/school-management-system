const router = require('express').Router();
const bcrypt = require('bcrypt');
const pool = require('../db');
const { signToken, auth, requireJwtConfiguration } = require('../middleware/auth');

router.post('/login', requireJwtConfiguration, async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ error: 'Username and password required' });
  try {
    const [rows] = await pool.query('SELECT * FROM users WHERE username = ?', [username]);
    if (rows.length === 0) return res.status(401).json({ error: 'Invalid username or password' });
    const user = rows[0];
    if (!user.active) return res.status(403).json({ error: 'This account has been deactivated. Contact admin.' });
    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) return res.status(401).json({ error: 'Invalid username or password' });
    const token = signToken(user);
    const { password_hash, ...safe } = user;
    res.json({ token, user: safe });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

router.post('/guardian-login', requireJwtConfiguration, async (req, res) => {
  const { student_code, dob, phone, birth_cert_no } = req.body || {};
  let loginStage = 'student lookup';
  if (!student_code || !dob || !phone || !birth_cert_no) {
    return res.status(400).json({ error: 'Student ID, guardian phone, birth registration number and date of birth are required' });
  }
  try {
    const [rows] = await pool.query(
      `SELECT s.*, c.name AS class_name, c.section
       FROM students s JOIN classes c ON s.class_id = c.id
       WHERE s.student_code = ?`,
      [String(student_code).trim()]
    );
    if (rows.length === 0) return res.status(401).json({ error: 'Student not found with this ID' });
    const s = rows[0];
    if (Number(s.birth_cert_placeholder) === 1) {
      return res.status(401).json({ error: 'Student-এর আসল জন্মনিবন্ধন নম্বর school-এ update না হওয়া পর্যন্ত login করা যাবে না।' });
    }
    if (String(s.birth_cert_no || '').trim() !== String(birth_cert_no).trim()) {
      return res.status(401).json({ error: 'Birth registration number does not match admission record' });
    }
    const dbDob = s.dob instanceof Date ? s.dob.toISOString().slice(0, 10) : String(s.dob || '').slice(0, 10);
    const dobStr = /^\d{4}-\d{2}-\d{2}$/.test(dbDob) ? dbDob : '';
    const dobMatch = s.dob ? dobStr === String(dob).trim() : false;
    if (!dobMatch) return res.status(401).json({ error: 'Date of birth does not match' });
    const mainPhone = String(s.guardian_phone || '').trim();
    const storedGuardianDigits = mainPhone.replace(/\D/g, '');
    const suppliedGuardianDigits = String(phone).replace(/\D/g, '');
    if (storedGuardianDigits.length < 10 || suppliedGuardianDigits.length < 10 ||
        storedGuardianDigits.slice(-10) !== suppliedGuardianDigits.slice(-10)) {
      return res.status(401).json({ error: 'Phone number does not match admission record' });
    }

    loginStage = 'guardian account and ownership link';
    const username = 'g_' + String(s.student_code).toLowerCase();
    const hash = await bcrypt.hash(mainPhone, 10);
    const conn = await pool.getConnection();
    let guardian;
    try {
      await conn.beginTransaction();
      let guardianId = Number(s.guardian_id) || null;
      if (guardianId) {
        const [[linkedAccount]] = await conn.query('SELECT * FROM users WHERE id=?', [guardianId]);
        if (!linkedAccount || linkedAccount.role !== 'guardian') guardianId = null;
      }

      if (!guardianId) {
        // A previous interrupted login may have created the username but not
        // linked it to the student. Reuse that guardian account idempotently.
        let [[account]] = await conn.query('SELECT * FROM users WHERE username=?', [username]);
        if (account && account.role !== 'guardian') {
          throw Object.assign(new Error('Guardian account could not be matched safely.'), { status: 409 });
        }
        if (!account) {
          // is_class_teacher is NOT NULL on the live schema (legacy column
          // shared by every role). Guardian rows store an empty class list,
          // matching existing accounts; omitting it fails the insert with 23502.
          await conn.query(
            `INSERT INTO users (role, username, password_hash, name, phone, is_class_teacher)
             VALUES ('guardian',?,?,?,?,'[]') ON CONFLICT (username) DO NOTHING`,
            [username, hash, s.guardian_name || 'Guardian of ' + s.name, mainPhone]
          );
          [[account]] = await conn.query('SELECT * FROM users WHERE username=?', [username]);
        }
        if (!account || account.role !== 'guardian') {
          throw Object.assign(new Error('Guardian account could not be created.'), { status: 500 });
        }
        guardianId = Number(account.id);
        await conn.query('UPDATE students SET guardian_id=? WHERE id=?', [guardianId, s.id]);
      }

      // The student who logged in is this guardian's own child. Replaying the
      // login safely restores the primary link after an interrupted request.
      await conn.query(
        `INSERT INTO guardian_links (guardian_id, student_id, role, status)
         VALUES (?,?,'primary','approved')
         ON CONFLICT (guardian_id, student_id) DO UPDATE SET role='primary', status='approved'`,
        [guardianId, s.id]
      );
      [[guardian]] = await conn.query('SELECT * FROM users WHERE id=?', [guardianId]);
      if (!guardian) throw Object.assign(new Error('Guardian account was not available after linking.'), { status: 500 });
      await conn.commit();
    } catch (err) {
      try { await conn.rollback(); } catch (_) {}
      throw err;
    } finally {
      conn.release();
    }

    loginStage = 'token creation';
    if (guardian.active === false || Number(guardian.active) === 0) {
      throw Object.assign(
        new Error('Guardian account has been deactivated. Contact admin.'),
        { status: 403 }
      );
    }
    const token = signToken(guardian);
    // Audit logging is best-effort; an audit-table hiccup must not turn a
    // successfully authenticated guardian into a misleading login failure.
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [guardian.id, 'guardian_login', 'Guardian logged in for ' + s.name])
      .catch(err => console.error('Guardian login audit write failed:', err.code || 'DB_ERROR'));
    const { password_hash, ...safe } = guardian;
    res.json({
      token,
      user: safe,
      students: [{
        id: s.id, name: s.name, student_code: s.student_code, roll: s.roll,
        class_name: s.class_name, section: s.section
      }]
    });
  } catch (err) {
    console.error('Guardian login error at', loginStage, err.code || 'UNKNOWN', err.status || 500);
    const exposeMessage = err.status === 403 || err.status === 409;
    res.status(err.status || 500).json({ error: exposeMessage ? err.message : 'Server error' });
  }
});

router.get('/me', auth(), (req, res) => {
  res.json({ user: req.user });
});

router.post('/register-device', auth(), async (req, res) => {
  const { fcm_token, platform } = req.body || {};
  if (!fcm_token) return res.status(400).json({ error: 'fcm_token required' });
  try {
    await pool.query(
      `INSERT INTO device_tokens (user_id, role, fcm_token, platform)
       VALUES (?,?,?,?)
       ON CONFLICT (fcm_token) DO UPDATE SET user_id=EXCLUDED.user_id, role=EXCLUDED.role, active=1`,
      [req.user.id, req.user.role, String(fcm_token), platform || 'android']
    );
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

router.post('/unregister-device', auth(), async (req, res) => {
  const { fcm_token } = req.body || {};
  if (!fcm_token) return res.status(400).json({ error: 'fcm_token required' });
  try {
    await pool.query('UPDATE device_tokens SET active=0 WHERE fcm_token=? AND user_id=?', [String(fcm_token), req.user.id]);
    res.json({ ok: true });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;
