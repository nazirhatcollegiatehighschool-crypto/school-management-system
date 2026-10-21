const pool = require('./db.js');
(async () => {
  const [rows] = await pool.query("SELECT s.student_code, s.dob, s.guardian_phone, s.name, c.name AS class_name, c.section, s.roll FROM students s JOIN classes c ON c.id=s.class_id WHERE s.guardian_phone IS NOT NULL AND s.guardian_phone != '' LIMIT 5");
  console.log(JSON.stringify(rows, null, 2));
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });