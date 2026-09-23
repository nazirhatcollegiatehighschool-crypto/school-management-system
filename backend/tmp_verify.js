const { Pool } = require('pg');
const p = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.DB_SSL !== 'false' });
(async () => {
  const q = async (t, a) => (await p.query(t, a)).rows;
  console.log('homework left:', (await q('select count(*) n from homework'))[0].n, '| with subject null:', (await q('select count(*) n from homework where subject_id is null'))[0].n);
  console.log('exams:', (await q('select count(*) n from exams'))[0].n, 'marks:', (await q('select count(*) n from marks'))[0].n);
  console.log('aliases sample:');
  console.table(await q(`select sa.id, s.class_id, s.name, sa.alias_name, sa.field_value from subject_aliases sa join subjects s on s.id=sa.subject_id order by s.class_id, sa.field_value limit 8`));
  console.log('student_subjects kept:', (await q('select count(*) n from student_subjects'))[0].n);
  console.log('Class 9 Science groups:');
  console.table(await q(`select group_name, count(*) n from subjects where class_id=10 group by group_name order by group_name`));
  console.log('student 6 (Rakib) subject allocs:');
  console.table(await q(`select s.id sub_id, s.name, ss.is_mandatory, ss.is_fourth_subject, ss.is_elective
    from student_subjects ss join subjects s on s.id=ss.subject_id where ss.student_id=6 order by s.sort_order`));
  console.log('religion aliases count per class (18):', (await q(`select count(*) from subject_aliases sa join subjects s on s.id=sa.subject_id where s.name='Religion & Moral Education'`))[0].count);
})().catch(e => { console.error(e.message); process.exit(1); }).finally(() => p.end());