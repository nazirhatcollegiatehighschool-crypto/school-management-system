// ------------------------------------------------------------------
// NCTB exam-category catalog + mark-weightage engine (Q1 + Q2).
//
// Every class maps to a BAND, and a band decides which exam kinds may
// exist for it. The event kind must be legal for that band or the API
// rejects the event with 400 - this is the enforcement point that stops
// someone creating a "Half-Yearly" for Class 10 or a "Model Test" for
// Class 6.
//
// The same table carries the weight_pct used by session_gpa.js to fold
// several exam kinds into ONE session GPA (CA 20 / Half-Yearly 30 /
// Annual 50 for classes 6-9, for example).
// ------------------------------------------------------------------

const pool = require('./db');

const BAND_69 = '6-9', BAND_10 = '10', BAND_SSC = 'ssc';

// Cache the catalog for 60s: it changes rarely and every event create
// hits it.
let cache = null;
let cacheAt = 0;
const TTL = 60 * 1000;

async function loadCatalog(force) {
  if (!force && cache && Date.now() - cacheAt < TTL) return cache;
  const [rows] = await pool.query(
    'SELECT band, exam_kind, weight_pct, is_promotion_source FROM exam_catalog'
  );
  const map = {};
  for (const r of rows) {
    map[r.band] = map[r.band] || {};
    map[r.band][r.exam_kind] = {
      weight_pct: Number(r.weight_pct || 0),
      is_promotion_source: Number(r.is_promotion_source || 0) === 1,
    };
  }
  cache = map;
  cacheAt = Date.now();
  return cache;
}

/**
 * Band for a class, derived from its NAME (not its id) so a class row
 * re-used across sessions still lands in the right band.
 */
function bandOfClass(className) {
  const n = String(className || '');
  if (/class\s*10/i.test(n)) return BAND_10;
  if (/ssc/i.test(n)) return BAND_SSC;
  const m = n.match(/(\d+)/);
  if (m) {
    const lvl = Number(m[1]);
    if (lvl >= 6 && lvl <= 9) return BAND_69;
  }
  // Class 11+ / anything unknown: treat as SSC band (board-style).
  return BAND_SSC;
}

/** Legal exam kinds for a band. */
async function allowedKinds(band) {
  const cat = await loadCatalog();
  return Object.keys(cat[band] || {});
}

/** Weight of one exam kind inside its band (0 if unknown). */
async function weightFor(band, kind) {
  const cat = await loadCatalog();
  const e = cat[band] && cat[band][kind];
  return e ? e.weight_pct : 0;
}

/**
 * Validate an event kind against a class's band.
 * Returns { ok:true, band, weight_pct } or { ok:false, error }.
 */
async function validateEventKind(className, examKind) {
  const band = bandOfClass(className);
  const cat = await loadCatalog();
  const kinds = cat[band] || {};
  const k = String(examKind || 'other');
  if (!kinds[k]) {
    const list = Object.keys(kinds).join(', ');
    return {
      ok: false,
      error: `Class "${className}" belongs to band ${band}; exam kind "${k}" is not allowed here. Allowed: ${list}`,
    };
  }
  return { ok: true, band, weight_pct: kinds[k].weight_pct, is_promotion_source: kinds[k].is_promotion_source };
}

/** Which exam_kind a band promotes from (used by the promotion engine). */
async function promotionSourceKind(band) {
  const cat = await loadCatalog();
  const kinds = cat[band] || {};
  for (const k of Object.keys(kinds)) if (kinds[k].is_promotion_source) return k;
  // Fallback to the historical rules.
  return band === BAND_10 ? 'test' : 'annual';
}

module.exports = {
  BAND_69, BAND_10, BAND_SSC,
  loadCatalog, bandOfClass, allowedKinds, weightFor,
  validateEventKind, promotionSourceKind,
  invalidate() { cache = null; },
};
