const test = require('node:test');
const assert = require('node:assert/strict');
const {
  CANONICAL_SESSION_EXAMS,
  sessionIsOpen,
  sessionIsComplete,
  advanceActiveYear,
  buildSessionOptions,
} = require('../lib/academic_session');

function eventsFor(year, publishedKinds) {
  return CANONICAL_SESSION_EXAMS.map(exam_kind => ({
    year,
    exam_kind,
    is_published: publishedKinds.includes(exam_kind) ? 1 : 0,
  }));
}

test('only a published prior-year Test opens the next session', () => {
  const events = [
    ...eventsFor(2026, ['annual', 'half_yearly']),
    ...eventsFor(2027, []),
  ];
  assert.equal(sessionIsOpen(2026, 2026, events), true);
  assert.equal(sessionIsOpen(2027, 2026, events), false);
  assert.equal(sessionIsOpen(2028, 2026, events), false);
  events.find(event => event.year === 2026 && event.exam_kind === 'test').is_published = 1;
  assert.equal(sessionIsOpen(2027, 2026, events), true);
  assert.equal(sessionIsOpen(2028, 2026, events), false);
});

test('publishing the current-session Test activates the next academic session', () => {
  const events = [...eventsFor(2026, ['test']), ...eventsFor(2027, [])];
  assert.equal(sessionIsComplete(2026, events), false);
  assert.equal(advanceActiveYear(2026, 2050, events), 2027);
  assert.equal(sessionIsOpen(2028, 2026, events), false);
  assert.equal(advanceActiveYear(2027, 2050, events), 2027);

  events.find(event => event.year === 2027 && event.exam_kind === 'test').is_published = 1;
  assert.equal(advanceActiveYear(2026, 2050, events), 2028);
});

test('published Test exams advance academic sessions continuously through 2045', () => {
  const events = [];
  for (let year = 2026; year < 2045; year += 1) {
    events.push(...eventsFor(year, ['test']));
  }
  assert.equal(advanceActiveYear(2026, 2045, events), 2045);
});

test('dashboard marks 2027 active after the 2026 Test is published', () => {
  const events = [...eventsFor(2026, ['test']), ...eventsFor(2027, [])];
  const activeYear = advanceActiveYear(2026, 2050, events);
  const sessions = [2026, 2027, 2028].map((year, index) => ({
    id: index + 1,
    name: String(year),
    is_active: year === activeYear ? 1 : 0,
  }));
  const options = buildSessionOptions({
    firstYear: activeYear,
    activeYear,
    lastYear: 2028,
    sessions,
    events,
  });
  assert.equal(activeYear, 2027);
  assert.deepEqual(options.map(session => session.year), [2027, 2028]);
  assert.equal(options[0].is_open, true);
  assert.equal(options[0].is_active, true);
  assert.equal(options[1].is_open, false);
});

test('sessions through 2050 are selectable placeholders without opening their exams', () => {
  const sessions = [2026, 2027, 2050].map((year, index) => ({
    id: index + 1,
    name: String(year),
    is_active: year === 2026 ? 1 : 0,
  }));
  const options = buildSessionOptions({
    firstYear: 2026,
    activeYear: 2026,
    lastYear: 2050,
    sessions,
    events: eventsFor(2026, []),
  });
  assert.equal(options.find(session => session.year === 2050).is_open, false);
  assert.match(options.find(session => session.year === 2050).blocked_reason, /Test exam publish/);
});
