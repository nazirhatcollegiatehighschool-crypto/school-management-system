import { useState, useEffect } from 'react';
import { api } from '../api';

export default function Results() {
  const [events, setEvents] = useState([]);
  const [classes, setClasses] = useState([]);
  const [eventId, setEventId] = useState('');
  const [classId, setClassId] = useState('');
  const [eventName, setEventName] = useState('');
  const [data, setData] = useState(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const [showNew, setShowNew] = useState(false);
  const [newName, setNewName] = useState('');

  const load = () => {
    api('/results/events').then(setEvents).catch(e => setErr(e.message));
    api('/admin/classes').then(setClasses).catch(() => {});
  };
  useEffect(load, []);

  const compute = async () => {
    setErr(''); setMsg(''); setBusy(true);
    try {
      const r = await api('/results/results/compute', { method: 'POST', body: { event_id: Number(eventId), class_id: Number(classId) } });
      setMsg(`Computed: ${r.computed}/${r.students} students`);
      view();
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };

  const view = async () => {
    setErr(''); setBusy(true);
    try {
      const r = await api(`/results/tabulation?event_id=${eventId}&class_id=${classId}`);
      setData(r);
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };

  const createEvent = async e => {
    e.preventDefault(); setErr('');
    try {
      await api('/results/events', { method: 'POST', body: { name: newName } });
      setShowNew(false); setNewName(''); load();
    } catch (ex) { setErr(ex.message); }
  };

  return (
    <div>
      {err && <div className="error-msg no-print">{err}</div>}
      {msg && <div className="success-msg no-print">{msg}</div>}

      <div className="panel no-print">
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
          <h3>Exam Events & Results — ফলাফল গণনা (SSC Grading)</h3>
          <button className="btn" onClick={() => setShowNew(true)}>+ New Event</button>
        </div>
        <div className="doc-toolbar">
          <div><label>Exam Event</label>
            <select value={eventId} onChange={e => { setEventId(e.target.value); setEventName((events.find(x => x.id === Number(e.target.value)) || {}).name || ''); }}>
              <option value="">Select event</option>
              {events.map(ev => <option key={ev.id} value={ev.id}>{ev.name}</option>)}
            </select>
          </div>
          <div><label>Class</label>
            <select value={classId} onChange={e => setClassId(e.target.value)}>
              <option value="">Select class</option>
              {classes.map(c => <option key={c.id} value={c.id}>{c.name} - {c.section}{c.group_name ? ` (${c.group_name})` : ''}</option>)}
            </select>
          </div>
          <button className="btn green" disabled={!eventId || !classId || busy} onClick={compute}>⚙ Compute Results</button>
          <button className="btn" disabled={!eventId || !classId || busy} onClick={view}>📋 View Tabulation</button>
        </div>
      </div>

      {data && (
        <div className="print-sheet">
          <div className="doc-header">
            <h1>{(data.settings && data.settings.school_name) || 'My School'}</h1>
            <div className="doc-title">Tabulation Sheet — {eventName}</div>
          </div>
          <table className="mark-table">
            <thead>
              <tr>
                <th>Roll</th><th>Student</th>
                {data.subjects.map(s => <th key={s}>{s}</th>)}
                <th>GPA</th><th>Result</th><th>Position</th>
              </tr>
            </thead>
            <tbody>
              {data.rows.map(r => (
                <tr key={r.id}>
                  <td>{r.roll}</td>
                  <td className="subj">{r.name}</td>
                  {data.subjects.map((s, i) => {
                    const f = r._families[i];
                    return <td key={s}>{f ? `${f.total}/${f.full} (${f.letter_grade})` : '-'}</td>;
                  })}
                  <td><b>{r.final_gpa != null ? r.final_gpa : '-'}</b></td>
                  <td><span className={'badge ' + (r.result_status === 'PASSED' ? 'paid' : r.result_status ? 'absent' : '')}>{r.result_status || '-'}</span></td>
                  <td>{r.position ? `#${r.position}` : '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <div style={{ marginTop: 14 }} className="no-print">
            <button className="btn" onClick={() => window.print()}>🖨️ Print Tabulation</button>
          </div>
        </div>
      )}

      {showNew && (
        <div className="modal-bg" onClick={() => setShowNew(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>New Exam Event</h3>
            <form onSubmit={createEvent}>
              <div className="form-row">
                <div><label>Event Name *</label><input value={newName} onChange={e => setNewName(e.target.value)} placeholder="Annual Examination 2026" required /></div>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={() => setShowNew(false)}>Cancel</button>
                <button type="submit" className="btn">Create</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}