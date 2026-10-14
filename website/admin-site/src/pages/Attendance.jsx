import { useState, useEffect } from 'react';
import { api } from '../api';

const FINAL_STYLE = {
  TRUANT_UNAUTHORIZED: { bg: '#fef2f2', fg: '#b91c1c', bn: '🚨 পলাতক (বিনা অনুমতিতে)' },
  LATE_ARRIVAL_UNCHECKED: { bg: '#fffbeb', fg: '#b45309', bn: 'দেরিতে আগমন (যাচাই বাকি)' },
  PRESENT_FULL_DAY: { bg: '#ecfdf5', fg: '#047857', bn: 'সারাদিন উপস্থিত' },
  EARLY_DEPARTURE_AUTHORIZED: { bg: '#eff6ff', fg: '#1d4ed8', bn: 'অনুমতি নিয়ে প্রস্থান' },
  APPROVED_LEAVE: { bg: '#f5f3ff', fg: '#6d28d9', bn: 'অনুমোদিত ছুটি' },
  ABSENT_FULL_DAY: { bg: '#f1f5f9', fg: '#475569', bn: 'সারাদিন অনুপস্থিত' },
  PENDING_P5: { bg: '#fffbeb', fg: '#92400e', bn: '৫ম পিরিয়ড বাকি' },
};

export default function Attendance() {
  const [rows, setRows] = useState([]);
  const [classes, setClasses] = useState([]);
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [classId, setClassId] = useState('');
  const [session, setSession] = useState('');
  const [exceptions, setExceptions] = useState([]);
  const [leaves, setLeaves] = useState([]);
  const [tab, setTab] = useState('records');
  const [err, setErr] = useState('');

  useEffect(() => { api('/admin/classes').then(setClasses).catch(() => {}); }, []);
  useEffect(() => {
    const p = new URLSearchParams();
    if (date) p.set('date', date);
    if (classId) p.set('class_id', classId);
    if (session) p.set('session', session);
    api('/admin/attendance?' + p.toString()).then(setRows).catch(e => setErr(e.message));
    api('/admin/attendance/exceptions?date=' + date).then(r => setExceptions(r.exceptions || [])).catch(() => {});
    api('/admin/leave-tickets?status=pending').then(setLeaves).catch(() => {});
  }, [date, classId, session]);

  const decideLeave = async (id, approve) => {
    // Leave approve/reject lives in teacher routes for the class teacher AND
    // admin (same RBAC family). Admin panel calls the teacher endpoint with
    // the admin token — approved ticket instantly re-synthesizes truancy.
    try {
      const base = window.__API_BASE__ || '';
      const tok = localStorage.getItem('token') || '';
      const r = await fetch(base + '/api/teacher/leave-tickets/' + id + '/' + (approve ? 'approve' : 'reject'), {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + tok },
      });
      if (!r.ok) throw new Error((await r.json()).error || 'failed');
      setLeaves(leaves.filter(l => l.id !== id));
    } catch (e) { setErr(e.message); }
  };

  const st = (f) => FINAL_STYLE[f] || { bg: '#f1f5f9', fg: '#475569', bn: f || '—' };

  return (
    <div>
      {err && <div className="error-msg">{err}</div>}

      {exceptions.length > 0 && (
        <div className="panel" style={{ borderLeft: '5px solid #dc2626', background: '#fef2f2' }}>
          <h3>🚨 Exception Feed — {date} ({exceptions.length} জন)</h3>
          <table>
            <thead><tr><th>Student</th><th>Class</th><th>Flag</th></tr></thead>
            <tbody>
              {exceptions.map(e => (
                <tr key={e.student_id}>
                  <td><b>{e.student_name}</b> (Roll {e.roll})</td>
                  <td>{e.class_name} ({e.section})</td>
                  <td><span className="badge" style={{ background: st(e.final_state).bg, color: st(e.final_state).fg }}>
                    {e.final_bn || st(e.final_state).bn}
                  </span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className="panel">
        <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
          {[['records', '📋 Records'], ['sessions', '🪟 Session Windows'], ['leaves', `🏖️ Leave Inbox${leaves.length ? ` (${leaves.length})` : ''}`]].map(([k, label]) => (
            <button key={k} className={'btn sm' + (tab === k ? '' : ' ghost')} onClick={() => setTab(k)}>{label}</button>
          ))}
        </div>

        {tab === 'records' && (<>
          <h3>Attendance — Dual Window (সকাল 10:15–11:00 • ৫ম পিরিয়ড 2:00–2:40)</h3>
          <div className="filters">
            <input type="date" value={date} onChange={e => setDate(e.target.value)} />
            <select value={classId} onChange={e => setClassId(e.target.value)}>
              <option value="">All classes</option>
              {classes.map(c => <option key={c.id} value={c.id}>{c.name} - {c.section}</option>)}
            </select>
            <select value={session} onChange={e => setSession(e.target.value)}>
              <option value="">Both sessions</option>
              <option value="morning">🌅 Morning only</option>
              <option value="p5">🕑 Period-5 only</option>
            </select>
          </div>
          <table>
            <thead><tr><th>Date</th><th>Session</th><th>Student</th><th>Class</th><th>Roll</th><th>Mark</th><th>Final State</th><th>Remark</th></tr></thead>
            <tbody>
              {rows.length === 0 && <tr><td colSpan="8" className="muted">No records found.</td></tr>}
              {rows.map(a => (
                <tr key={a.id}>
                  <td>{String(a.date).slice(0, 10)}</td>
                  <td>{a.session === 'p5' ? '🕑 P5' : '🌅 Morning'}{a.override_reason ? ' (override)' : ''}</td>
                  <td>{a.student_name}</td>
                  <td>{a.class_name} ({a.section})</td>
                  <td>{a.roll}</td>
                  <td><span className={'badge ' + a.status}>{a.status}</span></td>
                  <td>{a.final_state
                    ? <span className="badge" style={{ background: st(a.final_state).bg, color: st(a.final_state).fg }}>{st(a.final_state).bn}</span>
                    : <span className="muted">—</span>}</td>
                  <td>{a.remark || '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>)}

        {tab === 'sessions' && (
          <div>
            <h3>Session Windows (server-clock enforced)</h3>
            <div className="cards">
              <div className="card"><b>🌅 Morning Entry</b><br />10:15 AM – 11:00 AM<br /><span className="muted">Roll call • PRESENT / ABSENT / LEAVE</span></div>
              <div className="card"><b>🕑 Period-5 Verify</b><br />2:00 PM – 2:40 PM<br /><span className="muted">Mid-day check • P5 present/absent</span></div>
              <div className="card"><b>⚙️ Synthesis</b><br />Automatic<br /><span className="muted">Morning + P5 + leave ticket → final state, truancy alert</span></div>
            </div>
            <p className="muted" style={{ fontSize: 12 }}>Window-এর বাইরে entry 403 হয়; admin override করলে reason audit log-এ থাকে। Device clock কখনো trust করা হয় না — server time-ই সত্য।</p>
          </div>
        )}

        {tab === 'leaves' && (
          <div>
            <h3>Leave Inbox (pending: {leaves.length})</h3>
            {leaves.length === 0 && <p className="muted">কোনো pending ছুটির আবেদন নেই।</p>}
            <table>
              <thead><tr><th>Date</th><th>Student</th><th>Kind</th><th>Reason</th><th></th></tr></thead>
              <tbody>
                {leaves.map(l => (
                  <tr key={l.id}>
                    <td>{String(l.leave_date).slice(0, 10)}</td>
                    <td>{l.student_name} (Roll {l.roll}) — {l.class_name}</td>
                    <td>{l.kind}</td>
                    <td>{l.reason || '-'}</td>
                    <td style={{ whiteSpace: 'nowrap' }}>
                      <button className="btn sm" onClick={() => decideLeave(l.id, true)}>Approve</button>{' '}
                      <button className="btn sm ghost" onClick={() => decideLeave(l.id, false)}>Reject</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
