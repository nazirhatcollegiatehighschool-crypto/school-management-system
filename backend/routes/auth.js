const router = require('express').Router();
const bcrypt = require('bcrypt');
const pool = require('../db');
const { signToken, auth } = require('../middleware/auth');

router.post('/login', async (req, res) => {
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

router.post('/guardian-login', async (req, res) => {
  const { student_code, dob, class_name, section, roll, phone } = req.body || {};
  if (!student_code || !dob || !class_name || !section || !roll || !phone) {
    return res.status(400).json({ error: 'All fields required: student code, DOB, class, section, roll, phone' });
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
    const d = s.dob instanceof Date ? s.dob : new Date(s.dob);
    const dobStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    const dobMatch = s.dob ? dobStr === String(dob).trim() : false;
    if (!dobMatch) return res.status(401).json({ error: 'Date of birth does not match' });
    const storedClassNum = (String(s.class_name).match(/\d+/) || [])[0];
    const givenClassNum = (String(class_name).match(/\d+/) || [])[0];
    if (!storedClassNum || !givenClassNum || storedClassNum !== givenClassNum) {
      return res.status(401).json({ error: 'Class does not match' });
    }
    if (String(s.section).toLowerCase() !== String(section).toLowerCase()) {
      return res.status(401).json({ error: 'Section does not match' });
    }
    if (Number(s.roll) !== Number(roll)) return res.status(401).json({ error: 'Roll number does not match' });
    const mainPhone = String(s.guardian_phone || '').trim();
    if (!mainPhone || mainPhone.replace(/[^0-9]/g, '').slice(-11) !== String(phone).replace(/[^0-9]/g, '').slice(-11)) {
      return res.status(401).json({ error: 'Phone number does not match admission record' });
    }

    let guardianId = s.guardian_id;
    if (!guardianId) {
      const username = 'g_' + s.student_code.toLowerCase();
      const hash = await bcrypt.hash(mainPhone, 10);
      const [ins] = await pool.query(
        "INSERT INTO users (role, username, password_hash, name, phone) VALUES ('guardian',?,?,?,?)",
        [username, hash, s.guardian_name || 'Guardian of ' + s.name, mainPhone]
      );
      guardianId = ins.insertId;
      await pool.query('UPDATE students SET guardian_id = ? WHERE id = ?', [guardianId, s.id]);
    }

    // The student who logged in is, by definition, that guardian's OWN child —
    // auto-approve a primary link so exactly THIS student is visible.
    await pool.query(
      `INSERT INTO guardian_links (guardian_id, student_id, role, status)
       VALUES (?,?,'primary','approved')
       ON CONFLICT (guardian_id, student_id) DO UPDATE SET role='primary', status='approved'`,
      [guardianId, s.id]
    );

    const [gRows] = await pool.query('SELECT * FROM users WHERE id = ?', [guardianId]);
    const guardian = gRows[0];
    const token = signToken(guardian);
    await pool.query('INSERT INTO activity_log (user_id, action, detail) VALUES (?,?,?)',
      [guardianId, 'guardian_login', 'Guardian logged in for ' + s.name]);
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
    console.error('Guardian login error:', err);
    res.status(500).json({ error: 'Server error' });
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