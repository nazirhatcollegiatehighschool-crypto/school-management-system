require('dotenv').config({path:'.env'});
const pool=require('./db');
(async()=>{
  const [r]=await pool.query("select class_id, section, session_id, count(*) c from students where class_id in (13,14,15,16,17,18) group by class_id, section, session_id order by class_id");
  console.log('students by class/section/session:');
  r.forEach(x=>console.log('  class='+x.class_id,'section='+x.section,'session='+x.session_id,'n='+x.c));
  const [p]=await pool.query("select * from promotions");
  console.log('promotions rows:', JSON.stringify(p));
  process.exit(0);
})();
