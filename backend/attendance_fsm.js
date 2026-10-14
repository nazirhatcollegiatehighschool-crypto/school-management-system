/**
 * attendance_fsm.js — Dual-Window Attendance & Truancy Detector Engine.
 *
 * SCIENTIFIC ARCHITECTURE (deterministic Finite State Machine):
 *
 * The school day has TWO mandatory verification windows. A single daily mark
 * cannot detect mid-day disappearance (the truancy problem), so the engine
 * stores BOTH session marks and SYNTHESIZES the final day state:
 *
 *   Session 1 (Morning Entry)      10:15 – 11:00
 *     states: PRESENT_MORNING | ABSENT_MORNING | APPROVED_LEAVE
 *   Session 2 (Period-5 Verify)    14:00 – 14:40
 *     states: PRESENT_P5 | ABSENT_P5
 *
 * Synthesis matrix (pure function of the two session marks + leave ticket):
 *   PRESENT_MORNING + PRESENT_P5  -> PRESENT_FULL_DAY
 *   PRESENT_MORNING + ABSENT_P5   + valid leave -> EARLY_DEPARTURE_AUTHORIZED
 *   PRESENT_MORNING + ABSENT_P5   + no leave    -> TRUANT_UNAUTHORIZED (flag!)
 *   ABSENT_MORNING  + PRESENT_P5  -> LATE_ARRIVAL_UNCHECKED (admin clearance)
 *   APPROVED_LEAVE  + *           -> APPROVED_LEAVE (morning leave covers day)
 *   ABSENT_MORNING  + ABSENT_P5   -> ABSENT_FULL_DAY
 *   <morning only>                -> PENDING_P5 (awaiting 2nd window)
 *
 * Time-guard: entries outside a window are REJECTED unless override=1 with a
 * reason (admin only, audit-logged). Server clock is authoritative — client
 * timestamps are never trusted (time-tampering defense).
 *
 * Storage: the existing `attendance` row gains a `session` column
 * ('morning'|'p5', UNIQUE(student_id,date,session)) plus a synthesized
 * `final_state` column. Legacy single-mark rows keep session='morning' so
 * old data stays valid (pending until P5 arrives).
 */

const SESSION_MORNING = 'morning';
const SESSION_P5 = 'p5';

// Window boundaries in Asia/Dhaka local time (server converts with +06:00).
// Morning: 10:15 AM – 11:10 AM (assembly + first roll call).
// Period-5: 2:00 PM – 2:45 PM (mid-day verification).
const WINDOWS = {
  morning: { start: '10:15', end: '11:10', label: 'সকালের হাজিরা (10:15–11:10)' },
  p5: { start: '14:00', end: '14:45', label: '৫ম পিরিয়ড যাচাই (2:00–2:45)' },
};

const FINAL = {
  PRESENT_FULL_DAY: 'PRESENT_FULL_DAY',
  TRUANT_UNAUTHORIZED: 'TRUANT_UNAUTHORIZED',
  EARLY_DEPARTURE_AUTHORIZED: 'EARLY_DEPARTURE_AUTHORIZED',
  LATE_ARRIVAL_UNCHECKED: 'LATE_ARRIVAL_UNCHECKED',
  APPROVED_LEAVE: 'APPROVED_LEAVE',
  ABSENT_FULL_DAY: 'ABSENT_FULL_DAY',
  PENDING_P5: 'PENDING_P5',
};

const FINAL_BN = {
  PRESENT_FULL_DAY: 'সারাদিন উপস্থিত',
  TRUANT_UNAUTHORIZED: '🚨 বিনা অনুমতিতে চলে গেছে (পলাতক)',
  EARLY_DEPARTURE_AUTHORIZED: 'অনুমতি নিয়ে আগে চলে গেছে',
  LATE_ARRIVAL_UNCHECKED: 'দেরিতে এসেছে (যাচাই বাকি)',
  APPROVED_LEAVE: 'অনুমোদিত ছুটি',
  ABSENT_FULL_DAY: 'সারাদিন অনুপস্থিত',
  PENDING_P5: '৫ম পিরিয়ড যাচাই বাকি',
};

function toDhakaMinutes(d = new Date()) {
  const dhaka = new Date(d.getTime() + (6 * 60 + d.getTimezoneOffset()) * 60000);
  return dhaka.getHours() * 60 + dhaka.getMinutes();
}

function hmToMin(hm) {
  const [h, m] = String(hm).split(':').map(Number);
  return h * 60 + m;
}

/** Which session window is open RIGHT NOW (server clock)? null = none open. */
function currentWindow(now = new Date()) {
  const mins = toDhakaMinutes(now);
  for (const key of [SESSION_MORNING, SESSION_P5]) {
    const w = WINDOWS[key];
    if (mins >= hmToMin(w.start) && mins <= hmToMin(w.end)) return key;
  }
  return null;
}

function windowFor(session) { return WINDOWS[session] || null; }

/**
 * Pure synthesis: (morningStatus, p5Status, hasLeaveTicket) -> final state.
 * morningStatus: 'present'|'absent'|'late'|null (null = not yet recorded)
 * p5Status:      same
 * hasLeave:      boolean — approved leave/early-departure ticket exists
 */
function synthesize(morningStatus, p5Status, hasLeave) {
  const m = morningStatus || null;
  const p = p5Status || null;
  if (m === 'leave' || m === 'approved_leave') return FINAL.APPROVED_LEAVE;
  if (m == null) return FINAL.PENDING_P5;
  if (p == null) return FINAL.PENDING_P5;
  const mPresent = (m === 'present' || m === 'late');
  const pPresent = (p === 'present' || p === 'late');
  if (mPresent && pPresent) return FINAL.PRESENT_FULL_DAY;
  if (mPresent && !pPresent) {
    return hasLeave ? FINAL.EARLY_DEPARTURE_AUTHORIZED : FINAL.TRUANT_UNAUTHORIZED;
  }
  if (!mPresent && pPresent) return FINAL.LATE_ARRIVAL_UNCHECKED;
  return FINAL.ABSENT_FULL_DAY;
}

/**
 * Guard: is a session entry allowed at `now`?
 * Returns {ok:true} or {ok:false, reason}.
 * override=true requires admin role + reason (caller enforces + logs).
 */
function guardWindow(session, now = new Date(), override = false) {
  const w = windowFor(session);
  if (!w) return { ok: false, reason: 'Unknown session' };
  if (override) return { ok: true, overridden: true };
  const mins = toDhakaMinutes(now);
  if (mins < hmToMin(w.start) || mins > hmToMin(w.end)) {
    return {
      ok: false,
      reason: `“${w.label}” সময়ের বাইরে entry বন্ধ। Admin override ছাড়া ${w.start}–${w.end}-এর বাইরে হাজিরা নেওয়া যাবে না।`,
      window: session,
    };
  }
  return { ok: true };
}

module.exports = {
  SESSION_MORNING, SESSION_P5, WINDOWS, FINAL, FINAL_BN,
  synthesize, guardWindow, currentWindow, windowFor, toDhakaMinutes,
};
