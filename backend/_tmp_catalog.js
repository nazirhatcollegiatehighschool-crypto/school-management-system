const pool = require('./db.js');
(async () => {
  const [rows] = await pool.query('SELECT * FROM exam_catalog ORDER BY band, exam_kind');
  console.log('=== exam_catalog ===');
  console.log(JSON.stringify(rows, null, 2));
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });