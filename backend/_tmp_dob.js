const pool = require('./db.js');
(async () => {
  const [rows] = await pool.query('SELECT student_code, dob FROM students WHERE student_code = \'48291056\'');
  console.log('Raw DOB from DB:', JSON.stringify(rows[0].dob));
  console.log('Type:', typeof rows[0].dob);
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });