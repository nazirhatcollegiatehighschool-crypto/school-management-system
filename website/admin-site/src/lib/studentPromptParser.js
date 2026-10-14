// Improved port of transcript-generator's parseStudentInfo (ai-parsers.js).
// Pure JS — no DOM. Parses a Bangla/English student-info prompt "Label: value"
// blob into structured fields. Improvements over the original:
//   * scans every occurrence of each label (not just the first),
//   * keeps the longest label at the same start index and drops labels nested
//     inside (or touching) an already-matched label's span, so sequential
//     "Guardian Name:" / "Guardian Phone:" rows stay clean.

const BANGLA = { '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4', '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9' };
const ARABIC = { '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9' };

export function toLatinDigits(str) {
  return String(str == null ? '' : str)
    .replace(/[০-৯]/g, c => BANGLA[c] || c)
    .replace(/[٠-٩]/g, c => ARABIC[c] || c);
}

const MONTHS = {
  january: 1, february: 2, march: 3, april: 4, may: 5, june: 6, july: 7,
  august: 8, september: 9, october: 10, november: 11, december: 12,
  'জানুয়ারি': 1, 'জানুয়ারী': 1, 'ফেব্রুয়ারি': 2, 'ফেব্রুয়ারী': 2, 'মার্চ': 3,
  'এপ্রিল': 4, 'মে': 5, 'জুন': 6, 'জুলাই': 7, 'আগস্ট': 8, 'সেপ্টেম্বর': 9,
  'অক্টোবর': 10, 'নভেম্বর': 11, 'ডিসেম্বর': 12,
};

function pad2(n) { return String(n).length < 2 ? '0' + n : String(n); }

function normalizeDob(raw) {
  const v = String(raw || '').trim();
  if (!v) return '';
  let m;
  if ((m = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/.exec(v))) return m[1] + '-' + pad2(m[2]) + '-' + pad2(m[3]);
  if ((m = /^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/.exec(v))) return m[3] + '-' + pad2(m[2]) + '-' + pad2(m[1]);
  if ((m = /(\d{4})\s+(\d{1,2})\s+([A-Za-z\u0980-\u09FF]+)/.exec(v))) {
    const mn = MONTHS[m[3].toLowerCase()];
    if (mn) return m[1] + '-' + pad2(mn) + '-' + pad2(m[2]);
  }
  if ((m = /(\d{1,2})\s+([A-Za-z\u0980-\u09FF]+)\s+(\d{4})/.exec(v))) {
    const mn = MONTHS[m[2].toLowerCase()];
    if (mn) return m[3] + '-' + pad2(mn) + '-' + pad2(m[1]);
  }
  return v;
}

const escRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const hasWord = (str, word) =>
  new RegExp('(^|[^\\w\\u0980-\\u09FF])' + escRe(word) + '([^\\w\\u0980-\\u09FF]|$)', 'i').test(str);

const FIELDS = [
  ['name', ['name', 'student name', 'ছাত্রের নাম', 'নাম']],
  ['roll', ['roll', 'roll no', 'roll number', 'রোল']],
  ['class', ['class', 'শ্রেণী', 'শ্রেণি', 'ক্লাস']],
  ['group', ['group', 'গ্রুপ', 'বিভাগ']],
  ['section', ['section', 'শাখা', 'sec']],
  ['gender', ['gender', 'sex', 'লিঙ্গ', 'জেন্ডার']],
  ['dob', ['date of birth', 'birth date', 'dob', 'জন্মতারিখ', 'জন্ম তারিখ']],
  ['birth_cert_no', ['birth certificate no', 'birth certificate number', 'birth certificate', 'birth cert', 'birth reg', 'birth registration', 'birth registration no', 'জন্ম নিবন্ধন', 'জন্মনিবন্ধন', 'জন্ম সনদ', 'জন্মসনদ']],
  ['religion', ['religion', 'ধর্ম']],
  ['blood_group', ['blood group', 'blood', 'রক্ত', 'রক্তের গ্রুপ']],
  ['optional_subject', ['optional subject', 'optional', 'oecho', 'ঐচ্ছিক বিষয়', 'ঐচ্ছিক', 'নৈবিক বিষয়', 'অপশনাল']],
  ['father_name', ["father's name", 'father name', 'father', 'পিতার নাম', 'পিতা']],
  ['mother_name', ["mother's name", 'mother name', 'mother', 'মাতার নাম', 'মাতা']],
  ['phone', ['phone', 'mobile', 'contact', 'ফোন', 'মোবাইল']],
  ['email', ['email', 'ইমেইল', 'মেইল']],
  ['guardian_name', ['guardian name', 'guardian', 'অভিভাবকের নাম', 'অভিভাবক']],
  ['guardian_phone', ['guardian phone', 'guardian contact', 'অভিভাবক ফোন', 'অভিভাবক নম্বর']],
  ['address', ['address', 'present address', 'current address', 'permanent address', 'residential address', 'village', 'location', 'ঠিকানা', 'বর্তমান ঠিকানা', 'স্থায়ী ঠিকানা', 'বাসস্থান', 'residence']],
  ['student_id', ['student id', 'student no', 'id', 'student code']],
];

export function parseStudentPrompt(text) {
  const raw = toLatinDigits(text || '');
  const data = {};
  const set = (k, v) => { if (v != null && String(v).trim() !== '') data[k] = String(v).trim(); };

  const hits = [];
  FIELDS.forEach(([key, labels]) => {
    labels.forEach(lab => {
      const re = new RegExp('(^|\\s)' + escRe(lab) + '\\s*[:\\-\\=]?\\s*', 'gi');
      let m;
      while ((m = re.exec(raw))) {
        const sep = (m[1] || '').length;
        hits.push({ key, index: m.index + sep, end: m.index + m[0].length });
        if (m[0].length === 0) re.lastIndex++;
      }
    });
  });

  hits.sort((a, b) => (a.index !== b.index ? a.index - b.index : b.end - a.end));
  const kept = [];
  for (const h of hits) {
    const last = kept[kept.length - 1];
    if (last && h.index >= last.index && h.index <= last.end) continue;
    kept.push(h);
  }
  kept.sort((a, b) => a.end - b.end);
  kept.forEach((h, i) => {
    const nextStart = i + 1 < kept.length ? kept[i + 1].index : raw.length;
    const prevEnd = i > 0 ? kept[i - 1].end : 0;
    const after = raw.slice(h.end, nextStart).trim().replace(/[:.,;]+$/, '');
    const before = raw.slice(prevEnd, h.index).trim().replace(/^[:.,;\s]+/, '');
    const val = after || before;
    if (val) set(h.key, val);
  });

  if (!data.group) {
    if (hasWord(raw, 'বিজ্ঞান') || hasWord(raw, 'সায়েন্স') || hasWord(raw, 'সায়েন্স') || /\bscience\b/i.test(raw)) data.group = 'Science';
    else if (hasWord(raw, 'ব্যবসায়') || hasWord(raw, 'ব্যবসায়') || hasWord(raw, 'কমার্স') || /\b(commerce|business)\b/i.test(raw)) data.group = 'Commerce';
    else if (hasWord(raw, 'মানবিক') || /\b(arts|humanities)\b/i.test(raw)) data.group = 'Arts';
  }

  const out = {};
  if (data.name) out.name = data.name.replace(/\.$/, '');
  if (data.roll) { const r = parseInt(data.roll, 10); if (!isNaN(r)) out.roll = r; }
  if (data.class) { const c = parseInt(data.class, 10); if (!isNaN(c) && c >= 1 && c <= 12) out.class = String(c); }
  if (data.group) {
    const g = data.group.toLowerCase();
    if (hasWord(g, 'science') || hasWord(g, 'বিজ্ঞান') || hasWord(g, 'সায়েন্স') || hasWord(g, 'সায়েন্স')) out.group = 'Science';
    else if (hasWord(g, 'commerce') || hasWord(g, 'business') || hasWord(g, 'ব্যবসায়') || hasWord(g, 'ব্যবসায়') || hasWord(g, 'কমার্স') || hasWord(g, 'বাণিজ্য')) out.group = 'Commerce';
    else if (hasWord(g, 'arts') || hasWord(g, 'humanities') || hasWord(g, 'মানবিক')) out.group = 'Arts';
  }
  if (data.section) {
    const sm = data.section.trim().toUpperCase().match(/\b[ABC]\b/);
    out.section = sm ? sm[0] : (data.section.trim() === 'এ' ? 'A' : data.section.trim() === 'বি' ? 'B' : data.section.trim() === 'সি' ? 'C' : undefined);
    if (!out.section) delete out.section;
  }
  if (data.gender) {
    // Female FIRST: indexOf('male') matches "Female" — must not mislabel girls.
    const gd = data.gender.toLowerCase().trim();
    const hasWord = (s, w) => new RegExp('(^|[^\\w\\u0980-\\u09FF])' + w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '([^\\w\\u0980-\\u09FF]|$)').test(s);
    if (gd.indexOf('female') !== -1 || gd.indexOf('মেয়ে') !== -1 || hasWord(gd, 'girl') || gd === 'f') out.gender = 'Female';
    else if (hasWord(gd, 'male') || hasWord(gd, 'boy') || gd === 'm' || gd.indexOf('ছেলে') !== -1) out.gender = 'Male';
    else out.gender = 'Other';
  }
  if (data.dob) {
    const d = normalizeDob(data.dob);
    if (/^\d{4}-\d{2}-\d{2}$/.test(d || '')) out.dob = d; // strict YYYY-MM-DD only
  }
  if (data.birth_cert_no) {
    const digits = String(data.birth_cert_no).replace(/\D/g, '');
    const m17 = digits.match(/\d{17}/);
    if (m17) out.birth_cert_no = m17[0];
    else if (String(data.birth_cert_no).trim()) out.birth_cert_no = String(data.birth_cert_no).trim();
  }
  if (data.religion) {
    const rl = data.religion.toLowerCase();
    if (rl.indexOf('islam') !== -1 || rl.indexOf('ইসলাম') !== -1) out.religion = 'Islam';
    else if (rl.indexOf('hindu') !== -1 || rl.indexOf('হিন্দু') !== -1) out.religion = 'Hinduism';
    else if (rl.indexOf('christ') !== -1 || rl.indexOf('খ্রিস্ট') !== -1) out.religion = 'Christianity';
    else if (rl.indexOf('buddh') !== -1 || rl.indexOf('বৌদ্ধ') !== -1) out.religion = 'Buddhism';
    else if (rl.indexOf('other') !== -1 || rl.indexOf('অন্য') !== -1) out.religion = 'Other';
  }
  if (data.blood_group) {
    const bm = data.blood_group.toUpperCase().match(/(A|B|AB|O)[+-]/);
    out.blood_group = bm ? bm[0] : (/unknown|জানা নেই/.test(data.blood_group.toLowerCase()) ? 'Unknown' : undefined);
    if (!out.blood_group) delete out.blood_group;
  }
  if (data.optional_subject) {
    const os = data.optional_subject.toLowerCase();
    out.optional_subject = os.indexOf('home science') !== -1 || os.indexOf('গৃহ') !== -1 || os.indexOf('হোম') !== -1 ? 'Home Science'
      : os.indexOf('higher') !== -1 || os.indexOf('উচ্চ') !== -1 || os.indexOf('হায়ার') !== -1 || os.indexOf('highermath') !== -1 ? 'Higher Mathematics'
        : os.indexOf('agriculture') !== -1 || os.indexOf('কৃষি') !== -1 || os.indexOf('কৃষিবিজ্ঞান') !== -1 ? 'Agriculture Studies'
          : data.optional_subject.replace(/\.$/, '').trim();
  }
  ['father_name', 'mother_name', 'guardian_name', 'address', 'email', 'student_id'].forEach(k => {
    if (data[k]) out[k] = data[k].replace(/\.$/, '');
  });
  if (data.phone) out.phone = data.phone.replace(/[\s\-]/g, '');
  if (data.guardian_phone) out.guardian_phone = data.guardian_phone.replace(/[\s\-]/g, '');
  return out;
}

export const PROMPT_TEMPLATE = `ছাত্র / ছাত্রীর পূর্ণ বিবরণ STRICT "Label: Value" ফরম্যাটে, প্রতি লাইনে ঠিক একটি করে দিন — যতগুলো জানেন ততগুলো (নাম ও রোল বাধ্যতামূলক):
Name: ...
Roll: ...
Class: ...
Group / Section: ...
Father's Name: ...
Mother's Name: ...
Guardian Name: ...
Guardian Phone: ...
Phone: ...
Email: ...
Date of Birth: 2011-05-15
Gender: Female
Religion: Islam / Hindu / Christian / Buddhist / Other
Blood Group: A+ / B+ / O-
Optional Subject: ...
Birth Certificate No: 20110515001234567
Address: ...

কঠোর নিয়ম (একটিও ভাঙা যাবে না):
1. "Date of Birth"-এ শুধু YYYY-MM-DD ফরম্যাটের তারিখ দিবেন (যেমন 2011-05-15) — জন্ম নিবন্ধন নম্বর কখনোই এখানে দিবেন না।
2. "Gender"-এ শিক্ষার্থীর আসল লিঙ্গ দিবেন (Male / Female) — ভুলেও বদলাবেন না।
3. "Birth Certificate No"-তে শুধু ১৭ সংখ্যার নম্বর দিবেন, নিজস্ব আলাদা লাইনে।
4. প্রতিটি লাইন "Label: Value" আকারে রাখুন — লাইন বা মান এদিক-ওদিক সরাবেন না।`;