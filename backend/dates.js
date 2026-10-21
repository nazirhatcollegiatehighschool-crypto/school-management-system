// ------------------------------------------------------------------
// Safe date formatting for `pg` DATE columns.
//
// node-postgres parses PostgreSQL `date` values into JS Date objects set
// to LOCAL midnight. That makes both of these wrong:
//   String(d).slice(0, 10)  -> "Sun Sep 13"   (weekday prefix, garbage)
//   d.toISOString().slice(0,10)               -> previous day in any
//                                                non-UTC timezone
// Use ymd() to get the calendar date the row actually holds.
// ------------------------------------------------------------------

function ymd(d) {
  if (d == null) return null;
  if (d instanceof Date && !isNaN(d.getTime())) {
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  }
  return String(d).slice(0, 10);
}

/** Today's date in Bangladesh time (NOT the server/UTC date). */
function dhakaToday(d = new Date()) {
  return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
}

module.exports = { ymd, dhakaToday };
