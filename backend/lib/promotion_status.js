function isValidPromotionStatusPair(status, decision) {
  return (
    (status === 'approved' && decision === 'promoted') ||
    (status === 'retained' && decision === 'retained')
  );
}

module.exports = { isValidPromotionStatusPair };
