import { useState, useEffect } from 'react';
import { api } from '../api';

// Promotion execution: pick a PUBLISHED Annual (6-9) / Test (10) event +
// class, review per-student decisions (Promoted / Grace / Retained),
// eligible students are pre-checked and move automatically on execute.
export default function Promotions() {
  const [events, setEvents] = useState([]);
  const [classes, setClasses] = useState([]);
  const [eventId, setEventId] = useState('');
  const [classId, setClassId] = useState('');
  const [review, setReview] = useState(null);
  const [checks, setChecks] = useState({});
  const [overrides, setOverrides] = useState({});
  const [grace, setGrace] = useState('0');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');

  const load = () => {
    api('/results/events?published=1').then(setEvents).catch(e => setErr(e.message));
    api('/admin/classes').then(setClasses).catch(() => {});
  };
  useEffect(load, []);

  const promoEvents = events.filter(e => e.exam_kind === 'annual' || e.exam_kind === 'test');

  const doReview = async () => {
    setErr(''); setMsg(''); setBusy(true); setReview(null);
    try {
      const r = await api('/admin/promote/review', { method: 'POST', body: { class_id: Number(classId), event_id: Number(eventId) } });
      setReview(r);
      setGrace(String(r.grace_failed ?? 0));
      const c = {}, o = {};
      r.review.forEach(s => { c[s.id] = !!s.eligible; o[s.id] = 'auto'; });
      setChecks(c); setOverrides(o);
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };

  const saveGrace = async () => {
    setErr(''); setMsg('');
    const g = Number(grace);
    if (!Number.isInteger(g) || g < 0 || g > 11) { setErr('Grace 0..11 হতে হবে'); return; }
    try {
      await api('/admin/promote/grace', { method: 'PUT', body: { class_id: Number(classId), exam_type: review.kind, grace_failed: g } });
      setMsg('Grace rule saved — আবার Review করুন।');
      doReview();
    } catch (ex) { setErr(ex.message); }
  };

  const doExecute = async () => {
    const rows = (review.review || []).map(s => {
      const ov = overrides[s.id];
      const promote = ov === 'auto' ? !!checks[s.id] : ov === 'promoted';
      const decision = ov === 'auto' ? s.decision : (ov === 'promoted' ? (s.decision === 'grace_promoted' ? 'grace_promoted' : 'admin_override') : 'retained');
      return { id: s.id, promote, decision, final_gpa: s.final_gpa };
    }).filter(s => s.promote || true);
    const moving = rows.filter(s => s.promote).length;
    if (!window.confirm(`${moving} জন promoted হিসেবে ${review.dest_class ? review.dest_class.name + '-এ' : ''} move করবে, বাকিরা থাকবে। নিশ্চিত?`)) return;
    setErr(''); setMsg(''); setBusy(true);
    try {
      const r = await api('/admin/promote/execute', { method: 'POST', body: { class_id: Number(classId), event_id: Number(eventId), students: rows } });
      setMsg(`Done: ${r.promoted.length} promoted, ${r.retained.length} retained.`);
      doReview();
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };

  const decBadge = d => d === 'promoted' ? <span className="badge editable">Promoted</span> :
    d === 'grace_promoted' ? <span className="badge editable">Grace (Conditional)</span> :
    <span className="badge locked">Retained</span>;

  return (
    <div>
      {err && <div className="error-msg no-print">{err}</div>}
      {msg && <div className="success-msg no-print">{msg}</div>}
      <div className="panel no-print">
        <h3>Promotions — Annual (6-9) / Test (10), published event থেকে</h3>
        <div className="doc-toolbar">
          <div><label>Published Exam *</label>
            <select value={eventId} onChange={e => setEventId(e.target.value)}>
              <option value="">Select exam</option>
              {promoEvents.map(ev => <option key={ev.id} value={ev.id}>{ev.name}{ev.year ? ` — ${ev.year}` : ''}</option>)}
            </select>
          </div>
          <div><label>Class *</label>
            <select value={classId} onChange={e => setClassId(e.target.value)}>
              <option value="">Select class</option>
              {classes.map(c => <option key={c.id} value={c.id}>{c.name} - {c.section}{c.group_name ? ` (${c.group_name})` : ''}</option>)}
            </select>
          </div>
          <button className="btn" disabled={!eventId || !classId || busy} onClick={doReview}>📋 Review</button>
        </div>
        {promoEvents.length === 0 && <p className="muted">কোনো published Annual/Test exam নেই — আগে Events & Results থেকে publish করুন।</p>}
      </div>

      {review && (
        <div className="panel">
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8, flexWrap: 'wrap', gap: 8 }}>
            <h3>{review.event.name} — {review.class.name} ({review.class.group_name || review.class.section}) → {review.dest_class ? review.dest_class.name : 'গন্তব্য class পাওয়া যায়নি'}</h3>
            <div>
              <label className="muted" style={{ marginRight: 6 }}>Grace fails ≤ (শর্তসাপেক্ষ)</label>
              <input style={{ width: 60 }} type="number" min="0" max="11" value={grace} onChange={e => setGrace(e.target.value)} />
              <button className="btn sm ghost" style={{ marginLeft: 6 }} onClick={saveGrace}>Save</button>
            </div>
          </div>
          <p className="muted" style={{ fontSize: 12, marginBottom: 8 }}>
            Auto-Promotion নীতিমালা: সব subject-এ pass = <b>Promoted</b>; grace সীমার মধ্যে fail = <b>Grace (শর্তসাপেক্ষে উত্তীর্ণ)</b>;
            এর বেশি fail / absent = <b>Retained</b>. Class 10 Test থেকে উত্তীর্ণরা <b>SSC Batch</b>-এ year-tag সহ যাবে।
          </p>
          {!review.dest_class && <p className="error-msg">গন্তব্য class নির্ধারণ করা যায়নি (যেমন Class 8 section → Class 9 group)। সবাই retained থাকবে।</p>}
          <table>
            <thead><tr><th>Roll</th><th>Student</th><th>GPA</th><th>Fails</th><th>Decision</th><th>Override</th><th>Move ✓</th></tr></thead>
            <tbody>
              {review.review.map(s => (
                <tr key={s.id}>
                  <td>{s.roll}</td><td>{s.name}</td>
                  <td><b>{s.final_gpa != null ? s.final_gpa : '-'}</b></td>
                  <td>{s.fail_count}{s.failed_subjects && s.failed_subjects.length > 0 ? ` (${s.failed_subjects.join(', ')})` : ''}</td>
                  <td>{decBadge(s.decision)}</td>
                  <td>
                    <select value={overrides[s.id] || 'auto'} onChange={e => {
                      const v = e.target.value;
                      setOverrides(o => ({ ...o, [s.id]: v }));
                      if (v === 'promoted') setChecks(c => ({ ...c, [s.id]: true }));
                      if (v === 'retained') setChecks(c => ({ ...c, [s.id]: false }));
                    }}>
                      <option value="auto">Auto</option>
                      <option value="promoted">Force promote</option>
                      <option value="retained">Force retain</option>
                    </select>
                  </td>
                  <td><input type="checkbox" checked={!!checks[s.id]} disabled={!review.dest_class}
                    onChange={e => setChecks(c => ({ ...c, [s.id]: e.target.checked }))} /></td>
                </tr>
              ))}
            </tbody>
          </table>
          <div style={{ marginTop: 12 }}>
            <button className="btn green" disabled={busy || !review.dest_class} onClick={doExecute}>▶ Execute Promotion</button>
          </div>
        </div>
      )}
    </div>
  );
}
