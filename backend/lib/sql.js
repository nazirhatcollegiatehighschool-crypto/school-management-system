function inClause(column, values) {
  const list = (values || []).filter(value => value !== undefined && value !== null);
  if (!list.length) return { sql: '1=0', params: [] };
  // A scalar bind inside IN (?) becomes an invalid PostgreSQL ANY(scalar).
  if (list.length === 1) return { sql: `${column} = ?`, params: [list[0]] };
  return { sql: `${column} IN (${list.map(() => '?').join(',')})`, params: list };
}

module.exports = { inClause };
