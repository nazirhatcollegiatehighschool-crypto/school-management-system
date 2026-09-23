import { useState, useEffect } from 'react';
import { api } from '../api';

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday'];

export default function Routines() {
  const [routines, setRoutines] = useState([]);
  const [slots, setSlots] = useState([]);
  const [teachers, setTeachers] = useState([]);
  const [classes, setClasses] = useState([]);
  const [subjects, setSubjects] = useState([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState('');
  const [filter, setFilter] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [cTeacher, setCTeacher] = useState('');
  const [cClsName, setCClsName] = useState('');
  const [cSec, setCSec] = useState('');
  const [cDay, setCDay] = useState('');
  const [cSlot, setCSlot] = useState('');
  const [cSubject, setCSubject] = useState('');
  const [cNotes, setCNotes] = useState('');
  const [requests, setRequests] = useState([]);
  const [view, setView] = useState('schedule');
  const [mDay, setMDay] = useState(0);

  const load = async () => {
    setLoading(true); setErr('');
    try {
      const [r, cls, subs, reqs] = await Promise.all([
        api('/routine/all'),
        api('/admin/classes'),
        api('/admin/subjects'),
        api('/routine/admin/delete-requests'),
      ]);
      setRoutines(r.routines || []);
      setSlots(r.slots || []);
      setTeachers(r.teachers || []);
      setClasses(cls || []);
      setSubjects(subs || []);
      setRequests(reqs || []);
    } catch (e) { setErr(e.message); }
    finally { setLoading(false); }
  };

  useEffect(() => { load(); }, []);

  const removeEntry = async id => {
    if (!window.confirm('Delete this routine period?')) return;
    try {
      await api('/routine/admin/' + id, { method: 'DELETE' });
      load();
    } catch (e) { alert(e.message); }
  };

  const approveRequest = async req => {
    if (!window.confirm(`Approve delete — ${req.subject_name || '?'} (${req.class_details || ''})?`)) return;
    try {
      await api(`/routine/admin/delete-requests/${req.id}/approve`, { method: 'POST' });
      load();
    } catch (e) { alert(e.message); }
  };

  const rejectRequest = async req => {
    try {
      await api(`/routine/admin/delete-requests/${req.id}/reject`, { method: 'POST' });
      load();
    } catch (e) { alert(e.message); }
  };

  const pendingRequests = requests.filter(r => r.status === 'pending');

  const resetCreate = () => {
    setShowCreate(false);
    setCTeacher(''); setCClsName(''); setCSec(''); setCDay(''); setCSlot(''); setCSubject(''); setCNotes('');
  };

  const saveCreate = async e => {
    e.preventDefault(); setErr('');
    try {
      const row = classRows.find(r => (isGroup ? r.group_name : r.section) === cSec);
      if (!row) { setErr('Select class section/group'); return; }
      const sections = []; const groups = [];
      if (row.group_name) groups.push({ class_id: row.id, group_name: row.group_name });
      else sections.push({ class_id: row.id, section: row.section });
      await api('/routine/admin', {
        method: 'POST',
        body: {
          teacher_id: Number(cTeacher),
          day: DAYS.indexOf(cDay),
          time_slot_id: Number(cSlot),
          subject_id: Number(cSubject),
          sections, groups,
          notes: cNotes || null,
        },
      });
      resetCreate();
      load();
    } catch (ex) { setErr(ex.message); }
  };

  const list = filter ? routines.filter(r => String(r.teacher_id) === filter) : routines;
  const map = {};
  for (const e of list) {
    const key = `${e.day}_${e.slot_order}`;
    if (!map[key]) map[key] = [];
    map[key].push(e);
  }

  // master-grid derived state (rows = teachers, cols = periods, day = mDay)
  const mCell = {};
  for (const e of routines) {
    if (e.day !== mDay) continue;
    const k = `${e.teacher_id}_${e.slot_order}`;
    if (!mCell[k]) mCell[k] = [];
    mCell[k].push(e);
  }
  const classLabel = e => {
    const secs = (e.sections || []).map(s => `${s.class_name} (${s.section})`);
    const grps = (e.groups || []).map(g => `${g.class_name} (${g.group_name})`);
    return [...secs, ...grps].join(', ') || '';
  };

  const conflicts = [];
  const seen = {};
  for (const e of list) {
    const key = `${e.teacher_id}_${e.day}_${e.time_slot_id}`;
    if (!seen[key]) seen[key] = [];
    seen[key].push(e);
  }
  for (const k in seen) if (seen[k].length > 1) conflicts.push(...seen[k]);

  // cascade derivations for the create modal
  const classNames = [...new Set(classes.map(c => c.name))];
  const classRows = classes.filter(c => c.name === cClsName);
  const isGroup = classRows.some(c => c.group_name);
  const secOpts = isGroup
    ? [...new Set(classRows.map(c => c.group_name).filter(Boolean))]
    : [...new Set(classRows.map(c => c.section))];
  const selRow = classes.find(c => c.name === cClsName && (isGroup ? c.group_name : c.section) === cSec);
  const selClassId = selRow ? selRow.id : null;
  const classSubjects = subjects.filter(s => s.class_id === selClassId)
    .filter(s => cTeacher ? s.teacher_id === Number(cTeacher) : true);
  const teacherSubjectsEmpty = cTeacher && selClassId && classSubjects.length === 0;

  return (
    <div className="routines-page">
      <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginBottom: 12, flexWrap: 'wrap' }}>
        <div className="tabs" style={{ margin: 0 }}>
          <button className={'tab ' + (view === 'schedule' ? 'active' : '')} onClick={() => setView('schedule')}>Day × Period</button>
          <button className={'tab ' + (view === 'master' ? 'active' : '')} onClick={() => setView('master')}>Master Grid (Teacher × Period)</button>
        </div>
        {view === 'schedule' ? (
          <select value={filter} onChange={e => setFilter(e.target.value)} style={{ padding: 6 }}>
            <option value="">All Teachers</option>
            {teachers.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
        ) : (
          <select value={mDay} onChange={e => setMDay(Number(e.target.value))} style={{ padding: 6 }}>
            {DAYS.map((d, i) => <option key={d} value={i}>{d}</option>)}
          </select>
        )}
        <button className="btn" onClick={() => { load(); }}>Refresh</button>
        <button className="btn green" onClick={() => setShowCreate(true)}>+ New Period</button>
        {err && <span className="error-msg">{err}</span>}
      </div>
      {loading ? <p>Loading…</p> : (
        <>
          {pendingRequests.length > 0 && (
            <div style={{ background: '#fff3e0', border: '1px solid #ffe0b2', color: '#bf360c', padding: 10, borderRadius: 6, marginBottom: 12 }}>
              <b>🕘 {pendingRequests.length} Period Delete Request(s) awaiting approval</b>
              <table className="table" style={{ marginTop: 8 }}>
                <thead><tr><th>Subject</th><th>Class/Section</th><th>Teacher</th><th>Actions</th></tr></thead>
                <tbody>
                  {pendingRequests.map(req => (
                    <tr key={req.id}>
                      <td>{req.subject_name}</td>
                      <td>{req.class_details || '—'}</td>
                      <td>{req.teacher_name}</td>
                      <td style={{ whiteSpace: 'nowrap' }}>
                        <button className="btn ghost" onClick={() => rejectRequest(req)}>Reject</button>{' '}
                        <button className="btn" style={{ background: '#c62828' }} onClick={() => approveRequest(req)}>Approve</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {conflicts.length > 0 && (
            <div style={{ background: '#fdecea', border: '1px solid #f5c6c0', color: '#b71c1c', padding: 10, borderRadius: 6, marginBottom: 12 }}>
              <b>⚠ {conflicts.length} conflicting period(s)</b>
              <ul style={{ margin: '6px 0 0 18px' }}>
                {conflicts.map((c, i) => (
                  <li key={i}>{c.teacher_name} — {c.slot_label} ({DAYS[c.day]}) — {c.subject?.name}</li>
                ))}
              </ul>
            </div>
          )}
          {view === 'schedule' && (
            <div className="table-wrap">
              <table className="table">
                <thead>
                  <tr>
                    <th>Period</th>
                    {DAYS.map(d => <th key={d}>{d}</th>)}
                  </tr>
                </thead>
                <tbody>
                  {slots.map(slot => (
                    <tr key={slot.id}>
                      <td><b>{slot.slot_order}</b><br /><small>{slot.start_time}–{slot.end_time}</small></td>
                      {DAYS.map((d, di) => {
                        const key = `${di}_${slot.slot_order}`;
                        const entries = map[key] || [];
                        return (
                          <td key={d} style={{ verticalAlign: 'top', minWidth: 120 }}>
                            {entries.length === 0 ? <small style={{ color: '#bbb' }}>—</small> : entries.map((e, i) => (
                              <div key={i} style={{ background: '#e0f2f1', borderRadius: 4, padding: '4px 6px', marginBottom: 4, fontSize: 12 }}>
                                <b>{e.subject?.name}</b><br />
                                {e.teacher_name}
                                <button
                                  onClick={() => removeEntry(e.id)}
                                  style={{ float: 'right', border: 'none', background: 'none', color: '#c62828', cursor: 'pointer' }}
                                  title="Delete">✕</button>
                              </div>
                            ))}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {view === 'master' && (
            <div className="table-wrap">
              <table className="table">
                <thead>
                  <tr>
                    <th>Teacher — {DAYS[mDay]}</th>
                    {slots.map(s => (
                      <th key={s.id}><b>Period {s.slot_order}</b><br /><small>{s.start_time}–{s.end_time}</small></th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {teachers.map(t => (
                    <tr key={t.id}>
                      <td><b>{t.name}</b></td>
                      {slots.map(s => {
                        const entries = mCell[`${t.id}_${s.slot_order}`] || [];
                        return (
                          <td key={s.id} style={{ verticalAlign: 'top', minWidth: 140 }}>
                            {entries.length === 0 ? <small style={{ color: '#bbb' }}>—</small> : entries.map((e, i) => (
                              <div key={i} style={{ background: '#e0f2f1', borderRadius: 4, padding: '4px 6px', marginBottom: 4, fontSize: 12 }}>
                                <b>{e.subject?.name}</b><br />
                                <small>{classLabel(e)}</small>
                                <button
                                  onClick={() => removeEntry(e.id)}
                                  style={{ float: 'right', border: 'none', background: 'none', color: '#c62828', cursor: 'pointer' }}
                                  title="Delete">✕</button>
                              </div>
                            ))}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}

      {showCreate && (
        <div className="modal-bg" onClick={resetCreate}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>Add Routine Period — ধাপে ধাপে</h3>
            <form onSubmit={saveCreate}>
              <div className="form-row">
                <div><label>Step 1 — Teacher *</label>
                  <select value={cTeacher} onChange={e => { setCTeacher(e.target.value); setCSubject(''); }} required>
                    <option value="">Select teacher</option>
                    {teachers.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                  </select>
                </div>
                <div><label>Step 2 — Class *</label>
                  <select value={cClsName} onChange={e => { setCClsName(e.target.value); setCSec(''); setCSubject(''); }} required>
                    <option value="">Select class</option>
                    {classNames.map(n => <option key={n} value={n}>{n}</option>)}
                  </select>
                </div>
              </div>
              <div className="form-row">
                <div><label>Step 3 — {isGroup ? 'Group' : 'Section'} *</label>
                  <select value={cSec} onChange={e => { setCSec(e.target.value); setCSubject(''); }} disabled={!cClsName} required>
                    <option value="">{isGroup ? 'Select group' : 'Select section'}</option>
                    {secOpts.map(s => <option key={s} value={s}>{s}</option>)}
                  </select>
                </div>
                <div><label>Step 4 — Day *</label>
                  <select value={cDay} onChange={e => setCDay(e.target.value)} required>
                    <option value="">Select day</option>
                    {DAYS.map(d => <option key={d} value={d}>{d}</option>)}
                  </select>
                </div>
              </div>
              <div className="form-row">
                <div><label>Step 5 — Period *</label>
                  <select value={cSlot} onChange={e => setCSlot(e.target.value)} required>
                    <option value="">Select period</option>
                    {slots.map(s => <option key={s.id} value={s.id}>{s.slot_order} — {s.label} ({s.start_time}–{s.end_time})</option>)}
                  </select>
                </div>
                <div><label>Step 6 — Subject *</label>
                  <select value={cSubject} onChange={e => setCSubject(e.target.value)} disabled={!selClassId} required>
                    <option value="">Select subject</option>
                    {classSubjects.map(s => <option key={s.id} value={s.id}>{s.name}{s.teacher_name ? ' (' + s.teacher_name + ')' : ''}</option>)}
                  </select>
                </div>
              </div>
              {teacherSubjectsEmpty && <p className="error-msg">এই teacher-কে এই class-এ কোনো subject assign করা নেই।</p>}
              <div className="form-row">
                <div><label>Notes (optional)</label><input value={cNotes} onChange={e => setCNotes(e.target.value)} /></div>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={resetCreate}>Cancel</button>
                <button type="submit" className="btn">Add Period</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}