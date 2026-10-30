const EDITABLE_FIELDS = [
  'student_code', 'name', 'dob', 'roll', 'class_id', 'religion', 'guardian_id',
  'guardian_name', 'guardian_phone', 'guardian_email', 'address', 'father_name',
  'mother_name', 'birth_cert_no', 'gender', 'blood_group', 'optional_subject',
  'compulsory_subject', 'phone', 'email', 'receives_scholarship', 'status',
];

const { normalizeGender } = require('./gender');

const STRING_LIMITS = {
  student_code: 20,
  name: 100,
  religion: 20,
  guardian_name: 100,
  guardian_phone: 20,
  guardian_email: 100,
  address: 255,
  father_name: 100,
  mother_name: 100,
  birth_cert_no: 50,
  gender: 10,
  blood_group: 5,
  optional_subject: 60,
  compulsory_subject: 120,
  phone: 20,
  email: 100,
  status: 50,
};

function validateStudentProfileFields(body) {
  const errors = [];
  for (const [field, limit] of Object.entries(STRING_LIMITS)) {
    if (!Object.prototype.hasOwnProperty.call(body, field) || body[field] == null) continue;
    if (typeof body[field] !== 'string') {
      errors.push(`${field} must be text`);
    } else if (body[field].length > limit) {
      errors.push(`${field} cannot exceed ${limit} characters`);
    }
  }
  if (Object.prototype.hasOwnProperty.call(body, 'dob') &&
      body.dob != null && body.dob !== '' && typeof body.dob !== 'string') {
    errors.push('dob must be a date string');
  }
  if (Object.prototype.hasOwnProperty.call(body, 'receives_scholarship') &&
      ![true, false, 0, 1, 'true', 'false', '0', '1'].includes(body.receives_scholarship)) {
    errors.push('receives_scholarship must be a boolean');
  }
  return errors;
}

function toDatabaseBoolean(value) {
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === 'true' || normalized === '1';
  }
  return value === true || value === 1;
}

/** Build a safe partial update: omitted fields stay untouched; explicit null clears nullable fields. */
function buildStudentUpdate(body, curriculum) {
  const values = {};
  for (const field of EDITABLE_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(body, field)) values[field] = body[field];
  }

  if (Object.prototype.hasOwnProperty.call(body, 'student_code')) {
    const code = String(body.student_code || '').trim();
    if (code) values.student_code = code;
    else delete values.student_code;
  }
  if (body.status === undefined || body.status === null || body.status === '') {
    delete values.status;
  }

  if (Object.prototype.hasOwnProperty.call(body, 'religion')) {
    values.religion = body.religion;
  }
  if (Object.prototype.hasOwnProperty.call(body, 'gender')) {
    values.gender = normalizeGender(body.gender);
  }
  if (Object.prototype.hasOwnProperty.call(body, 'receives_scholarship')) {
    values.receives_scholarship = toDatabaseBoolean(body.receives_scholarship);
  }
  if (Object.prototype.hasOwnProperty.call(body, 'birth_cert_no')) {
    values.birth_cert_no = String(body.birth_cert_no).trim();
    values.birth_cert_placeholder = false;
  }

  if (Object.prototype.hasOwnProperty.call(body, 'class_id') ||
      Object.prototype.hasOwnProperty.call(body, 'optional_subject') ||
      Object.prototype.hasOwnProperty.call(body, 'compulsory_subject')) {
    values.optional_subject = curriculum.optional_subject || null;
    values.compulsory_subject = curriculum.compulsory_subject || null;
  }

  return values;
}

module.exports = { buildStudentUpdate, toDatabaseBoolean, validateStudentProfileFields };
