import { useState, useEffect, useMemo } from 'react';
import { api } from '../api';
import { parseStudentPrompt, PROMPT_TEMPLATE } from '../lib/studentPromptParser';

const empty = {
  student_code: '', name: '', dob: '', roll: '', class_id: '',
  guardian_name: '', guardian_phone: '', guardian_email: '', address: '',
  father_name: '', mother_name: '', birth_cert_no: '', religion: '',
  gender: '', blood_group: '', optional_subject: '', phone: '', email: '', status: ''
};

export default function Students() {
  const [rows, setRows] = useState([]);
  const [classes, setClasses] = useState([]);
  const [form, setForm] = useState(empty);
  const [cls, setCls] = useState('');
  const [sec, setSec] = useState('');
  const [editing, setEditing] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const [subjStu, setSubjStu] = useState(null);
  const [subjData, setSubjData] = useState(null);
  const [availSel, setAvailSel] = useState('');
  const [search, setSearch] = useState('');
  const [filterCls, setFilterCls] = useState('');
  const [filterSec, setFilterSec] = useState('');
  const [viewMode, setViewMode] = useState('table');
  const [prompt, setPrompt] = useState('');
  const [promptMsg, setPromptMsg] = useState('');

  const load = () => {
    api('/admin/students').then(setRows).catch(e => setErr(e.message));
    api('/admin/classes').then(setClasses).catch(() => {});
  };
  useEffect(load, []);

  const loadSubjects = async (stu) => {
    setSubjStu(stu); setSubjData(null); setAvailSel('');
    try {
      const r = await api('/admin/students/' + stu.id + '/subjects');
      setSubjData(r);
    } catch (e) { setErr(e.message); setSubjStu(null); }
  };
  const toggleSubject = async (sid, action) => {
    try {
      await api('/admin/students/' + subjStu.id + '/subjects', { method: 'PUT', body: { subject_id: sid, ...action } });
      loadSubjects(subjStu);
    } catch (e) { setErr(e.message); }
  };
  const addAvailSubject = async () => {
    if (!availSel) return;
    const a = subjData.available.find(x => Number(x.subject_id) === Number(availSel));
    const action = a && (a.is_fourth_subject || a.pool_fourth) ? { is_fourth_subject: true }
      : a && (a.is_elective || a.pool_elective) ? { is_elective: true }
      : { is_elective: a && a.is_optional ? true : false };
    await toggleSubject(Number(availSel), action);
    setAvailSel('');
  };

  const classNames = [...new Set(classes.map(c => c.name))];
  const selectedClasses = classes.filter(c => c.name === cls);
  const isGroup = selectedClasses.some(c => c.group_name);
  const sectionOpts = isGroup
    ? [...new Set(selectedClasses.map(c => c.group_name).filter(Boolean))]
    : [...new Set(selectedClasses.map(c => c.section))];

  const filterSelectedClasses = classes.filter(c => c.name === filterCls);
  const filterIsGroup = filterSelectedClasses.some(c => c.group_name);
  const filterSectionOpts = filterIsGroup
    ? [...new Set(filterSelectedClasses.map(c => c.group_name).filter(Boolean))]
    : [...new Set(filterSelectedClasses.map(c => c.section))];

  const filtered = useMemo(() => {
    let list = rows;
    if (search.trim()) {
      const q = search.trim().toLowerCase();
      list = list.filter(s =>
        s.name.toLowerCase().includes(q) ||
        (s.student_code || '').toLowerCase().includes(q) ||
        String(s.roll).includes(q) ||
        (s.guardian_name || '').toLowerCase().includes(q)
      );
    }
    if (filterCls) list = list.filter(s => s.class_name === filterCls);
    if (filterSec) list = list.filter(s => s.section === filterSec);
    return list;
  }, [rows, search, filterCls, filterSec]);

  const rollNo = Number(form.roll);
  const dupStudent = (() => {
    if (!cls || !sec || !rollNo) return null;
    return rows.find(r =>
      r.class_name === cls && r.section === sec &&
      Number(r.roll) === rollNo && r.id !== editing) || null;
  })();

  const save = async e => {
    e.preventDefault();
    setErr(''); setMsg('');
    try {
      if (!cls || !sec) { setErr('Class and section/group are required'); return; }
      const match = classes.find(c => c.name === cls && (isGroup ? c.group_name === sec : c.section === sec));
      if (!match) { setErr('Class/section combination not found in Classes list'); return; }
      const body = { ...form, roll: Number(form.roll), class_id: match.id };
      let result;
      if (editing) await api('/admin/students/' + editing, { method: 'PUT', body });
      else {
        result = await api('/admin/students', { method: 'POST', body });
        setMsg('Student added! ID: ' + (result.student_code || ''));
      }
      setShowForm(false); setEditing(null); setForm(empty); setCls(''); setSec(''); load();
    } catch (ex) { setErr(ex.message); }
  };

  const del = async id => {
    if (!confirm('Delete this student?')) return;
    try { await api('/admin/students/' + id, { method: 'DELETE' }); load(); }
    catch (ex) { setErr(ex.message); }
  };

  const edit = s => {
    setEditing(s.id);
    setForm({
      student_code: s.student_code, name: s.name, dob: s.dob ? s.dob.slice(0, 10) : '',
      roll: s.roll, class_id: s.class_id, guardian_name: s.guardian_name || '',
      guardian_phone: s.guardian_phone || '', guardian_email: s.guardian_email || '', address: s.address || '',
      father_name: s.father_name || '', mother_name: s.mother_name || '', birth_cert_no: s.birth_cert_no || '',
      religion: s.religion || '', gender: s.gender || '', blood_group: s.blood_group || '',
      optional_subject: s.optional_subject || '', phone: s.phone || '', email: s.email || '',
      status: s.status || 'active'
    });
    setCls(s.class_name);
    setSec(s.section);
    setShowForm(true);
  };

  const fillFromPrompt = async () => {
    setPromptMsg('');
    const res = parseStudentPrompt(prompt);
    if (Object.keys(res).length === 0) { setPromptMsg('Prompt-এ কোনো তথ্য পাওয়া যায়নি। Template অনুযায়ী লিখে আবার চেষ্টা করুন।'); return; }
    setForm(f => ({
      ...f,
      name: res.name ?? f.name,
      roll: res.roll != null ? String(res.roll) : f.roll,
      dob: res.dob ?? f.dob,
      father_name: res.father_name ?? f.father_name,
      mother_name: res.mother_name ?? f.mother_name,
      birth_cert_no: res.birth_cert_no ?? f.birth_cert_no,
      guardian_name: res.guardian_name ?? f.guardian_name,
      guardian_phone: res.guardian_phone ?? f.guardian_phone,
      phone: res.phone ?? f.phone,
      email: res.email ?? f.email,
      gender: res.gender ?? f.gender,
      religion: res.religion === 'Hinduism' ? 'Hindu' : res.religion === 'Christianity' ? 'Christian' : res.religion === 'Buddhism' ? 'Buddhist' : (res.religion ?? f.religion),
      blood_group: res.blood_group ?? f.blood_group,
      optional_subject: res.optional_subject ?? f.optional_subject,
      address: res.address ?? f.address,
    }));
    setPromptMsg('✓ Prompt থেকে ফিল্ড পূরণ হয়েছে — মান যাচাই করে Class/Section বাছুন।');
  };

  const copyTemplate = async () => {
    try {
      await navigator.clipboard.writeText(PROMPT_TEMPLATE);
      setPromptMsg('✓ AI Prompt Template কপি হয়েছে');
    } catch (e) {
      setPrompt(PROMPT_TEMPLATE);
      setPromptMsg('কপি করা যায়নি — টেমপ্লেট টেক্সটবক্সে বসানো হয়েছে।');
    }
  };

  const resetForm = () => {
    setEditing(null); setForm(empty); setCls(''); setSec(''); setShowForm(true);
  };

  return (
    <div>
      {err && <div className="error-msg">{err}</div>}
      {msg && <div className="success-msg">{msg}</div>}
      <div className="panel">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12, flexWrap: 'wrap', gap: 10 }}>
          <h3>Students ({filtered.length}{filtered.length !== rows.length ? ` / ${rows.length}` : ''})</h3>
          <button className="btn" onClick={resetForm}>+ Add Student</button>
        </div>
        <div className="filters">
          <input
            type="text"
            placeholder="Search by name, code, roll, guardian..."
            value={search}
            onChange={e => setSearch(e.target.value)}
            style={{ minWidth: 240 }}
          />
          <select value={filterCls} onChange={e => { setFilterCls(e.target.value); setFilterSec(''); }}>
            <option value="">All Classes</option>
            {classNames.map(n => <option key={n} value={n}>{n}</option>)}
          </select>
          {filterCls && (
            <select value={filterSec} onChange={e => setFilterSec(e.target.value)}>
              <option value="">All {filterIsGroup ? 'Groups' : 'Sections'}</option>
              {filterSectionOpts.map(s => <option key={s} value={s}>{s}</option>)}
            </select>
          )}
          <div style={{ marginLeft: 'auto', display: 'flex', gap: 4 }}>
            <button className={`btn sm ${viewMode === 'table' ? '' : 'ghost'}`} onClick={() => setViewMode('table')}>Table</button>
            <button className={`btn sm ${viewMode === 'card' ? '' : 'ghost'}`} onClick={() => setViewMode('card')}>Cards</button>
          </div>
        </div>
        {viewMode === 'table' ? (
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead><tr><th>Code</th><th>Name</th><th>Class</th><th>Roll</th><th>DOB</th><th>Guardian</th><th>Phone</th><th>Status</th><th>Actions</th></tr></thead>
              <tbody>
                {filtered.map(s => (
                  <tr key={s.id}>
                    <td>{s.student_code}</td><td>{s.name}</td>
                    <td>{s.class_name} ({s.section})</td><td>{s.roll}</td>
                    <td>{s.dob ? s.dob.slice(0, 10) : '-'}</td>
                    <td>{s.guardian_name || '-'}</td><td>{s.guardian_phone || '-'}</td>
                    <td>{(!s.status || s.status === 'active')
                      ? <span className="badge editable">Active</span>
                      : <span className="badge locked">Inactive</span>}</td>
                    <td style={{ whiteSpace: 'nowrap' }}>
                      <button className="btn sm ghost" onClick={() => loadSubjects(s)}>Subjects</button>{' '}
                      <button className="btn sm ghost" onClick={() => edit(s)}>Edit</button>{' '}
                      <button className="btn sm red" onClick={() => del(s.id)}>Delete</button>
                    </td>
                  </tr>
                ))}
                {filtered.length === 0 && (
                  <tr><td colSpan={9} style={{ textAlign: 'center', color: '#64748b', padding: 20 }}>No students found</td></tr>
                )}
              </tbody>
            </table>
          </div>
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: 12 }}>
            {filtered.map(s => (
              <div key={s.id} style={{ background: '#fff', border: '1px solid var(--border)', borderRadius: 10, padding: 14 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
                  <div style={{ width: 36, height: 36, borderRadius: '50%', background: 'var(--primary)', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 700, fontSize: 14 }}>{s.roll}</div>
                  <div>
                    <div style={{ fontWeight: 600 }}>{s.name}</div>
                    <div className="muted">{s.class_name} ({s.section})</div>
                  </div>
                </div>
                <div style={{ fontSize: 13, color: 'var(--muted)', marginBottom: 10 }}>
                  <div>Code: {s.student_code || '-'}</div>
                  <div>DOB: {s.dob ? s.dob.slice(0, 10) : '-'}</div>
                  <div>Guardian: {s.guardian_name || '-'} {s.guardian_phone ? `(${s.guardian_phone})` : ''}</div>
                </div>
                <div style={{ display: 'flex', gap: 6 }}>
                  <button className="btn sm ghost" onClick={() => loadSubjects(s)}>Subjects</button>
                  <button className="btn sm ghost" onClick={() => edit(s)}>Edit</button>
                  <button className="btn sm red" onClick={() => del(s.id)}>Delete</button>
                </div>
              </div>
            ))}
            {filtered.length === 0 && (
              <div style={{ gridColumn: '1/-1', textAlign: 'center', color: '#64748b', padding: 20 }}>No students found</div>
            )}
          </div>
        )}
      </div>

      {showForm && (
        <div className="modal-bg" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>{editing ? 'Edit Student' : 'Add Student'}</h3>
            <form onSubmit={save}>
              {!editing && (
                <div style={{ background: '#f0f7ff', border: '1px solid #c9e3ff', borderRadius: 8, padding: 10, marginBottom: 12 }}>
                  <label>AI Prompt (বাংলা/English) — auto-fill</label>
                  <textarea
                    value={prompt}
                    onChange={e => setPrompt(e.target.value)}
                    rows={3}
                    style={{ width: '100%', boxSizing: 'border-box', marginTop: 4 }}
                    placeholder={'Name: ...\nRoll: 12\nFather\'s Name: ...'} />
                  <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                    <button type="button" className="btn sm" onClick={fillFromPrompt}>বিশ্লেষণ → ফিল করুন</button>
                    <button type="button" className="btn sm ghost" onClick={copyTemplate}>Copy Prompt Template</button>
                  </div>
                  {promptMsg && <div style={{ fontSize: 12, marginTop: 6, color: promptMsg.startsWith('✓') ? '#166534' : '#b91c1c' }}>{promptMsg}</div>}
                </div>
              )}
              <div className="form-row">
                <div><label>Student Code</label><input value={form.student_code} readOnly disabled placeholder="Auto-generated" title="Auto-generated on save" /></div>
                <div><label>Roll *</label><input type="number" value={form.roll}
                    onChange={e => setForm({ ...form, roll: e.target.value })}
                    style={dupStudent ? { border: '1px solid red' } : {}}
                    required />
                  {dupStudent && <div style={{ color: 'red', fontSize: 12, marginTop: 4 }}>Student with Roll {rollNo} already exists in this Class & {sec}!</div>}
                </div>
              </div>
              <div className="form-row">
                <div><label>Name *</label><input value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} required /></div>
                <div><label>Date of Birth</label><input type="date" value={form.dob} onChange={e => setForm({ ...form, dob: e.target.value })} /></div>
              </div>
              <div className="form-row">
                <div><label>Status *</label>
                  <select value={form.status || 'active'} onChange={e => setForm({ ...form, status: e.target.value })}>
                    <option value="active">Active</option>
                    <option value="inactive">Inactive (dropped out — no marks/attendance)</option>
                  </select>
                </div>
                <div></div>
              </div>
              <div className="form-row">
                <div><label>Gender</label>
                  <select value={form.gender} onChange={e => setForm({ ...form, gender: e.target.value })}>
                    <option value="">—</option>
                    <option>Male</option><option>Female</option><option>Other</option>
                  </select>
                </div>
                <div><label>Religion</label>
                  <select value={form.religion} onChange={e => setForm({ ...form, religion: e.target.value })}>
                    <option value="">—</option>
                    <option>Islam</option><option>Hindu</option><option>Christian</option><option>Buddhist</option><option>Other</option>
                  </select>
                </div>
              </div>
              <div className="form-row">
                <div><label>Class *</label>
                  <select value={cls} onChange={e => { setCls(e.target.value); setSec(''); setForm({ ...form, class_id: '' }); }} required>
                    <option value="">Select class</option>
                    {classNames.map(n => <option key={n} value={n}>{n}</option>)}
                  </select>
                </div>
                <div><label>{isGroup ? 'Group *' : 'Section *'}</label>
                  <select value={sec} onChange={e => setSec(e.target.value)} required>
                    <option value="">{isGroup ? 'Select group' : 'Select section'}</option>
                    {sectionOpts.map(s => <option key={s} value={s}>{s}</option>)}
                  </select>
                </div>
              </div>
              <div className="form-row">
                <div><label>Father's Name</label><input value={form.father_name} onChange={e => setForm({ ...form, father_name: e.target.value })} /></div>
                <div><label>Mother's Name</label><input value={form.mother_name} onChange={e => setForm({ ...form, mother_name: e.target.value })} /></div>
              </div>
              <div className="form-row">
                <div><label>Guardian Name</label><input value={form.guardian_name} onChange={e => setForm({ ...form, guardian_name: e.target.value })} /></div>
                <div><label>Guardian Phone (admission main number)</label><input value={form.guardian_phone} onChange={e => setForm({ ...form, guardian_phone: e.target.value })} placeholder="01XXXXXXXXX" /></div>
              </div>
              <div className="form-row">
                <div><label>Guardian Email</label><input type="email" value={form.guardian_email} onChange={e => setForm({ ...form, guardian_email: e.target.value })} /></div>
                <div><label>Student Phone</label><input value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} /></div>
              </div>
              <div className="form-row">
                <div><label>Blood Group</label><input value={form.blood_group} onChange={e => setForm({ ...form, blood_group: e.target.value })} placeholder="A+/B+/O-" /></div>
                <div><label>Optional Subject</label><input value={form.optional_subject} onChange={e => setForm({ ...form, optional_subject: e.target.value })} /></div>
              </div>
              <div className="form-row">
                <div><label>Birth Certificate No</label><input value={form.birth_cert_no} onChange={e => setForm({ ...form, birth_cert_no: e.target.value })} /></div>
                <div><label>Address</label><input value={form.address} onChange={e => setForm({ ...form, address: e.target.value })} /></div>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={() => setShowForm(false)}>Cancel</button>
                <button type="submit" className="btn" disabled={!!dupStudent}>{editing ? 'Update' : 'Add'}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {subjStu && (
        <div className="modal-bg" onClick={() => setSubjStu(null)}>
          <div className="modal wide" onClick={e => e.stopPropagation()}>
            <h3>Subjects of {subjStu.name} ({subjStu.class_name})</h3>
            {!subjData ? <p>Loading…</p> : (
              <>
                <h4>Assigned ({subjData.assigned.length})</h4>
                <table>
                  <thead><tr><th>Subject</th><th>Mandatory</th><th>4th Subject</th><th>Elective</th><th>Action</th></tr></thead>
                  <tbody>
                    {subjData.assigned.map(a => (
                      <tr key={a.subject_id}>
                        <td>{a.name}</td>
                        <td>{a.is_mandatory ? 'Yes' : 'No'}</td>
                        <td>{a.is_fourth_subject || a.pool_fourth ? 'Yes' : ''}</td>
                        <td>{a.is_elective || a.pool_elective ? 'Yes' : ''}</td>
                        <td>
                          {!a.is_mandatory && (
                            <button className="btn sm red" onClick={() => toggleSubject(a.subject_id, { remove: true })}>Remove</button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {subjData.available.length > 0 ? (
                  <>
                    <h4 style={{ marginTop: 16 }}>Add Subject — {subjStu.class_name}-এর অন্যান্য available বিষয়</h4>
                    <div style={{ display: 'flex', gap: 8, marginBottom: 10, flexWrap: 'wrap' }}>
                      <select value={availSel} onChange={e => setAvailSel(e.target.value)} style={{ flex: 1, minWidth: 220 }}>
                        <option value="">Select subject…</option>
                        {subjData.available.map(a => (
                          <option key={a.subject_id} value={a.subject_id}>
                            {a.name} — {a.is_fourth_subject ? '4th Subject' : a.is_elective ? 'Elective' : a.excluded_from_gpa ? 'Non-GPA' : a.is_optional ? 'Optional' : 'Subject'}
                          </option>
                        ))}
                      </select>
                      <button className="btn" disabled={!availSel} onClick={addAvailSubject}>+ Add</button>
                    </div>
                  </>
                ) : (
                  <p className="muted" style={{ marginTop: 12 }}>কোনো available বিষয় নেই।</p>
                )}
              </>
            )}
            <div className="modal-actions" style={{ marginTop: 12 }}>
              <button className="btn ghost" onClick={() => setSubjStu(null)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
