import { useState, useEffect } from 'react';
import { api } from '../api';

export default function Exams() {
  const [tab, setTab] = useState('term');
  const [rows, setRows] = useState([]);
  const [classes, setClasses] = useState([]);
  const [subjects, setSubjects] = useState([]);
  const [events, setEvents] = useState([]);
  const [form, setForm] = useState({ name: '', exam_type: 'final', class_id: '', subject_id: '', event_id: '', exam_date: '' });
  const [editId, setEditId] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [termDetail, setTermDetail] = useState(null);
  const [termName, setTermName] = useState('');
  const [showNewTerm, setShowNewTerm] = useState(false);
  const [editTermFor, setEditTermFor] = useState(null);
  const [marksFor, setMarksFor] = useState(null);
  const [marks, setMarks] = useState([]);
  const [exClsName, setExClsName] = useState(''); // exam cascade: class name
  const [exSec, setExSec] = useState('');         // ...then section/group
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

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
  const unassigned = { id: 0, name: 'Unassigned Term Exams', exams: adminExams.filter(e => !e.event_id) };
  const termGroups = termDetail ? null : [...terms, unassigned].filter(t => t.id !== 0 || t.exams.length > 0);
  const currentTermExams = termDetail ? adminExams.filter(
    e => termDetail.id === 0 ? !e.event_id : e.event_id === termDetail.id
  ) : [];

  const closeForm = () => { setShowForm(false); setEditId(null); setExClsName(''); setExSec(''); setForm({ name: '', exam_type: 'final', class_id: '', subject_id: '', event_id: '', exam_date: '' }); };

  const save = async e => {
    e.preventDefault(); setErr('');
    try {
      const body = { ...form, class_id: Number(form.class_id), subject_id: Number(form.subject_id), event_id: form.event_id ? Number(form.event_id) : null };
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
    setForm({ name: '', exam_type: 'final', class_id: '', subject_id: '', event_id: String(eventId || ''), exam_date: '' });
    setExClsName(''); setExSec('');
    setShowForm(true);
  };

  const openEdit = x => {
    setEditId(x.id);
    setForm({ name: x.name, exam_type: x.exam_type, class_id: String(x.class_id), subject_id: String(x.subject_id), event_id: x.event_id ? String(x.event_id) : '', exam_date: x.exam_date ? x.exam_date.slice(0, 10) : '' });
    const crow = classes.find(c => c.id === Number(x.class_id));
    setExClsName(crow ? crow.name : '');
    setExSec(crow ? (crow.group_name || crow.section) : '');
    setShowForm(true);
  };

  const createTerm = async e => {
    e.preventDefault(); setErr('');
    try {
      await api('/results/events', { method: 'POST', body: { name: termName } });
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

  const removeTerm = async id => {
    if (id === 0) return;
    if (!window.confirm('Delete this term? Its exams will remain but become unassigned.')) return;
    setErr('');
    try { await api('/results/events/' + id, { method: 'DELETE' }); setTermDetail(null); load(); }
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
  const typeLabel = t => t === 'class_test' ? 'Class Test' : t === 'midterm' ? 'Midterm' : t === 'final' ? 'Final' : t;

  return (
    <div>
      {err && <div className="error-msg">{err}</div>}

      <div className="tabs no-print" style={{ marginBottom: 12 }}>
        <button className={'tab ' + (tab === 'term' ? 'active' : '')} onClick={() => setTab('term')}>Term Exams (Admin)</button>
        <button className={'tab ' + (tab === 'class_test' ? 'active' : '')} onClick={() => setTab('class_test')}>Class Tests (Teacher)</button>
      </div>

      {tab === 'term' && !termDetail && (
        <div className="panel">
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
            <h3>Term Exams — grouped by exam term; subject-wise marks inside</h3>
            <div>
              <button className="btn ghost" style={{ marginRight: 6 }} onClick={() => setShowNewTerm(true)}>+ Create Term</button>
              <button className="btn" onClick={() => openCreate()}>+ Create Exam</button>
            </div>
          </div>
          <table>
            <thead><tr><th>Term / Event</th><th>Session</th><th>Subjects</th><th>Published</th><th>Actions</th></tr></thead>
            <tbody>
              {termGroups.map(t => (
                <tr key={t.id}>
                  <td><b>{t.name}</b></td>
                  <td>{t.session_name || '-'}</td>
                  <td>{t.exams.length}</td>
                  <td>{t.exams.filter(e => e.status === 'published').length} / {t.exams.length}</td>
                  <td>
                    <button className="btn sm" onClick={() => setTermDetail(t)}>Manage Marks</button>
                    {t.id !== 0 && (
                      <>
                        <button className="btn sm ghost" style={{ marginLeft: 6 }} onClick={() => { setEditTermFor(t); setTermName(t.name); }}>Edit Term</button>
                        <button className="btn sm danger" style={{ marginLeft: 6 }} onClick={() => removeTerm(t.id)}>Delete Term</button>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'term' && termDetail && (
        <div className="panel">
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
            <h3>Marks — {termDetail.name}</h3>
            <div>
              <button className="btn green" style={{ marginRight: 6 }} onClick={() => openCreate(termDetail.id)}>+ Add Subject Exam</button>
              <button className="btn ghost" onClick={() => setTermDetail(null)}>← Back to Terms</button>
            </div>
          </div>
          <table>
            <thead><tr><th>Exam</th><th>Class</th><th>Subject</th><th>Date</th><th>Marks</th><th>Status</th><th>Actions</th></tr></thead>
            <tbody>
              {currentTermExams.map(x => (
                <tr key={x.id}>
                  <td>{x.name}</td>
                  <td>{x.class_name} ({x.section})</td>
                  <td>{x.subject_name}</td>
                  <td>{x.exam_date ? x.exam_date.slice(0, 10) : '-'}</td>
                  <td>{x.marks_count || 0} / {x.student_count || 0}</td>
                  <td>{statusBadge(x.status)}</td>
                  <td>
                    <button className="btn sm" onClick={() => viewMarks(x.id)}>Marks</button>
                    <button className="btn sm ghost" style={{ marginLeft: 6 }} onClick={() => openEdit(x)}>Edit</button>
                    {x.status !== 'published' && <button className="btn sm green" style={{ marginLeft: 6 }} disabled={busy} onClick={() => setStatus(x.id, 'published')}>Publish</button>}
                    {x.status === 'published' && <button className="btn sm amber" style={{ marginLeft: 6 }} disabled={busy} onClick={() => setStatus(x.id, 'unpublished')}>Unpublish</button>}
                    <button className="btn sm danger" style={{ marginLeft: 6 }} onClick={() => removeExam(x.id)}>Delete</button>
                  </td>
                </tr>
              ))}
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

      {showNewTerm && (
        <div className="modal-bg" onClick={() => setShowNewTerm(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>Create Term / Exam Event</h3>
            <form onSubmit={createTerm}>
              <div className="form-row">
                <div><label>Term Name *</label><input value={termName} onChange={e => setTermName(e.target.value)} placeholder="Half Yearly Examination 2026" required /></div>
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
            <p className="muted" style={{ marginBottom: 10 }}>Teacher ১০ মিনিট পর edit করতে পারবে না। Admin "Unlock" চাপলে teacher আবার edit করতে পারবে।</p>
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