'use strict';

const CANONICAL_SESSION_EXAMS = Object.freeze([
  'half_yearly',
  'annual',
  'pretest',
  'test',
  'special_model_test',
]);

function sessionYear(value) {
  const match = String(value || '').match(/(?:19|20)\d{2}/);
  return match ? Number(match[0]) : null;
}

function isPublished(value) {
  return value === true || Number(value) === 1;
}

function eventIsPublished(events, year, kind) {
  return events.some(event => Number(event.year) === Number(year) &&
    event.exam_kind === kind && isPublished(event.is_published));
}

function sessionIsOpen(year, firstYear, events) {
  return Number(year) === Number(firstYear) ||
    eventIsPublished(events, Number(year) - 1, 'test');
}

function sessionIsComplete(year, events) {
  return CANONICAL_SESSION_EXAMS.every(kind =>
    eventIsPublished(events, year, kind));
}

function advanceActiveYear(startYear, lastYear, events) {
  let year = Number(startYear);
  while (year < Number(lastYear) && sessionIsOpen(year + 1, startYear, events)) {
    year += 1;
  }
  return year;
}

function buildSessionOptions({ firstYear, lastYear = 2050, activeYear, sessions, events }) {
  const byYear = new Map(sessions.map(row => [sessionYear(row.name), row]));
  const options = [];
  for (let year = Number(firstYear); year <= Number(lastYear); year += 1) {
    if (year < Number(activeYear) || sessionIsComplete(year, events)) continue;
    const row = byYear.get(year);
    if (!row) continue;
    const open = sessionIsOpen(year, firstYear, events);
    options.push({
      ...row,
      year,
      is_active: Number(row.is_active) === 1 || row.is_active === true,
      is_open: open,
      is_complete: false,
      blocked_reason: open ? null : `আগের session ${year - 1}-এর Class 10 Test exam publish হয়নি।`,
    });
  }
  return options;
}

module.exports = {
  CANONICAL_SESSION_EXAMS,
  sessionYear,
  eventIsPublished,
  sessionIsOpen,
  sessionIsComplete,
  advanceActiveYear,
  buildSessionOptions,
};
