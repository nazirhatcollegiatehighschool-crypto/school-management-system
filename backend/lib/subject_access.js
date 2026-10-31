'use strict';

const { canonicalReligion, canonicalSubject } = require('../curriculum');

const RELIGION_SUBJECT_RE = /religion|islam|hindu|buddh|christian|ধর্ম|ইসলাম|হিন্দু|বৌদ্ধ|খ্রিস্ট/i;

function isReligionSubject(subjectName) {
  return RELIGION_SUBJECT_RE.test(String(subjectName || ''));
}

function religionFromSubjectName(subjectName) {
  const name = String(subjectName || '');
  if (/hindu/i.test(name)) return 'Hinduism';
  if (/christian/i.test(name)) return 'Christianity';
  if (/buddh/i.test(name)) return 'Buddhism';
  if (/islam|muslim/i.test(name)) return 'Islam';
  return null;
}

function defaultClassCurriculum(classInfo, gender) {
  const name = String(classInfo && (classInfo.class_name || classInfo.name) || '');
  const level = Number((name.match(/\d+/) || [])[0]);
  if (level !== 9 && level !== 10) return { optional_subject: null, compulsory_subject: null };
  const groupRaw = String(
    (classInfo && (classInfo.group_name || classInfo.section)) || ''
  ).toLowerCase();
  const group = /arts|humanit/.test(groupRaw) ? 'arts'
    : /commerce|business/.test(groupRaw) ? 'commerce'
    : /science/.test(groupRaw) ? 'science' : null;
  if (!group) return { optional_subject: null, compulsory_subject: null };
  const normalizedGender = String(gender || '').trim().toLowerCase();
  if (group === 'arts') {
    return {
      optional_subject: normalizedGender === 'male' ? 'Agriculture'
        : normalizedGender === 'female' ? 'Home Science' : null,
      compulsory_subject: 'Economics',
    };
  }
  if (group === 'commerce') {
    return {
      optional_subject: normalizedGender === 'male' ? 'Agriculture'
        : normalizedGender === 'female' ? 'Home Science' : null,
      compulsory_subject: null,
    };
  }
  return {
    optional_subject: ['male', 'female'].includes(normalizedGender) ? 'Higher Mathematics' : null,
    compulsory_subject: null,
  };
}

function studentMatchesSubject(student, subjectName, classInfo = null) {
  if (isReligionSubject(subjectName)) {
    const explicit = religionFromSubjectName(subjectName);
    const allowed = explicit ? new Set([canonicalReligion(explicit)]) : null;
    return allowed ? allowed.has(canonicalReligion(student.religion)) : true;
  }

  const canonical = canonicalSubject(subjectName);
  if (!canonical) return true;
  const selected = new Set([
    canonicalSubject(student.optional_subject),
    canonicalSubject(student.compulsory_subject),
  ].filter(Boolean));
  if (selected.size === 0) {
    const defaults = defaultClassCurriculum(classInfo, student.gender);
    const defaultSelected = new Set([
      canonicalSubject(defaults.optional_subject),
      canonicalSubject(defaults.compulsory_subject),
    ].filter(Boolean));
    return defaultSelected.has(canonical);
  }
  return selected.has(canonical);
}

module.exports = {
  isReligionSubject,
  religionFromSubjectName,
  studentMatchesSubject,
  defaultClassCurriculum,
};
