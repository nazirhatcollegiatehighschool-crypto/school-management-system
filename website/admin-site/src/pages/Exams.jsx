import { useState, useEffect } from 'react';
import { api } from '../api';

const kindLabel = k => ({
  half_yearly: 'Half Yearly', annual: 'Annual', pretest: 'Pre-Test', test: 'Test Exam', other: 'Other'
}[k] || k);
const kindToExamType = k => ['half_yearly', 'annual', 'pretest', 'test'].includes(k) ? k : 'final';

export default function Exams() {
  const [tab, setTab] = useState('term');
  const [rows, setRows] = useState([]);
  const [classes, setClasses] = useState([]);
  const [subjects, setSubjects] = useState([]);
  const [events, setEvents] = useState([]);
  const [form, setForm] = useState({ name: '', exam_type: 'final', class_id: '', subject_id: '', event_id: '', exam_date: '', entry_deadline: '' });
  const [editId, setEditId] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [expandedId, setExpandedId] = useState(null);
  const [termName, setTermName] = useState('');
  const [showNewTerm, setShowNewTerm] = useState(false);
  const [newTermKind, setNewTermKind] = useState('half_yearly');
  const [newTermYear, setNewTermYear] = useState(String(new Date().getFullYear()));
  const [editTermFor, setEditTermFor] = useState(null);
  const [marksFor, setMarksFor] = useState(null);
  const [marks, setMarks] = useState([]);
  const [exClsName, setExClsName] = useState(''); // exam cascade: class name
  const [exSec, setExSec] = useState('');         // ...then section/group
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const [reqFilter, setReqFilter] = useState('pending');
  const [requests, setRequests] = useState([]);

  const load = () => {
    api('/admin/exams').then(setRows).catch(e => setErr(e.message));
    api('/admin/classes').then(setClasses).catch(() => {});
    api('/admin/subjects').then(setSubjects).catch(() => {});
    api('/results/events').then(evs => setEvents(evs)).catch(() => {});
  };
  useEffect(load, []);

  const adminExams = rows.filter(r => r.source === 'admin');
  const classTests = rows.filter(r => r.source === 'teacher');

  const terms = events.map(ev => ({ ...ev, exams: adminExams.filter(e => e.event_id === ev.id) }));
  const unassigned = { id: 0, name: 'Unassigned Exams', exam_kind: 'other', exams: adminExams.filter(e => !e.event_id) };
  const termGroups = [...terms, unassigned].filter(t => t.id !== 0 || t.exams.length > 0);

  const closeForm = () => { setShowForm(false); setEditId(null); setExClsName(''); setExSec(''); setForm({ name: '', exam_type: 'final', class_id: '', subject_id: '', event_id: '', exam_date: '', entry_deadline: '' }); };

  const save = async e => {
    e.preventDefault(); setErr('');
    try {
      const body = { ...form, class_id: Number(form.class_id), subject_id: Number(form.subject_id), event_id: form.event_id ? Number(form.event_id) : null,
        entry_deadline: form.entry_deadline ? form.entry_deadline.replace('T', ' ') + ':00' : '' };
      if (editId) {
        await api('/admin/exams/' + editId, { method: 'PUT', body });
      } else {
        await api('/admin/exams', { method: 'POST', body });
      }
      closeForm(); load();
    } catch (ex) { setErr(ex.message); }
  };

  const openCreate = (eventId = '') => {
    setEditId(null);
    const ev = events.find(x => x.id === Number(eventId));
    setForm({ name: '', exam_type: ev ? kindToExamType(ev.exam_kind) : 'final', class_id: '', subject_id: '', event_id: String(eventId || ''), exam_date: '', entry_deadline: '' });
    setExClsName(''); setExSec('');
    setShowForm(true);
  };

  const openEdit = x => {
    setEditId(x.id);
    setForm({ name: x.name, exam_type: x.exam_type, class_id: String(x.class_id), subject_id: String(x.subject_id), event_id: x.event_id ? String(x.event_id) : '', exam_date: x.exam_date ? x.exam_date.slice(0, 10) : '', entry_deadline: x.entry_deadline ? String(x.entry_deadline).slice(0, 16).replace(' ', 'T') : '' });
    const crow = classes.find(c => c.id === Number(x.class_id));
    setExClsName(crow ? crow.name : '');
    setExSec(crow ? (crow.group_name || crow.section) : '');
    setShowForm(true);
  };

  const createTerm = async e => {
    e.preventDefault(); setErr('');
    try {
      const body = { name: termName, exam_kind: newTermKind, year: Number(newTermYear) };
      await api('/results/events', { method: 'POST', body });
      setShowNewTerm(false); setTermName(''); load();
    } catch (ex) { setErr(ex.message); }
  };

  const renameTerm = async e => {
    e.preventDefault(); setErr('');
    try {
      await api('/results/events/' + editTermFor.id, { method: 'PUT', body: { name: termName } });
      setEditTermFor(null); setTermName(''); load();
    } catch (ex) { setErr(ex.message); }
  };

  const removeTerm = async (id, name) => {
    if (id === 0) return;
    if (!window.confirm(`"${name || 'this term'}" সম্পূর্ণ DELETE করবেন?\n\nএর সব subject-exam, marks, cached result ও promotion মুছে যাবে। Delete দিলে ঐ slot আবার create করা যাবে।`)) return;
    setErr('');
    try { await api('/results/events/' + id, { method: 'DELETE' }); setExpandedId(null); load(); }
    catch (ex) { setErr(ex.message); }
  };

  const viewMarks = async id => {
    try { setMarks(await api('/admin/exams/' + id + '/marks')); setMarksFor(id); }
    catch (ex) { setErr(ex.message); }
  };

  const unlock = async markId => {
    try { await api('/admin/marks/' + markId + '/unlock', { method: 'PUT' }); viewMarks(marksFor); }
    catch (ex) { setErr(ex.message); }
  };

  const editMark = async (markId, val) => {
    try { await api('/admin/marks/' + markId, { method: 'PUT', body: { marks: Number(val) } }); viewMarks(marksFor); }
    catch (ex) { setErr(ex.message); }
  };

  const setStatus = async (id, status) => {
    setErr(''); setBusy(true);
    try {
      await api('/admin/exams/' + id + '/' + (status === 'published' ? 'publish-admin' : 'unpublish'), { method: 'POST' });
      load();
    } catch (ex) { setErr(ex.message); } finally { setBusy(false); }
  };

  const removeExam = async id => {
    if (!window.confirm('Delete this exam and all its marks?')) return;
    setErr('');
    try { await api('/admin/exams/' + id, { method: 'DELETE' }); load(); }
    catch (ex) { setErr(ex.message); }
  };

  // 1-click marks-entry permission: per exam or whole event at once.
  const setEntry = async (id, open) => {
    setErr(''); setMsg(''); setBusy(true);
    try {
      await api('/admin/exams/' + id + '/entry', { method: 'PUT', body: { entry_open: open } });
      setMsg(open ? 'Entry opened — teacher-রা marks দিতে পারবে।' : 'Entry revoked — teacher entry বন্ধ।');
      load();
    } catch (ex) { setErr(ex.message); } finally { setBusy(false); }
  };

  const setEventEntry = async (id, open) => {
    if (!window.confirm(open
      ? 'এই event-এর সব exam-এ teacher entry খুলে দিবেন?'
      : 'এই event-এর সব exam-এ teacher entry বন্ধ করবেন?')) return;
    setErr(''); setMsg(''); setBusy(true);
    try {
      const r = await api('/admin/events/' + id + '/entry', { method: 'POST', body: { entry_open: open } });
      setMsg(open ? `Entry opened (${r.exams} exams)।` : `Entry revoked (${r.exams} exams) — teacher entry বন্ধ।`);
      load();
    } catch (ex) { setErr(ex.message); } finally { setBusy(false); }
  };

  const loadRequests = async (status) => {
    setErr('');
    try { setRequests(await api('/admin/mark-edit-requests?status=' + (status || reqFilter))); }
    catch (ex) { setErr(ex.message); }
  };

  const decideRequest = async (id, decision) => {
    if (decision === 'reject' && !window.confirm('Request reject করবেন?')) return;
    setErr(''); setMsg(''); setBusy(true);
    try {
      await api(`/admin/mark-edit-requests/${id}/${decision === 'approve' ? 'approve' : 'reject'}`, { method: 'POST' });
      setMsg(decision === 'approve' ? 'Approved — teacher আবার ৫ ঘণ্টা edit করতে পারবে।' : 'Rejected.');
      loadRequests();
    } catch (ex) { setErr(ex.message); }
    setBusy(false);
  };

  const exam = rows.find(r => r.id === marksFor);
  const filteredSubjects = subjects.filter(s => !form.class_id || s.class_id === Number(form.class_id));
  const exClassNames = [...new Set(classes.map(c => c.name))];
  const exClassRows = classes.filter(c => c.name === exClsName);
  const exIsGroup = exClassRows.some(c => c.group_name);
  const exSecOpts = exIsGroup
    ? [...new Set(exClassRows.map(c => c.group_name).filter(Boolean))]
    : [...new Set(exClassRows.map(c => c.section))];
  const statusBadge = s => s === 'published' ? <span className="badge editable">Published</span> :
    s === 'submitted' ? <span className="badge locked">Submitted</span> :
    <span className="badge locked">Draft</span>;
  const typeLabel = t => ({
    class_test: 'Class Test', midterm: 'Midterm', final: 'Final',
    half_yearly: 'Half Yearly', annual: 'Annual', pretest: 'Pre-Test', test: 'Test Exam'
  }[t] || t);

  return (
    <div>
      {err && <div className="error-msg">{err}</div>}
      {msg && <div className="success-msg no-print">{msg}</div>}

      <div className="tabs no-print" style={{ marginBottom: 12 }}>
        <button className={'tab ' + (tab === 'term' ? 'active' : '')} onClick={() => setTab('term')}>Exams & Marks</button>
        <button className={'tab ' + (tab === 'class_test' ? 'active' : '')} onClick={() => setTab('class_test')}>Class Tests (Teacher)</button>
        <button className={'tab ' + (tab === 'approvals' ? 'active' : '')} onClick={() => { setTab('approvals'); loadRequests('pending'); }}>Edit Approvals</button>
      </div>

      {tab === 'term' && (
        <div className="panel">
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
            <h3>Exams & Marks — Half Yearly / Annual / Pre-Test / Test (session year সহ)</h3>
            <div>
              <button className="btn ghost" style={{ marginRight: 6 }} onClick={() => setShowNewTerm(true)}>+ Create Exam Event</button>
              <button className="btn" onClick={() => openCreate()}>+ Create Exam</button>
            </div>
          </div>
          <table>
            <thead><tr><th></th><th>Exam Event</th><th>Session</th><th>Subjects</th><th>Published</th><th>Actions</th></tr></thead>
            <tbody>
              {termGroups.map(t => ([
                <tr key={t.id}>
                  <td>{t.id !== 0 && t.exams.length > 0 && (
                    <button className="btn sm ghost" onClick={() => setExpandedId(expandedId === t.id ? null : t.id)}>{expandedId === t.id ? '▾' : '▸'}</button>
                  )}</td>
                  <td><b>{t.name}</b><br /><span className="muted" style={{ fontSize: 11 }}>
                    {kindLabel(t.exam_kind)}{t.year ? ` ${t.year}` : ''}{t.promotion_linked ? ' • Promotional' : ''}
                  </span></td>
                  <td>{t.session_name || '-'}</td>
                  <td>{t.exams.length}</td>
                  <td>{t.exams.filter(e => e.status === 'published').length} / {t.exams.length}</td>
                  <td>
                    {t.id !== 0 && <button className="btn sm green" onClick={() => openCreate(t.id)}>+ Subject Exam</button>}
                    {t.id !== 0 && (
                      <>
                        <button className="btn sm ghost" style={{ marginLeft: 6 }} onClick={() => setEventEntry(t.id, 1)}>Entry: Open All</button>
                        <button className="btn sm amber" style={{ marginLeft: 6 }} onClick={() => setEventEntry(t.id, 0)}>Revoke All</button>
                        <button className="btn sm ghost" style={{ marginLeft: 6 }} onClick={() => { setEditTermFor(t); setTermName(t.name); }}>Rename</button>
                        <button className="btn sm danger" style={{ marginLeft: 6 }} onClick={() => removeTerm(t.id, t.name)}>Delete</button>
                      </>
                    )}
                  </td>
                </tr>,
                expandedId === t.id && (
                  <tr key={t.id + '-x'}>
                    <td></td>
                    <td colSpan="5">
                      <table>
                        <thead><tr><th>Exam</th><th>Class</th><th>Subject</th><th>Marks</th><th>Status</th><th>Entry</th><th>Actions</th></tr></thead>
                        <tbody>
                          {t.exams.map(x => (
                            <tr key={x.id}>
                              <td>{x.name}</td>
                              <td>{x.class_name} ({x.section})</td>
                              <td>{x.subject_name}</td>
                              <td>{x.marks_count || 0} / {x.student_count || 0}</td>
                              <td>{statusBadge(x.status)}</td>
                              <td>{Number(x.entry_open) === 0
                                ? <span className="badge locked">Closed</span>
                                : <span className="badge editable">Open</span>}</td>
                              <td>
                                <button className="btn sm" onClick={() => viewMarks(x.id)}>Marks</button>
                                <button className="btn sm ghost" style={{ marginLeft: 6 }} onClick={() => openEdit(x)}>Edit</button>
                                {Number(x.entry_open) === 0
                                  ? <button className="btn sm green" style={{ marginLeft: 6 }} disabled={busy} onClick={() => setEntry(x.id, 1)}>Open Entry</button>
                                  : <button className="btn sm amber" style={{ marginLeft: 6 }} disabled={busy} onClick={() => setEntry(x.id, 0)}>Revoke</button>}
                                {x.status !== 'published' && <button className="btn sm green" style={{ marginLeft: 6 }} disabled={busy} onClick={() => setStatus(x.id, 'published')}>Publish</button>}
                                {x.status === 'published' && <button className="btn sm amber" style={{ marginLeft: 6 }} disabled={busy} onClick={() => setStatus(x.id, 'unpublished')}>Unpublish</button>}
                                <button className="btn sm danger" style={{ marginLeft: 6 }} onClick={() => removeExam(x.id)}>Delete</button>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </td>
                  </tr>
                )
              ]))}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'class_test' && (
        <div className="panel">
          <div style={{ marginBottom: 12 }}>
            <h3>Class Tests — created by teachers. Admin: View Marks / Delete only.</h3>
          </div>
          <table>
            <thead><tr><th>Test Name</th><th>Class & Subject</th><th>Teacher</th><th>Date</th><th>Status</th><th>Actions</th></tr></thead>
            <tbody>
              {classTests.map(x => (
                <tr key={x.id}>
                  <td>{x.name}</td>
                  <td>{x.class_name} ({x.section}) — {x.subject_name}</td>
                  <td>{x.created_by_name}</td>
                  <td>{x.exam_date ? x.exam_date.slice(0, 10) : '-'}</td>
                  <td>{statusBadge(x.status)}</td>
                  <td>
                    <button className="btn sm" onClick={() => viewMarks(x.id)}>View Marks</button>
                    <button className="btn sm danger" style={{ marginLeft: 6 }} onClick={() => removeExam(x.id)}>Delete</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'approvals' && (
        <div className="panel">
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
            <h3>Mark Edit Requests — ৫ ঘণ্টা পার হলে teacher-এর re-edit অনুমতি</h3>
            <div>
              <select value={reqFilter} onChange={e => { setReqFilter(e.target.value); loadRequests(e.target.value); }}>
                <option value="pending">Pending</option>
                <option value="approved">Approved</option>
                <option value="rejected">Rejected</option>
              </select>
              <button className="btn sm ghost" style={{ marginLeft: 6 }} onClick={() => loadRequests()}>Refresh</button>
            </div>
          </div>
          <table>
            <thead><tr><th>Teacher</th><th>Student</th><th>Exam</th><th>Reason</th><th>Asked</th><th>Actions</th></tr></thead>
            <tbody>
              {requests.length === 0 && <tr><td colSpan="6" className="muted">কোনো request নেই।</td></tr>}
              {requests.map(r => (
                <tr key={r.id}>
                  <td>{r.teacher_name}</td>
                  <td>{r.student_name} (Roll {r.roll})<br /><span className="muted" style={{ fontSize: 11 }}>{r.class_name} ({r.section})</span></td>
                  <td>{r.exam_name}<br /><span className="muted" style={{ fontSize: 11 }}>{r.subject_name}</span></td>
                  <td style={{ maxWidth: 220 }}>{r.reason || '—'}</td>
                  <td style={{ fontSize: 11 }}>{String(r.created_at).slice(0, 16).replace('T', ' ')}</td>
                  <td>
                    {r.status === 'pending' ? (
                      <>
                        <button className="btn sm green" disabled={busy} onClick={() => decideRequest(r.id, 'approve')}>Approve (+৫ঘণ্টা)</button>
                        <button className="btn sm danger" style={{ marginLeft: 6 }} disabled={busy} onClick={() => decideRequest(r.id, 'reject')}>Reject</button>
                      </>
                    ) : <span className="muted">{r.status}</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showNewTerm && (
        <div className="modal-bg" onClick={() => setShowNewTerm(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>Create Exam Event — Half Yearly / Annual / Pre-Test / Test</h3>
            <form onSubmit={createTerm}>
              <div className="form-row">
                <div><label>Event Name *</label><input value={termName} onChange={e => setTermName(e.target.value)} placeholder="Test Examination 2026" required /></div>
              </div>
              <div className="form-row">
                <div><label>Kind *</label>
                  <select value={newTermKind} onChange={e => setNewTermKind(e.target.value)}>
                    <option value="half_yearly">Half Yearly (Class 6-9, promotion নয়)</option>
                    <option value="annual">Annual (Class 6-9, promotion জড়িত)</option>
                    <option value="pretest">Pre-Test (Class 10, promotion নয়)</option>
                    <option value="test">Test Exam (Class 10, promotion জড়িত)</option>
                  </select>
                </div>
                <div><label>Year *</label><input type="number" value={newTermYear} onChange={e => setNewTermYear(e.target.value)} required /></div>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={() => setShowNewTerm(false)}>Cancel</button>
                <button type="submit" className="btn">Create</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {editTermFor && (
        <div className="modal-bg" onClick={() => setEditTermFor(null)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>Rename Term</h3>
            <form onSubmit={renameTerm}>
              <div className="form-row">
                <div><label>Term Name *</label><input value={termName} onChange={e => setTermName(e.target.value)} required /></div>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={() => setEditTermFor(null)}>Cancel</button>
                <button type="submit" className="btn">Save</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {showForm && (
        <div className="modal-bg" onClick={closeForm}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>{editId ? 'Edit Exam' : 'Create Exam'} — {form.event_id ? (events.find(ev => ev.id === Number(form.event_id)) || {}).name : 'Term Exam'}</h3>
            <form onSubmit={save}>
              <div className="form-row">
                <div><label>Exam Name *</label><input value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Half Yearly - Math" required /></div>
                <div><label>Type</label>
                  <select value={form.exam_type} onChange={e => setForm({ ...form, exam_type: e.target.value })}>
                    <option value="half_yearly">Half Yearly</option>
                    <option value="annual">Annual</option>
                    <option value="pretest">Pre-Test</option>
                    <option value="test">Test Exam</option>
                    <option value="final">Final</option>
                    <option value="midterm">Midterm</option>
                    <option value="class_test">Class Test</option>
                  </select>
                </div>
              </div>
              <div className="form-row">
                <div><label>Step 1 — Class *</label>
                  <select value={exClsName} onChange={e => { setExClsName(e.target.value); setExSec(''); setForm({ ...form, class_id: '', subject_id: '' }); }} required>
                    <option value="">Select class</option>
                    {exClassNames.map(n => <option key={n} value={n}>{n}</option>)}
                  </select>
                </div>
                <div><label>Step 2 — {exIsGroup ? 'Group' : 'Section'} *</label>
                  <select value={exSec} onChange={e => {
                    setExSec(e.target.value);
                    const row = exClassRows.find(r => (exIsGroup ? r.group_name : r.section) === e.target.value);
                    setForm({ ...form, class_id: row ? String(row.id) : '', subject_id: '' });
                  }} disabled={!exClsName} required>
                    <option value="">{exIsGroup ? 'Select group' : 'Select section'}</option>
                    {exSecOpts.map(s => <option key={s} value={s}>{s}</option>)}
                  </select>
                </div>
              </div>
<div className="form-row">
                <div><label>Term / Event</label>
                  <select value={form.event_id} onChange={e => setForm({ ...form, event_id: e.target.value })}>
                    <option value="">(None)</option>
                    {events.map(ev => <option key={ev.id} value={ev.id}>{ev.name}</option>)}
                  </select>
                </div>
                <div><label>Exam Date (marks entry closes at end of this day)</label>
                  <input type="date" value={form.exam_date} onChange={e => setForm({ ...form, exam_date: e.target.value })} />
                </div>
                <div><label>Entry Deadline — নির্দিষ্ট তারিখ ও সময় পর্যন্ত entry (খালি = খোলা)</label>
                  <input type="datetime-local" value={form.entry_deadline} onChange={e => setForm({ ...form, entry_deadline: e.target.value })} />
                </div>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={closeForm}>Cancel</button>
                <button type="submit" className="btn">{editId ? 'Save' : 'Create'}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {marksFor && (
        <div className="modal-bg" onClick={() => setMarksFor(null)}>
          <div className="modal" style={{ width: 640 }} onClick={e => e.stopPropagation()}>
            <h3>Marks — {exam ? exam.name : ''} <span className="muted">({exam ? typeLabel(exam.exam_type) : ''})</span></h3>
            <p className="muted" style={{ marginBottom: 10 }}>Teacher ৫ ঘণ্টা পর edit করতে পারবে না। Admin "Unlock" চাপলে teacher আবার ৫ ঘণ্টা edit করতে পারবে।</p>
            <table>
              <thead><tr><th>Roll</th><th>Student</th><th>Marks</th><th>Status</th><th>Actions</th></tr></thead>
              <tbody>
                {marks.length === 0 && <tr><td colSpan="5" className="muted">No marks entered yet.</td></tr>}
                {marks.map(m => (
                  <tr key={m.id}>
                    <td>{m.roll}</td><td>{m.student_name}</td>
                    <td>{m.marks} / {m.total}</td>
                    <td><span className={'badge ' + (m.editable ? 'editable' : 'locked')}>{m.editable ? 'Editable' : 'Locked'}</span></td>
                    <td>
                      <input style={{ width: 80 }} type="number" defaultValue={m.marks} onBlur={e => { if (Number(e.target.value) !== m.marks) editMark(m.id, e.target.value); }} />
                      {!m.editable && <button className="btn sm amber" style={{ marginLeft: 6 }} onClick={() => unlock(m.id)}>Unlock</button>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <div className="modal-actions">
              <button className="btn ghost" onClick={() => setMarksFor(null)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}