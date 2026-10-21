require('dotenv').config({path:'.env'});
const pool=require('./db');
(async()=>{
  const [c]=await pool.query("SELECT id,name,section,group_name FROM classes ORDER BY name, section, group_name");
  const cls=c[0];
  console.log('class:',JSON.stringify(cls));
  try{
    const [r]=await pool.query(
      `SELECT id, name, section, group_name FROM classes
         WHERE name = 'Class ' || (CAST(SUBSTRING($1 FROM '\d+') AS INT) + 1) ||
               CASE WHEN $2 IS NOT NULL THEN ' (' || $2 || ')' ELSE ' (' || $3 || ')' END
         ORDER BY id LIMIT 1`,
      [cls.name, cls.group_name, cls.section]);
    console.log('OK:',JSON.stringify(r));
  }catch(e){ console.log('ERR:', e.message); }
  process.exit(0);
})();
