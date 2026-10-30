const pool = require('./db');

const OPTIONS = {
  arts: ['Agriculture', 'Home Science'],
  commerce: ['Agriculture', 'Home Science'],
  science: ['Higher Mathematics', 'Agriculture', 'Home Science'],
};

function canonicalSubject(value) {
  const key = String(value || '').trim().toLowerCase().replace(/[^a-z]/g, '');
  if (['civics', 'civicsandcitizenship'].includes(key)) return 'Civics';
  if (['economics', 'economy'].includes(key)) return 'Economics';
  if (['agriculture', 'agriculturestudies', 'agriculturalstudies'].includes(key)) return 'Agriculture';
  if (['homescience', 'homeeconomics'].includes(key)) return 'Home Science';
  if (['highermathematics', 'highermath', 'advancedmathematics'].includes(key)) return 'Higher Mathematics';
  return null;
}

function canonicalReligion(value) {
  const raw = String(value || '').trim();
  const key = raw.toLowerCase();
  if (/^(islam|islamic|muslim)$/.test(key)) return 'Islam';
  if (/^hindu(ism)?$/.test(key)) return 'Hinduism';
  if (/^christian(ity)?$/.test(key)) return 'Christianity';
  if (/^buddhist?$|^buddhism$/.test(key)) return 'Buddhism';
  return raw || null;
}

async function validateStudentCurriculum(classId, choices = {}, { partial = false } = {}) {
  const [[cls]] = await pool.query('SELECT id, name, group_name, section FROM classes WHERE id=?', [classId]);
  if (!cls) throw Object.assign(new Error('Class not found'), { status: 404 });
  const level = Number((String(cls.name).match(/\d+/) || [])[0]);
  const groupRaw = String(cls.group_name || cls.section || '').toLowerCase();
  const group = /arts|humanit/.test(groupRaw) ? 'arts'
    : /commerce|business/.test(groupRaw) ? 'commerce'
    : /science/.test(groupRaw) ? 'science' : null;
  if (level !== 9 && level !== 10) return { compulsory_subject: choices.compulsory_subject || null, optional_subject: choices.optional_subject || null };
  if (!group) throw Object.assign(new Error('Class 9–10 student-এর Arts, Commerce বা Science group নির্ধারিত থাকতে হবে।'), { status: 400 });

  const compulsory = canonicalSubject(choices.compulsory_subject);
  const optional = canonicalSubject(choices.optional_subject);
  if (group === 'arts' && !partial && !compulsory) {
    throw Object.assign(new Error('Arts-এর জন্য Civics অথবা Economics বেছে নিতে হবে।'), { status: 400 });
  }
  if (group === 'arts' && choices.compulsory_subject && !['Civics', 'Economics'].includes(compulsory)) {
    throw Object.assign(new Error('Arts-এর compulsory subject Civics অথবা Economics হতে হবে।'), { status: 400 });
  }
  if (group !== 'arts' && compulsory) {
    throw Object.assign(new Error('Civics/Economics choice শুধু Arts group-এর জন্য।'), { status: 400 });
  }
  if (!partial && !optional) {
    throw Object.assign(new Error('এই group-এর optional subject বেছে নিতে হবে।'), { status: 400 });
  }
  if (optional && !OPTIONS[group].includes(optional)) {
    throw Object.assign(new Error(`${group} group-এর জন্য এই optional subject প্রযোজ্য নয়।`), { status: 400 });
  }
  return { compulsory_subject: group === 'arts' ? compulsory : null, optional_subject: optional };
}

module.exports = { canonicalSubject, canonicalReligion, validateStudentCurriculum, OPTIONS };
