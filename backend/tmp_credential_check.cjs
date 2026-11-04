require('dotenv').config({ path: 'backend/.env', quiet: true });
const pool = require('./db');
(async () => {
  const [[admins]] = await pool.query('SELECT COUNT(*) AS n FROM users WHERE role=?', ['admin']);
  const [[username]] = await pool.query('SELECT COUNT(*) AS n FROM users WHERE username=?', ['NazirhatCollegiateHighSchool']);
  const [rows] = await pool.query('SELECT id, (username=?) AS requested_username FROM users WHERE role=? ORDER BY id', ['NazirhatCollegiateHighSchool', 'admin']);
  console.log(JSON.stringify({
    adminCount: Number(admins.n),
    requestedUsernameAlreadyInUse: Number(username.n) > 0,
    adminRecords: rows.map(row => ({ id: row.id, hasRequestedUsername: row.requested_username === true || row.requested_username === 1 })),
  }));
  await pool.end();
})().catch(error => {
  console.error(error.code || error.name);
  process.exit(1);
});
