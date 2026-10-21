require('dotenv').config();
const p = require('./db');
(async () => {
  const [r] = await p.query("SELECT id,exam_type,source,class_id,subject_id,status,entry_open FROM exams WHERE class_id=13 AND subject_id=1027");
  console.log(JSON.stringify(r, null, 2));
  process.exit(0);
})();
