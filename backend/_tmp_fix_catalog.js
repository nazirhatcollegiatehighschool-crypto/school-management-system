const pool = require('./db.js');
(async () => {
  // Fix promotion-source rules:
  // - Band 6-9: only annual = promotion source (half_yearly = no, ca = no)
  // - Band 10: only test = promotion source (pretest = no)
  // - Band SSC: test = promotion source (model_test = no)
  
  await pool.query('UPDATE exam_catalog SET is_promotion_source=0 WHERE band=? AND exam_kind=?', ['6-9', 'half_yearly']);
  await pool.query('UPDATE exam_catalog SET is_promotion_source=0 WHERE band=? AND exam_kind=?', ['6-9', 'ca']);
  await pool.query('UPDATE exam_catalog SET is_promotion_source=1 WHERE band=? AND exam_kind=?', ['6-9', 'annual']);
  
  await pool.query('UPDATE exam_catalog SET is_promotion_source=0 WHERE band=? AND exam_kind=?', ['10', 'pretest']);
  await pool.query('UPDATE exam_catalog SET is_promotion_source=1 WHERE band=? AND exam_kind=?', ['10', 'test']);
  
  await pool.query('UPDATE exam_catalog SET is_promotion_source=1 WHERE band=? AND exam_kind=?', ['ssc', 'test']);
  await pool.query('UPDATE exam_catalog SET is_promotion_source=0 WHERE band=? AND exam_kind=?', ['ssc', 'model_test']);
  
  const [rows] = await pool.query('SELECT * FROM exam_catalog ORDER BY band, exam_kind');
  console.log('=== AFTER FIX ===');
  console.log(JSON.stringify(rows, null, 2));
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });