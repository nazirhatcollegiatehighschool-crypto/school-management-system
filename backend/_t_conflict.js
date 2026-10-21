require('dotenv').config({path:'.env'});
const pool=require('./db');
(async()=>{
  try{
    await pool.query("INSERT INTO promotions (student_id,event_id,class_id,from_class,to_class,decision) VALUES (999999,999999,13,'X','Y','test') ON CONFLICT (student_id, event_id) DO NOTHING");
    console.log('ON CONFLICT (student_id,event_id): INFERENCE OK');
    await pool.query("DELETE FROM promotions WHERE student_id=999999");
  }catch(e){ console.log('INFERENCE ERR:', e.message); }
  // check transform of $2 IS NOT NULL
  const sql2 = "SELECT id FROM classes WHERE name = 'Class ' || (CAST(SUBSTRING($1 FROM '\d+') AS INT) + 1) || CASE WHEN CAST($2 AS text) IS NOT NULL THEN ' (' || CAST($2 AS text) || ')' ELSE ' (' || CAST($3 AS text) || ')' END ORDER BY id LIMIT 1";
  try{
    const [r]=await pool.query(sql2,['Class 9','Arts','A']);
    console.log('CAST fix OK:',JSON.stringify(r));
  }catch(e){ console.log('CAST fix ERR:', e.message); }
  process.exit(0);
})();
