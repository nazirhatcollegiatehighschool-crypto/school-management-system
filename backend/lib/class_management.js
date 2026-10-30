const CLASS_GROUP_KEYS = new Set([
  'arts', 'humanities', 'humanity', 'science', 'commerce', 'business', 'businessstudies',
]);

function normalizeClassInput(body = {}, current = {}) {
  const value = (key) => Object.prototype.hasOwnProperty.call(body, key)
    ? body[key]
    : current[key];
  const rawTeacherId = value('teacher_id');
  const teacherId = rawTeacherId === undefined || rawTeacherId === null || rawTeacherId === ''
    ? null
    : Number(rawTeacherId);
  return {
    name: String(value('name') || '').trim(),
    section: String(value('section') || '').trim(),
    group_name: String(value('group_name') || '').trim() || null,
    teacher_id: teacherId,
  };
}

function validateClassInput(input) {
  const errors = [];
  if (!input.name) errors.push('Class name is required.');
  else if (input.name.length > 30) errors.push('Class name must be 30 characters or fewer.');
  if (!input.section) errors.push('Section is required.');
  else if (input.section.length > 20) errors.push('Section must be 20 characters or fewer.');
  if (input.group_name && input.group_name.length > 20) errors.push('Group name must be 20 characters or fewer.');
  if (input.teacher_id !== null && (!Number.isInteger(input.teacher_id) || input.teacher_id < 1)) {
    errors.push('Select a valid class teacher.');
  }
  const level = Number((input.name.match(/\d+/) || [])[0]);
  const groupKey = String(input.group_name || '').toLowerCase().replace(/[^a-z]/g, '');
  const validGroup = CLASS_GROUP_KEYS.has(groupKey);
  if ((level === 9 || level === 10) && !validGroup) {
    errors.push('Classes 9–10 require Arts/Humanities, Science, or Commerce/Business as the group.');
  }
  return errors;
}

module.exports = { normalizeClassInput, validateClassInput };
