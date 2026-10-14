import { useState, useEffect } from 'react';
import { api } from '../api';

function tierOf(className) {
  const n = String(className || '');
  if (/^class\s*([678])$/i.test(n)) return 'general';
  if (/^class\s*(9|10)$/i.test(n) || /^ssc/i.test(n)) return 'ssc';
  return 'other';
}

export default function Classes() {
  const [rows, setRows] = useState([]);
  const [teachers, setTeachers] = useState([]);
  const [subjects, setSubjects] = useState([]);
  const [tab, setTab] = useState('classes');
  const [err, setErr] = useState('');
  const [ok, setOk] = useState('');

  // cascade filters
  const [clsName, setClsName] = useState('');
  const [subClsName, setSubClsName] = useState('');
  const [subSec, setSubSec] = useState('');

  const [form, setForm] = useState({ name: '', section: '', group_name: '', teacher_id: '' });
  const [editing, setEditing] = useState(null);
  const [showForm, setShowForm] = useState(false);

  const [subForm, setSubForm] = useState(null); // edit modal state
  const [subEditingId, setSubEditingId] = useState(null);
  const [showSub, setShowSub] = useState(false);

  const load = () => {
    api('/admin/classes').then(setRows).catch(e => setErr(e.message));
    api('/admin/teachers').then(setTeachers).catch(() => {});
    api('/admin/subjects').then(setSubjects).catch(() => {});
  };
  useEffect(load, []);
  useEffect(() => { if (tab === 'subjects' && !subClsName) setSubClsName(clsName); }, [clsName, tab, subClsName]);

  const flash = (m) => { setOk(m); setTimeout(() => setOk(''), 2500); };

  // ---- cascade helpers ----
  const classNames = [...new Set(rows.map(c => c.name))];
  const classRows = rows.filter(c => c.name === clsName);
  const isGrouped = classRows.some(c => c.group_name && c.group_name !== '');
  const secOpts = isGrouped
    ? [...new Set(classRows.map(c => c.group_name).filter(Boolean))]
    : [...new Set(classRows.map(c => c.section))];

  const subClassRows = rows.filter(c => c.name === subClsName);
  const subIsGrouped = subClassRows.some(c => c.group_name && c.group_name !== '');
  const subSecOpts = subIsGrouped
    ? [...new Set(subClassRows.map(c => c.group_name).filter(Boolean))]
    : [...new Set(subClassRows.map(c => c.section))];

  const filteredClasses = classRows;
  const filteredSubjects = subjects.filter(s =>
    s.class_name === subClsName && (!subSec || s.section === subSec)
  );
  const currentTier = tierOf(subClsName);

  // ---- class save ----
  const save = async e => {
    e.preventDefault(); setErr('');
    try {
      const body = { ...form, teacher_id: form.teacher_id ? Number(form.teacher_id) : null };
      if (editing) await api('/admin/classes/' + editing, { method: 'PUT', body });
      else await api('/admin/classes', { method: 'POST', body });
      setShowForm(false); setEditing(null); setForm({ name: '', section: '', group_name: '', teacher_id: '' });
      load(); flash('Class saved');
    } catch (ex) { setErr(ex.message); }
  };

  // ---- class delete ----
  const removeClass = async c => {
    if (!window.confirm(`Delete class ${c.name} (${c.group_name || c.section})? Students, subjects and attendance of this class will be removed.`)) return;
    setErr('');
    try {
      await api('/admin/classes/' + c.id, { method: 'DELETE' });
      load(); flash('Class deleted');
    } catch (ex) { setErr(ex.message); }
  };

  // ---- class teacher assignment ----
  const assignClassTeacher = async (c, teacherId) => {
    setErr('');
    try {
      await api('/admin/classes/' + c.id, {
        method: 'PUT',
        body: { name: c.name, section: c.section, group_name: c.group_name || null, teacher_id: teacherId ? Number(teacherId) : null },
      });
      load(); flash('Class teacher assigned');
    } catch (ex) { setErr(ex.message); }
  };

  // ---- subject teacher assignment (full-body PUT so marks are preserved) ----
  const assignTeacher = async (s, teacherId) => {
    setErr('');
    try {
      const body = {
        name: s.name, class_id: s.class_id, teacher_id: teacherId ? Number(teacherId) : null,
        full_marks: s.full_marks, pass_marks: s.pass_marks || null, group_name: s.group_name || 'Compulsory',
        is_optional: !!s.is_optional, excluded_from_gpa: !!s.excluded_from_gpa,
        cq_full: s.cq_full || null, mcq_full: s.mcq_full || null, practical_full: s.practical_full || null,
        written_full: s.written_full || null, ca_full: s.ca_full || null,
        subject_code: s.subject_code || null, is_fourth_subject: !!s.is_fourth_subject,
        is_elective: !!s.is_elective, sort_order: s.sort_order,
      };
      await api('/admin/subjects/' + s.id, { method: 'PUT', body });
      load(); flash('Teacher assigned');
    } catch (ex) { setErr(ex.message); }
  };

  // ---- subject edit ----
  const editSubject = s => {
    setSubEditingId(s.id);
    setSubForm({
      name: s.name, teacher_id: s.teacher_id ? String(s.teacher_id) : '',
      full_marks: s.full_marks || 100, pass_marks: s.pass_marks != null ? s.pass_marks : '',
      group_name: s.group_name || 'Compulsory', is_optional: !!s.is_optional,
      excluded_from_gpa: !!s.excluded_from_gpa,
      cq_full: s.cq_full != null ? s.cq_full : '', mcq_full: s.mcq_full != null ? s.mcq_full : '',
      practical_full: s.practical_full != null ? s.practical_full : '',
      written_full: s.written_full != null ? s.written_full : '', ca_full: s.ca_full != null ? s.ca_full : '',
      subject_code: s.subject_code != null ? s.subject_code : '',
      is_fourth_subject: !!s.is_fourth_subject, is_elective: !!s.is_elective,
      sort_order: s.sort_order != null ? s.sort_order : '',
    });
    setShowSub(true);
  };

  const saveSubject = async e => {
    e.preventDefault(); setErr('');
    const num = (v, d) => (v === '' || v === null || v === undefined ? d : Number(v));
    try {
      const body = {
        name: subForm.name, class_id: Number(subClsRow().id), teacher_id: subForm.teacher_id ? Number(subForm.teacher_id) : null,
        full_marks: num(subForm.full_marks, 100),
        pass_marks: currentTier === 'general' ? num(subForm.pass_marks, 33) : (subForm.pass_marks === '' ? null : num(subForm.pass_marks, null)),
        group_name: subForm.group_name || 'Compulsory',
        is_optional: !!subForm.is_optional, excluded_from_gpa: !!subForm.excluded_from_gpa,
        cq_full: currentTier === 'ssc' ? (subForm.cq_full === '' ? null : num(subForm.cq_full, null)) : (subForm.cq_full === '' ? null : num(subForm.cq_full, null)),
        mcq_full: currentTier === 'ssc' ? (subForm.mcq_full === '' ? null : num(subForm.mcq_full, null)) : null,
        practical_full: currentTier === 'ssc' ? (subForm.practical_full === '' ? null : num(subForm.practical_full, null)) : (subForm.practical_full === '' ? null : num(subForm.practical_full, null)),
        written_full: subForm.written_full === '' || subForm.written_full === undefined ? null : num(subForm.written_full, null),
        ca_full: subForm.ca_full === '' || subForm.ca_full === undefined ? null : num(subForm.ca_full, null),
        subject_code: subForm.subject_code === '' ? null : num(subForm.subject_code, null),
        is_fourth_subject: !!subForm.is_fourth_subject, is_elective: !!subForm.is_elective,
        sort_order: subForm.sort_order === '' ? null : num(subForm.sort_order, null),
      };
      await api('/admin/subjects/' + subEditingId, { method: 'PUT', body });
      setShowSub(false); load(); flash('Subject updated');
    } catch (ex) { setErr(ex.message); }
  };

  const subClsRow = () => subClassRows.find(r => (subIsGrouped ? r.group_name : r.section) === subSec) || subClassRows[0] || {};

  const marksCell = s => {
    const tier = tierOf(s.class_name);
    const parts = [s.cq_full, s.mcq_full, s.practical_full, s.written_full, s.ca_full].filter(x => x !== null && x !== undefined);
    if (tier === 'ssc') return parts.length ? parts.join(' / ') : <span className="muted">—</span>;
    return [`${s.full_marks || 100}${s.pass_marks != null ? ' (pass ' + s.pass_marks + ')' : ''}`];
  };

  const subTypeBadge = s => {
    if (s.is_fourth_subject) return <span className="badge editable">4th</span>;
    if (s.is_elective) return <span className="badge" style={{ background: '#fef3c7', color: '#92400e' }}>Elective</span>;
    if (s.is_optional) return <span className="badge editable">Optional</span>;
    if (s.excluded_from_gpa) return <span className="muted">excluded</span>;
    return 'Main';
  };

  return (
    <div>
      {err && <div className="error-msg">{err}</div>}
      {ok && <div className="ok-msg" style={{ background: '#e8f5e9', color: '#1b5e20', padding: '8px 12px', borderRadius: 8, marginBottom: 10 }}>{ok}</div>}

      <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
        <button className={tab === 'classes' ? 'btn' : 'btn ghost'} onClick={() => setTab('classes')}>
          Class & Class Teacher Allocation
        </button>
        <button className={tab === 'subjects' ? 'btn' : 'btn ghost'} onClick={() => setTab('subjects')}>
          Subject & Marks Distribution
        </button>
      </div>

      {tab === 'classes' && (
        <div className="panel">
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12, flexWrap: 'wrap', gap: 8 }}>
            <h3>Class & Class Teacher Allocation</h3>
            <button className="btn" onClick={() => { setEditing(null); setForm({ name: '', section: '', group_name: '', teacher_id: '' }); setShowForm(true); }}>+ Add Class</button>
          </div>

          <div style={{ display: 'flex', gap: 10, marginBottom: 12, flexWrap: 'wrap' }}>
            <select value={clsName} onChange={e => setClsName(e.target.value)} style={{ maxWidth: 220 }}>
              <option value="">All classes</option>
              {classNames.map(n => <option key={n} value={n}>{n}</option>)}
            </select>
            {clsName && <span className="muted" style={{ alignSelf: 'center' }}>{isGrouped ? 'Groups' : 'Sections'}: {secOpts.join(', ')}</span>}
          </div>

          <table>
            <thead><tr><th>Class</th><th>Section / Group</th><th>Class Teacher</th><th>Students</th><th>Actions</th></tr></thead>
            <tbody>
              {(filteredClasses.length ? filteredClasses : rows).map(c => (
                <tr key={c.id}>
                  <td>{c.name}</td><td>{c.group_name || c.section}</td>
                  <td>
                    <select value={c.teacher_id || ''} onChange={e => assignClassTeacher(c, e.target.value)} style={{ maxWidth: 210 }}>
                      <option value="">— Unassigned —</option>
                      {teachers.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                    </select>
                  </td>
                  <td>{c.student_count}</td>
                  <td>
                    <button className="btn sm ghost" onClick={() => { setEditing(c.id); setForm({ name: c.name, section: c.group_name || c.section, group_name: c.group_name || '', teacher_id: c.teacher_id || '' }); setShowForm(true); }}>Edit</button>
                    <button className="btn sm ghost" style={{ color: '#c62828' }} onClick={() => removeClass(c)}>Delete</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'subjects' && (
        <div className="panel">
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12, flexWrap: 'wrap', gap: 8 }}>
            <h3>Subject & Marks Distribution — {currentTier === 'general' ? 'সাধারণ (Full Marks / Pass Marks)' : currentTier === 'ssc' ? 'SSC (CQ / MCQ / Practical)' : ''}</h3>
          </div>

          <div style={{ display: 'flex', gap: 10, marginBottom: 12, flexWrap: 'wrap' }}>
            <select value={subClsName} onChange={e => { setSubClsName(e.target.value); setSubSec(''); }}>
              <option value="">Select class</option>
              {classNames.map(n => <option key={n} value={n}>{n}</option>)}
            </select>
            <select value={subSec} onChange={e => setSubSec(e.target.value)} disabled={!subClsName}>
              <option value="">Select {subIsGrouped ? 'group' : 'section'}</option>
              {subSecOpts.map(s => <option key={s} value={s}>{s}</option>)}
            </select>
          </div>

          {!subClsName || !subSec ? (
            <div className="muted" style={{ padding: '18px 4px' }}>
              উপরে Class ও Section/Group নির্বাচন করুন। ‹ফিল্টার করে শুধু সেই ক্লাসের subjects দেখানো হবে›
            </div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Subject</th><th>Code</th>
                  <th>{currentTier === 'general' ? 'Marks (Full / Pass)' : 'CQ / MCQ / Practical'}</th>
                  <th>Type</th><th>Teacher</th><th></th>
                </tr>
              </thead>
              <tbody>
                {filteredSubjects.map(s => (
                  <tr key={s.id}>
                    <td>{s.name}</td>
                    <td>{s.subject_code || <span className="muted">—</span>}</td>
                    <td>{marksCell(s)}</td>
                    <td>{subTypeBadge(s)}</td>
                    <td style={{ maxWidth: 200 }}>
                      <select value={s.teacher_id || ''} onChange={e => assignTeacher(s, e.target.value)}>
                        <option value="">— Unassigned —</option>
                        {teachers.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                      </select>
                    </td>
                    <td><button className="btn sm ghost" onClick={() => editSubject(s)}>Edit</button></td>
                  </tr>
                ))}
                {filteredSubjects.length === 0 && (
                  <tr><td colSpan="6" className="muted" style={{ textAlign: 'center' }}>এই class/section-এ কোনো subject নেই</td></tr>
                )}
              </tbody>
            </table>
          )}
        </div>
      )}

      {showSub && (
        <div className="modal-bg" onClick={() => setShowSub(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>Edit Subject — {subClsName} {subSec}</h3>
            <form onSubmit={saveSubject}>
              <div className="form-row">
                <div><label>Subject Name *</label><input value={subForm.name} onChange={e => setSubForm({ ...subForm, name: e.target.value })} required /></div>
                <div><label>NCTB Code</label><input type="number" value={subForm.subject_code} onChange={e => setSubForm({ ...subForm, subject_code: e.target.value })} placeholder="101" /></div>
              </div>

              {currentTier === 'general' ? (
                <div className="form-row">
                  <div><label>Full Marks</label><input type="number" value={subForm.full_marks} onChange={e => setSubForm({ ...subForm, full_marks: e.target.value })} /></div>
                  <div><label>Pass Marks (NCTB)</label><input type="number" value={subForm.pass_marks} onChange={e => setSubForm({ ...subForm, pass_marks: e.target.value })} placeholder="33" /></div>
                </div>
              ) : (
                <>
                  <div className="form-row">
                    <div><label>Full Marks</label><input type="number" value={subForm.full_marks} onChange={e => setSubForm({ ...subForm, full_marks: e.target.value })} /></div>
                    <div><label>CQ (Creative / সৃজনশীল)</label><input type="number" value={subForm.cq_full} onChange={e => setSubForm({ ...subForm, cq_full: e.target.value })} placeholder="e.g. 70" /></div>
                    <div><label>MCQ (বহুনির্বাচনী)</label><input type="number" value={subForm.mcq_full} onChange={e => setSubForm({ ...subForm, mcq_full: e.target.value })} placeholder="e.g. 30" /></div>
                  </div>
                  <div className="form-row">
                    <div><label>Practical (ব্যবহারিক)</label><input type="number" value={subForm.practical_full} onChange={e => setSubForm({ ...subForm, practical_full: e.target.value })} placeholder="e.g. 25" /></div>
                    <div><label>Written (লিখিত)</label><input type="number" value={subForm.written_full} onChange={e => setSubForm({ ...subForm, written_full: e.target.value })} placeholder="optional" /></div>
                    <div><label>CA (ধারাবাহিক মূল্যায়ন)</label><input type="number" value={subForm.ca_full} onChange={e => setSubForm({ ...subForm, ca_full: e.target.value })} placeholder="optional" /></div>
                  </div>
                  <div className="form-row">
                    <div><label>Pass Marks (optional)</label><input type="number" value={subForm.pass_marks} onChange={e => setSubForm({ ...subForm, pass_marks: e.target.value })} placeholder="33" /></div>
                  </div>
                  <div className="muted" style={{ fontSize: 12, marginTop: 4 }}>
                    টিপস: CQ + MCQ + Practical + Written + CA-র যোগফল Full Marks-এর সাথে মিলিয়ে দিন — teacher-রা component-wise নম্বর দিলে system নিজে total হিসাব করবে।
                  </div>
                </>
              )}

              <div className="form-row">
                <div><label>Type</label>
                  <div style={{ display: 'flex', gap: 14, alignItems: 'center', paddingTop: 20, flexWrap: 'wrap' }}>
                    <label style={{ display: 'flex', gap: 6, alignItems: 'center', margin: 0 }}>
                      <input type="checkbox" style={{ width: 'auto' }} checked={subForm.is_optional} onChange={e => setSubForm({ ...subForm, is_optional: e.target.checked })} /> Optional
                    </label>
                    <label style={{ display: 'flex', gap: 6, alignItems: 'center', margin: 0 }}>
                      <input type="checkbox" style={{ width: 'auto' }} checked={subForm.is_fourth_subject} onChange={e => setSubForm({ ...subForm, is_fourth_subject: e.target.checked })} /> 4th Subject Pool
                    </label>
                    <label style={{ display: 'flex', gap: 6, alignItems: 'center', margin: 0 }}>
                      <input type="checkbox" style={{ width: 'auto' }} checked={subForm.is_elective} onChange={e => setSubForm({ ...subForm, is_elective: e.target.checked })} /> Elective
                    </label>
                    <label style={{ display: 'flex', gap: 6, alignItems: 'center', margin: 0 }}>
                      <input type="checkbox" style={{ width: 'auto' }} checked={subForm.excluded_from_gpa} onChange={e => setSubForm({ ...subForm, excluded_from_gpa: e.target.checked })} /> GPA-র বাইরে
                    </label>
                  </div>
                </div>
              </div>

              <div className="form-row">
                <div><label>Teacher</label>
                  <select value={subForm.teacher_id} onChange={e => setSubForm({ ...subForm, teacher_id: e.target.value })}>
                    <option value="">— Unassigned —</option>
                    {teachers.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                  </select>
                </div>
                <div><label>Sort Order</label><input type="number" value={subForm.sort_order} onChange={e => setSubForm({ ...subForm, sort_order: e.target.value })} /></div>
              </div>

              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={() => setShowSub(false)}>Cancel</button>
                <button type="submit" className="btn">Save</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {showForm && (
        <div className="modal-bg" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>{editing ? 'Edit Class' : 'Add Class'}</h3>
            <form onSubmit={save}>
              <div className="form-row">
                <div><label>Class Name *</label><input value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Class 9" required /></div>
                <div><label>Section / Group *</label><input value={form.section} onChange={e => setForm({ ...form, section: e.target.value })} placeholder="A" required /></div>
              </div>
              {tierOf(form.name) === 'ssc' && (
                <div className="form-row">
                  <div><label>SSC Track</label>
                    <select value={form.group_name} onChange={e => setForm({ ...form, group_name: e.target.value })}>
                      <option value="">— Select track —</option>
                      <option value="Science">Science</option>
                      <option value="Commerce">Commerce</option>
                      <option value="Arts">Arts (Humanities)</option>
                    </select>
                  </div>
                </div>
              )}
              <div className="form-row">
                <div><label>Class Teacher</label>
                  <select value={form.teacher_id} onChange={e => setForm({ ...form, teacher_id: e.target.value })}>
                    <option value="">— Unassigned —</option>
                    {teachers.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                  </select>
                </div>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={() => setShowForm(false)}>Cancel</button>
                <button type="submit" className="btn">{editing ? 'Update' : 'Add'}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}