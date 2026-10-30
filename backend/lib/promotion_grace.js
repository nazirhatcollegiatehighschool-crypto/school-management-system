function normalizeSubjectFamily(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/\b(1st|2nd|first|second)\b/g, '')
    .replace(/[^a-z0-9]/g, '');
}

function decideByGrace({ families, selectedSubjectNames }) {
  const selected = new Set((selectedSubjectNames || []).map(normalizeSubjectFamily));
  const failed = (families || [])
    .filter(family => !family.is_optional &&
      (family.letter_grade === 'F' || family.absent === true || family.letter_grade === 'Absent'))
    .map(family => String(family.subject || ''));
  const graceFailed = failed.filter(name => selected.has(normalizeSubjectFamily(name)));
  const ungracedFailed = failed.filter(name => !selected.has(normalizeSubjectFamily(name)));

  if (failed.length === 0) {
    return { status: 'eligible', decision: 'promoted', eligible: true, failed, graceFailed, ungracedFailed, autoGrace: false };
  }
  if (ungracedFailed.length === 0 && graceFailed.length > 0) {
    return { status: 'approved', decision: 'promoted', eligible: true, failed, graceFailed, ungracedFailed, autoGrace: true };
  }
  return { status: 'not_eligible', decision: 'retained', eligible: false, failed, graceFailed, ungracedFailed, autoGrace: false };
}

function decidePromotionByGrace({ families, selectedSubjectNames, resultStatus }) {
  const outcome = decideByGrace({ families, selectedSubjectNames });
  if (resultStatus === 'ABSENT' || !(families || []).length) {
    return {
      ...outcome,
      status: 'not_eligible',
      decision: 'retained',
      eligible: false,
      autoGrace: false,
    };
  }
  return {
    ...outcome,
    decision: outcome.eligible ? 'promoted' : 'retained',
  };
}

module.exports = { normalizeSubjectFamily, decideByGrace, decidePromotionByGrace };
