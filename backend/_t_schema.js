require('dotenv').config({path:'.env'});
const pool=require('./db');
(async()=>{
  for (const tb of ['promotion_history','notifications','students']) {
    const [c]=await pool.query("select column_name,data_type,is_nullable from information_schema.columns where table_name=$1 order by ordinal_position",[tb]);
    console.log('---',tb,'---');
    c.forEach(r=>console.log('  ',r.column_name,r.data_type,'null='+r.is_nullable));
  }
  process.exit(0);
})();
