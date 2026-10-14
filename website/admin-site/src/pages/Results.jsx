import { useState, useEffect } from 'react';
import { api } from '../api';

const KINDS = [
  ['half_yearly', 'Half Yearly (promotion নয়)'],
  ['annual', 'Annual (promotion জড়িত)'],
  ['pretest', 'Pre-Test (promotion নয়)'],
  ['test', 'Test Exam (promotion জড়িত)'],
];
const ALL_KINDS = [...KINDS, ['other', 'Other / Free-form (legacy)']];
const kindLabel = k => (ALL_KINDS.find(x => x[0] === k) || [k, k])[1].split(' (')[0];

export default function Results({ initialTab }) {
  const [tab, setTab] = useState(initialTab || 'events');
  const [events, setEvents] = useState([]);
  const [classes, setClasses] = useState([]);
  const [sessions, setSessions] = useState([]);
  const [eventId, setEventId] = useState('');
  const [classId, setClassId] = useState('');
  const [eventName, setEventName] = useState('');
  const [data, setData] = useState(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const [showNew, setShowNew] = useState(false);
  const [newName, setNewName] = useState('');
  const [newKind, setNewKind] = useState('half_yearly');
  const [newYear, setNewYear] = useState(String(new Date().getFullYear()));
  const [newSession, setNewSession] = useState('');
  const [newExamDate, setNewExamDate] = useState('');
  const [newResultDate, setNewResultDate] = useState('');
  const [pubFor, setPubFor] = useState(null);
  const [notifyG, setNotifyG] = useState(true);
  const [entryFor, setEntryFor] = useState(null);
  const [entryOpen, setEntryOpen] = useState(true);
  const [drill, setDrill] = useState(null);
  const [covFor, setCovFor] = useState(null);
  const [cov, setCov] = useState(null);
  const [showNewSession, setShowNewSession] = useState(false);
  const [sessionName, setSessionName] = useState('');

  const load = () => {
    api('/results/events').then(setEvents).catch(e => setErr(e.message));
    api('/admin/classes').then(setClasses).catch(() => {});
    api('/admin/sessions').then(r => {
      setSessions(r);
      const act = r.find(s => s.is_active);
      if (act && !newSession) setNewSession(String(act.id));
    }).catch(() => {});
  };
  useEffect(load, []);

  const activeEvents = events.filter(e => !e.is_published);
  const publishedEvents = events.filter(e => e.is_published);

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
    e.preventDefault(); setErr(''); setMsg('');
    try {
      const body = { name: newName };
      if (newKind !== 'other') { body.exam_kind = newKind; body.year = Number(newYear); }
      if (newSession) body.session_id = Number(newSession);
      if (newExamDate) body.exam_date = newExamDate;
      if (newResultDate) body.result_date = newResultDate;
      const r = await api('/results/events', { method: 'POST', body });
      setShowNew(false); setNewName(''); setNewExamDate(''); setNewResultDate(''); load();
      setMsg(`Event created (id ${r.id}). এবার Exams & Marks থেকে subject-exam যোগ করুন।`);
    } catch (ex) { setErr(ex.message); }
  };

  // Teacher mark-entry permission for the whole event (one click, all Class-10
  // groups at once). Entry window rule: open only while unpublished; publish
  // closes it for every exam simultaneously.
  const doEntryToggle = async () => {
    if (!entryFor) return;
    setErr(''); setMsg(''); setBusy(true);
    try {
      const r = await api(`/admin/events/${entryFor.id}/entry`, { method: 'POST', body: { entry_open: entryOpen ? 1 : 0 } });
      setEntryFor(null); load();
      setMsg(`"${entryFor.name}": teacher entry ${entryOpen ? 'খোলা' : 'বন্ধ'} (${r.exams} subject-exam)।`);
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };

  // Drill-down: event → class → group/section → students → subjects+numbers.
  // Progressive disclosure: each level loads only when tapped.
  const openDrill = async ev => {
    setErr(''); setBusy(true);
    try {
      const r = await api(`/results/events/${ev.id}/coverage`);
      setDrill({ event: ev, classes: r.classes, openClass: null, students: [], openStudent: null, details: {} });
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };
  const openDrillClass = async classId => {
    if (!drill) return;
    setErr(''); setBusy(true);
    try {
      const r = await api(`/results/tabulation?event_id=${drill.event.id}&class_id=${classId}`);
      setDrill({ ...drill, openClass: classId, students: r.rows || [], subjects: r.subjects || [], openStudent: null });
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };
  const drillPdfAll = () => {
    if (!drill || !drill.openClass) return;
    window.open(`/api/results/class-pdf?event_id=${drill.event.id}&class_id=${drill.openClass}`, '_blank');
  };
  const drillPdfOne = (studentId) => {
    if (!drill) return;
    window.open(`/api/guardian/student/${studentId}/result-card.pdf?event_id=${drill.event.id}`, '_blank');
  };

  const doPublish = async () => {
    if (!pubFor) return;
    setErr(''); setMsg(''); setBusy(true);
    try {
      const r = await api(`/results/events/${pubFor.id}/publish`, { method: 'POST', body: { notify_guardians: notifyG } });
      setPubFor(null); load();
      setMsg(`"${pubFor.name}" Published-এ গেছে। ${notifyG ? `Guardian-কে পাঠানো হয়েছে (${r.notified} জন)।` : 'Guardian-কে পাঠানো হয়নি।'}${r.next_year_session ? ` ${r.next_year_session} session-এর shell auto-create হয়েছে।` : ''}`);
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };

  const doUnpublish = async ev => {
    if (!window.confirm(`"${ev.name}" unpublish করবেন? Guardian-রা আর দেখতে পাবে না।`)) return;
    setErr(''); setBusy(true);
    try { await api(`/results/events/${ev.id}/unpublish`, { method: 'POST' }); load(); }
    catch (ex) { setErr(ex.message); }
    setBusy(false);
  };

  const doDelete = async ev => {
    if (!window.confirm(`"${ev.name}" সম্পূর্ণ DELETE করবেন?\n\nএর সব subject-exam, marks, cached result ও promotion মুছে যাবে। Delete দিলে ${ev.year || 'ঐ বছর'} এর জন্য আবার এই exam create করা যাবে।`)) return;
    setErr(''); setMsg(''); setBusy(true);
    try {
      const r = await api(`/results/events/${ev.id}`, { method: 'DELETE' });
      load();
      setMsg(`Deleted: ${r.exams} exams, ${r.marks} marks, ${r.results} results, ${r.promotions} promotions. ঐ slot আবার create করা যাবে।`);
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };

  const openCoverage = async ev => {
    setErr('');
    try {
      const r = await api(`/results/events/${ev.id}/coverage`);
      setCov(r); setCovFor(ev);
    } catch (ex) { setErr(ex.message); }
  };

  const createSession = async e => {
    e.preventDefault(); setErr(''); setMsg('');
    try {
      const r = await api('/admin/sessions', { method: 'POST', body: { name: sessionName } });
      setShowNewSession(false); setSessionName(''); load();
      setMsg(`Session "${sessionName || ''}" ready — ${r.ensured.created.length} নতুন shell, ${r.ensured.adopted.length} adopt, ${r.ensured.skipped.length} আগে থেকেই ছিল।`);
    } catch (ex) { setErr(ex.message); }
  };

  const setActiveSession = async id => {
    setErr('');
    try { await api(`/admin/sessions/${id}/active`, { method: 'PUT', body: { is_active: true } }); load(); }
    catch (ex) { setErr(ex.message); }
  };

  const ensureSession = async id => {
    setErr(''); setMsg(''); setBusy(true);
    try {
      const r = await api('/results/events/ensure-session', { method: 'POST', body: { session_id: Number(id) } });
      load();
      setMsg(`Session ${r.session.name}: ${r.created.length} created, ${r.adopted.length} adopted, ${r.skipped.length} skipped.`);
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };

  const fmtD = d => d ? String(d).slice(0, 10) : '—';
  const eventRow = ev => (
    <tr key={ev.id}>
      <td><b>{ev.name}</b><br /><span className="muted" style={{ fontSize: 11 }}>{ev.session_name || '-'} • {kindLabel(ev.exam_kind)}{ev.year ? ` ${ev.year}` : ''}{ev.promotion_linked ? ' • Promotion' : ''}<br />📅 Exam: {fmtD(ev.exam_date)} • 🎯 Result: {fmtD(ev.result_date)}</span></td>
      <td>{ev.exam_count || 0}{(ev.entry_open_count || 0) > 0 && <><br /><span className="badge editable" style={{ fontSize: 11 }}>✏️ entry open ({ev.entry_open_count})</span></>}</td>
      <td>{ev.students_with_marks || 0}</td>
      <td>{ev.notify_guardians ? '🔔 Yes' : '—'}</td>
      <td>
        <button className="btn sm" onClick={() => openCoverage(ev)}>Coverage</button>
        <button className="btn sm ghost" style={{ marginLeft: 6 }} onClick={() => { setEventId(String(ev.id)); setEventName(ev.name); setTab('tabulate'); }}>Tabulate</button>
        {!ev.is_published && <button className="btn sm" style={{ marginLeft: 6 }} disabled={busy} onClick={() => openDrill(ev)}>🔍 Drill</button>}
        {!ev.is_published && <button className="btn sm" style={{ marginLeft: 6 }} disabled={busy} onClick={() => { setEntryFor(ev); setEntryOpen(true); }}>✏️ Entry</button>}
        {!ev.is_published && <button className="btn sm green" style={{ marginLeft: 6 }} disabled={busy} onClick={() => { setPubFor(ev); setNotifyG(true); }}>Publish ✓</button>}
        {ev.is_published && <button className="btn sm amber" style={{ marginLeft: 6 }} disabled={busy} onClick={() => doUnpublish(ev)}>Unpublish</button>}
        <button className="btn sm danger" style={{ marginLeft: 6 }} disabled={busy} onClick={() => doDelete(ev)}>Delete</button>
      </td>
    </tr>
  );

  return (
    <div>
      {err && <div className="error-msg no-print">{err}</div>}
      {msg && <div className="success-msg no-print">{msg}</div>}

      <div className="tabs no-print" style={{ marginBottom: 12 }}>
        <button className={'tab ' + (tab === 'events' ? 'active' : '')} onClick={() => setTab('events')}>Running Exams ({activeEvents.length})</button>
        <button className={'tab ' + (tab === 'published' ? 'active' : '')} onClick={() => setTab('published')}>Published Exams ({publishedEvents.length})</button>
        <button className={'tab ' + (tab === 'tabulate' ? 'active' : '')} onClick={() => setTab('tabulate')}>Tabulate / Compute</button>
        <button className={'tab ' + (tab === 'sessions' ? 'active' : '')} onClick={() => setTab('sessions')}>Sessions</button>
      </div>

      {(tab === 'events' || tab === 'published') && (
        <div className="panel">
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
            <h3>{tab === 'published' ? 'Published Exams — প্রকাশিত পরীক্ষা' : 'Running Exams — চলমান পরীক্ষা'}</h3>
            <button className="btn" onClick={() => setShowNew(true)}>+ New Event</button>
          </div>
          <table>
            <thead><tr><th>Event</th><th>Subjects</th><th>Students ✓</th><th>Guardian 🔔</th><th>Actions</th></tr></thead>
            <tbody>
              {(tab === 'published' ? publishedEvents : activeEvents).map(eventRow)}
              {(tab === 'published' ? publishedEvents : activeEvents).length === 0 &&
                <tr><td colSpan="5" className="muted">কিছু নেই।</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {covFor && cov && (
        <div className="panel" style={{ marginTop: 12 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8, alignItems: 'center' }}>
            <h3>Coverage — {covFor.name} (কতজন / কত subject entry)</h3>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              {cov.event_ready
                ? <span className="badge editable" style={{ fontSize: 13 }}>✅ 100% — Review → Publish করতে প্রস্তুত</span>
                : <span className="badge locked">⏳ Entry চলছে</span>}
              <button className="btn ghost sm" onClick={() => { setCovFor(null); setCov(null); }}>Close</button>
            </div>
          </div>
          <table>
            <thead><tr><th>Class</th><th>Students</th><th>Marks rows</th><th>Subjects</th><th>Status</th></tr></thead>
            <tbody>
              {cov.classes.map(c => (
                <tr key={c.class_id}>
                  <td>{c.class_name} ({c.group_name || c.section})</td>
                  <td><b>{c.students_with_marks}</b> / {c.student_count}
                    <div style={{ height: 6, background: '#e2e8f0', borderRadius: 3, marginTop: 3 }}>
                      <div style={{ width: `${c.student_count ? Math.round(c.students_with_marks / c.student_count * 100) : 0}%`, height: '100%', background: '#10b981', borderRadius: 3 }} />
                    </div>
                  </td>
                  <td>{c.marks_count}</td>
                  <td><b>{c.subjects_with_marks}</b> / {c.assigned_subjects || c.subject_count}
                    <div style={{ height: 6, background: '#e2e8f0', borderRadius: 3, marginTop: 3 }}>
                      <div style={{ width: `${c.subject_pct || 0}%`, height: '100%', background: (c.subject_pct || 0) === 100 ? '#10b981' : '#f59e0b', borderRadius: 3 }} />
                    </div>
                    <span className="muted" style={{ fontSize: 11 }}>{c.subject_progress}</span>
                  </td>
                  <td>{c.ready
                    ? <span className="badge editable">✅ Ready</span>
                    : <span className="muted" style={{ fontSize: 12 }}>{c.pending_subjects} subject বাকি</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'tabulate' && (
        <div className="panel no-print">
          <h3>Exam Events & Results — ফলাফল গণনা (SSC Grading)</h3>
          <div className="doc-toolbar">
            <div><label>Exam Event</label>
              <select value={eventId} onChange={e => { setEventId(e.target.value); setEventName((events.find(x => x.id === Number(e.target.value)) || {}).name || ''); }}>
                <option value="">Select event</option>
                {events.map(ev => <option key={ev.id} value={ev.id}>{ev.name}{ev.is_published ? ' ✓' : ''}</option>)}
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
      )}

      {tab === 'tabulate' && data && (
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

      {tab === 'sessions' && (
        <div className="panel">
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
            <h3>Sessions — Half Yearly / Annual / Pre-Test / Test auto shells</h3>
            <button className="btn" onClick={() => setShowNewSession(true)}>+ New Session</button>
          </div>
          <table>
            <thead><tr><th>Session</th><th>Active</th><th>Events</th><th>Actions</th></tr></thead>
            <tbody>
              {sessions.map(s => (
                <tr key={s.id}>
                  <td><b>{s.name}</b></td>
                  <td>{s.is_active ? '✅' : '—'}</td>
                  <td>{s.event_count}</td>
                  <td>
                    {!s.is_active && <button className="btn sm" onClick={() => setActiveSession(s.id)}>Set Active</button>}
                    <button className="btn sm ghost" style={{ marginLeft: 6 }} disabled={busy} onClick={() => ensureSession(s.id)}>Ensure 4 Shells</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {entryFor && (
        <div className="modal-bg" onClick={() => setEntryFor(null)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>Teacher Entry — "{entryFor.name}"</h3>
            <p className="muted">এক ক্লিকে Class 10-এর সব group-এর subject-exam-এ teacher entry {entryOpen ? 'খুলবে' : 'বন্ধ হবে'}। Publish করলে সব entry একসাথে বন্ধ হয়।</p>
            <label style={{ display: 'flex', gap: 8, alignItems: 'center', margin: '12px 0' }}>
              <input type="checkbox" checked={entryOpen} onChange={e => setEntryOpen(e.target.checked)} />
              Teacher-রা number entry করতে পারবে (permission)
            </label>
            <div className="modal-actions">
              <button type="button" className="btn ghost" onClick={() => setEntryFor(null)}>Cancel</button>
              <button type="button" className="btn green" disabled={busy} onClick={doEntryToggle}>{entryOpen ? 'Entry খুলুন ✏️' : 'Entry বন্ধ করুন 🔒'}</button>
            </div>
          </div>
        </div>
      )}

      {drill && (
        <div className="panel" style={{ marginTop: 12 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8, alignItems: 'center' }}>
            <h3>🔍 {drill.event.name} — Class → Group → Student → Subject</h3>
            <button className="btn ghost sm" onClick={() => setDrill(null)}>Close</button>
          </div>
          {!drill.openClass ? (
            <table>
              <thead><tr><th>Class 10</th><th>Students ✓</th><th>Subjects ✓</th><th></th></tr></thead>
              <tbody>
                {drill.classes.map(c => (
                  <tr key={c.class_id}>
                    <td><b>{c.class_name}</b> ({c.group_name || c.section})</td>
                    <td>{c.students_with_marks}/{c.student_count}</td>
                    <td>{c.subjects_with_marks}/{c.assigned_subjects || c.subject_count}</td>
                    <td><button className="btn sm" disabled={busy} onClick={() => openDrillClass(c.class_id)}>খুলুন →</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <div>
              <div style={{ display: 'flex', gap: 8, marginBottom: 10, alignItems: 'center' }}>
                <button className="btn sm ghost" onClick={() => setDrill({ ...drill, openClass: null, students: [] })}>← সব class</button>
                <b>{(drill.classes.find(c => c.class_id === drill.openClass) || {}).class_name} ({(drill.classes.find(c => c.class_id === drill.openClass) || {}).group_name || ''})</b>
                <span style={{ flex: 1 }} />
                <button className="btn sm green" onClick={drillPdfAll}>📄 সব student-এর PDF (এক ফাইলে)</button>
              </div>
              <table>
                <thead><tr><th>Roll</th><th>Student</th><th>GPA</th><th>Result</th><th>Pos</th><th></th></tr></thead>
                <tbody>
                  {(drill.students || []).map(s => (
                    <>
                      <tr key={s.id}>
                        <td>{s.roll}</td>
                        <td><b>{s.name}</b></td>
                        <td>{s.final_gpa != null ? s.final_gpa : '-'}</td>
                        <td>{s.result_status || '-'}</td>
                        <td>{s.position ? `#${s.position}` : '-'}</td>
                        <td>
                          <button className="btn sm ghost" onClick={() => setDrill({ ...drill, openStudent: drill.openStudent === s.id ? null : s.id })}>
                            {drill.openStudent === s.id ? 'লুকান' : 'Subject ▾'}
                          </button>
                          <button className="btn sm" style={{ marginLeft: 6 }} onClick={() => drillPdfOne(s.id)}>PDF</button>
                        </td>
                      </tr>
                      {drill.openStudent === s.id && (
                        <tr key={s.id + '-d'}>
                          <td colSpan="6" style={{ background: '#f8fafc' }}>
                            <table>
                              <thead><tr><th>Subject</th><th>Marks</th><th>Grade</th><th>GPA</th></tr></thead>
                              <tbody>
                                {(drill.subjects || []).map(sub => {
                                  const f = (s._families || []).find(x => x && x.subject === sub);
                                  return <tr key={sub}><td>{sub}</td><td>{f ? `${f.total}/${f.full}` : '-'}</td><td>{f ? f.letter_grade : '-'}</td><td>{f ? f.grade_point : '-'}</td></tr>;
                                })}
                              </tbody>
                            </table>
                          </td>
                        </tr>
                      )}
                    </>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {showNew && (
        <div className="modal-bg" onClick={() => setShowNew(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>New Exam Event</h3>
            <form onSubmit={createEvent}>
              <div className="form-row">
                <div><label>Event Name *</label><input value={newName} onChange={e => setNewName(e.target.value)} placeholder="Test Examination 2026" required /></div>
              </div>
              <div className="form-row">
                <div><label>📅 Exam Date (ঘোষণা — এই তারিখ থেকে teacher entry)</label><input type="date" value={newExamDate} onChange={e => setNewExamDate(e.target.value)} /></div>
                <div><label>🎯 Result Publish-এর সম্ভাব্য তারিখ</label><input type="date" value={newResultDate} onChange={e => setNewResultDate(e.target.value)} /></div>
              </div>
              <div className="form-row">
                <div><label>Kind *</label>
                  <select value={newKind} onChange={e => setNewKind(e.target.value)}>
                    {KINDS.map(k => <option key={k[0]} value={k[0]}>{k[1]}</option>)}
                  </select>
                </div>
                {newKind !== 'other' && <div><label>Year *</label><input type="number" value={newYear} onChange={e => setNewYear(e.target.value)} required /></div>}
              </div>
              <div className="form-row">
                <div><label>Session</label>
                  <select value={newSession} onChange={e => setNewSession(e.target.value)}>
                    <option value="">(default)</option>
                    {sessions.map(s => <option key={s.id} value={s.id}>{s.name}{s.is_active ? ' (active)' : ''}</option>)}
                  </select>
                </div>
              </div>
              {newKind !== 'other' && <p className="muted">একই kind+year আগে থাকলে create হবে না (409) — আগে delete করতে হবে।</p>}
              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={() => setShowNew(false)}>Cancel</button>
                <button type="submit" className="btn">Create</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {pubFor && (
        <div className="modal-bg" onClick={() => setPubFor(null)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>Publish "{pubFor.name}"?</h3>
            <p>Result থাকুক বা না থাকুক — publish করলে এটা Published Exams-এ চলে যাবে।{(pubFor.exam_kind === 'half_yearly' || pubFor.exam_kind === 'pretest' || pubFor.exam_kind === 'annual' || pubFor.exam_kind === 'test') && pubFor.year ? ` ${Number(pubFor.year) + 1} সালের shell auto-create হবে।` : ''}</p>
            <label style={{ display: 'flex', gap: 8, alignItems: 'center', margin: '12px 0' }}>
              <input type="checkbox" checked={notifyG} onChange={e => setNotifyG(e.target.checked)} />
              Guardian-দের কাছে notification পাঠান (সিদ্ধান্ত: admin)
            </label>
            <div className="modal-actions">
              <button type="button" className="btn ghost" onClick={() => setPubFor(null)}>Cancel</button>
              <button type="button" className="btn green" disabled={busy} onClick={doPublish}>Publish ✓</button>
            </div>
          </div>
        </div>
      )}

      {showNewSession && (
        <div className="modal-bg" onClick={() => setShowNewSession(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>New Session</h3>
            <form onSubmit={createSession}>
              <div className="form-row">
                <div><label>Session Name * (সাল)</label><input value={sessionName} onChange={e => setSessionName(e.target.value)} placeholder="2027" required /></div>
              </div>
              <p className="muted">Create করলে Half Yearly / Annual / Pre-Test / Test — ৪টা shell auto-create হবে।</p>
              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={() => setShowNewSession(false)}>Cancel</button>
                <button type="submit" className="btn">Create</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
