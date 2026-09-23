import { useState, useEffect } from 'react';
import { api } from '../api';

const empty = { name: '', username: '', password: '', phone: '', email: '', designation: '', sort_order: '', classTeacher: [] };

export default function Teachers() {
  const [rows, setRows] = useState([]);
  const [allClasses, setAllClasses] = useState([]);
  const [form, setForm] = useState(empty);
  const [editing, setEditing] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const [ctCls, setCtCls] = useState('');   // class-teacher cascade: class name
  const [ctSec, setCtSec] = useState('');   // ...then section / group
  const [requests, setRequests] = useState([]);
  const load = async () => {
    try {
      const [teachers, classes, reqs] = await Promise.all([
        api('/admin/teachers'),
        api('/admin/classes'),
        api('/admin/class-teacher-requests')
      ]);
      setRows(teachers);
      setAllClasses(classes);
      setRequests(reqs || []);
    } catch (e) { setErr(e.message); }
  };
  useEffect(() => { load(); }, []);

  const save = async e => {
    e.preventDefault(); setErr(''); setMsg('');
    try {
      const body = { ...form };
      if (editing && !body.password) delete body.password;
      delete body.classTeacher;
      body.class_teacher = form.classTeacher;
      body.sort_order = body.sort_order !== '' ? Number(body.sort_order) : 99;
      if (editing) {
        await api('/admin/teachers/' + editing, { method: 'PUT', body });
      } else {
        await api('/admin/teachers', { method: 'POST', body });
      }
      setMsg(editing ? 'Teacher updated' : 'Teacher created — login ID/password ready');
      setShowForm(false); setEditing(null); setForm(empty); load();
    } catch (ex) { setErr(ex.message); }
  };

  const del = async id => {
    if (!confirm('Delete this teacher?')) return;
    try { await api('/admin/teachers/' + id, { method: 'DELETE' }); load(); }
    catch (ex) { setErr(ex.message); }
  };

  const assignClassTeacher = () => {
    if (!ctCls || !ctSec) return;
    const match = allClasses.find(c => c.name === ctCls && (ctIsGroup ? c.group_name === ctSec : c.section === ctSec));
    if (!match) { setErr('Class/section combination not found'); return; }
    setErr('');
    setForm(f => ({ ...f, classTeacher: f.classTeacher.includes(match.id) ? f.classTeacher : [...f.classTeacher, match.id] }));
    setCtSec('');
  };

  const removeClassTeacher = id => setForm(f => ({ ...f, classTeacher: f.classTeacher.filter(x => x !== id) }));

  const startEdit = (t) => {
    setEditing(t.id);
    setForm({
      name: t.name, username: t.username, password: '',
      phone: t.phone || '', email: t.email || '',
      designation: t.designation || '', sort_order: t.sort_order != null ? t.sort_order : '',
      classTeacher: t.class_teacher_ids || []
    });
    setCtCls(''); setCtSec('');
    setShowForm(true);
  };

  const ctClassNames = [...new Set(allClasses.map(c => c.name))];
  const ctRows = allClasses.filter(c => c.name === ctCls);
  const ctIsGroup = ctRows.some(c => c.group_name);
  const ctSecOpts = ctIsGroup
    ? [...new Set(ctRows.map(c => c.group_name).filter(Boolean))]
    : [...new Set(ctRows.map(c => c.section))];
  const classRow = id => allClasses.find(c => c.id === id);

  const decideRequest = async (id, approve) => {
    try {
      if (approve && !confirm('Approve and assign this teacher as class teacher?')) return;
      await api(`/admin/class-teacher-requests/${id}/${approve ? 'approve' : 'reject'}`, { method: 'POST' });
      load();
    } catch (ex) { setErr(ex.message); }
  };

  const pendingRequests = requests.filter(r => r.status === 'pending');

  return (
    <div>
      {err && <div className="error-msg">{err}</div>}
      {msg && <div className="success-msg">{msg}</div>}
      {pendingRequests.length > 0 && (
        <div className="panel" style={{ background: '#fff8e1', border: '1px solid #ffe082', marginBottom: 12 }}>
          <h3>🕘 Class Teacher Requests ({pendingRequests.length}) — পেন্ডিং অনুমোদন</h3>
          <table>
            <thead><tr><th>Teacher</th><th>Class</th><th>Current Class Teacher</th><th>Note</th><th>Actions</th></tr></thead>
            <tbody>
              {pendingRequests.map(rq => (
                <tr key={rq.id}>
                  <td>{rq.teacher_name}</td>
                  <td>{rq.class_name} ({rq.group_name || rq.section})</td>
                  <td style={{ fontSize: 12 }}>{rq.current_teacher_name || <span style={{ color: '#999' }}>—</span>}</td>
                  <td style={{ fontSize: 12 }}>{rq.note || '—'}</td>
                  <td style={{ whiteSpace: 'nowrap' }}>
                    <button className="btn sm ghost" onClick={() => decideRequest(rq.id, false)}>Reject</button>{' '}
                    <button className="btn sm" onClick={() => decideRequest(rq.id, true)}>Approve</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <div className="panel">
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
          <h3>Teachers ({rows.length}) — এখানেই teacher-দের login ID/password তৈরি হয়</h3>
          <button className="btn" onClick={() => { setEditing(null); setForm(empty); setCtCls(''); setCtSec(''); setShowForm(true); }}>+ Add Teacher</button>
        </div>
        <table>
          <thead><tr><th>#</th><th>Name</th><th>Designation</th><th>Login ID</th><th>Phone</th><th>Class Teacher</th><th>Actions</th></tr></thead>
          <tbody>
            {rows.map(t => (
              <tr key={t.id}>
                <td>{t.sort_order ?? '-'}</td>
                <td>{t.name}</td>
                <td>{t.designation || '-'}</td>
                <td>{t.username}</td>
                <td>{t.phone || '-'}</td>
                <td style={{ fontSize: 12 }}>
                  {(t.class_teacher || []).length === 0 ? <span style={{ color: '#999' }}>—</span> :
                    (t.class_teacher || []).map((ct, i) => (
                      <span key={i} style={{ display: 'inline-block', background: '#e8f5e9', borderRadius: 4, padding: '2px 6px', marginRight: 4, marginBottom: 2 }}>
                        {ct.class} {ct.group || ct.section}
                      </span>
                    ))
                  }
                </td>
                <td>
                  <button className="btn sm ghost" onClick={() => startEdit(t)}>Edit</button>{' '}
                  <button className="btn sm red" onClick={() => del(t.id)}>Delete</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {showForm && (
        <div className="modal-bg" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxHeight: '90vh', overflowY: 'auto' }}>
            <h3>{editing ? 'Edit Teacher' : 'Add Teacher (creates app login)'}</h3>
            <form onSubmit={save}>
              <div className="form-row">
                <div><label>Name *</label><input value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} required /></div>
                <div><label>Login ID (username) *</label><input value={form.username} onChange={e => setForm({ ...form, username: e.target.value })} required /></div>
              </div>
              <div className="form-row">
                <div><label>Designation (পদবি)</label><input value={form.designation} onChange={e => setForm({ ...form, designation: e.target.value })} placeholder="Assistant Teacher / Headmaster" /></div>
                <div><label>Sort Order (serial #)</label><input type="number" value={form.sort_order} onChange={e => setForm({ ...form, sort_order: e.target.value })} placeholder="1" /></div>
              </div>
              <div className="form-row">
                <div><label>Password *{editing && ' (blank = keep old)'}</label><input value={form.password} onChange={e => setForm({ ...form, password: e.target.value })} placeholder={editing ? 'Leave blank to keep' : 'Set password'} /></div>
                <div><label>Phone</label><input value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} /></div>
              </div>
              <hr style={{ margin: '14px 0', border: 'none', borderTop: '1px solid #eee' }} />
              <div style={{ marginBottom: 6 }}>
                <label style={{ fontWeight: 600 }}>Class Teacher — ধাপে ধাপে যেসব ক্লাসে এই teacher class teacher হবেন</label>
                <div style={{ fontSize: 12, color: '#666', marginBottom: 6 }}>Step 1: Class → Step 2: Section/Group → Assign। প্রতি ক্লাসে একজন class teacher; আগের assignee স্বয়ংক্রিয়ভাবে বাদ পড়বে।</div>
              </div>
              <div className="form-row" style={{ marginBottom: 8 }}>
                <div><label>Step 1 — Class *</label>
                  <select value={ctCls} onChange={e => { setCtCls(e.target.value); setCtSec(''); }}>
                    <option value="">Select class</option>
                    {ctClassNames.map(n => <option key={n} value={n}>{n}</option>)}
                  </select>
                </div>
                <div><label>Step 2 — {ctIsGroup ? 'Group' : 'Section'} *</label>
                  <select value={ctSec} onChange={e => setCtSec(e.target.value)} disabled={!ctCls}>
                    <option value="">{ctIsGroup ? 'Select group' : 'Select section'}</option>
                    {ctSecOpts.map(s => <option key={s} value={s}>{s}</option>)}
                  </select>
                </div>
                <div style={{ display: 'flex', alignItems: 'flex-end' }}>
                  <button type="button" className="btn" disabled={!ctCls || !ctSec} onClick={assignClassTeacher}>+ Assign</button>
                </div>
              </div>
              <div style={{ fontSize: 12, color: '#666', marginBottom: 4 }}>নির্বাচিত ({form.classTeacher.length}):</div>
              {form.classTeacher.length === 0 && <div style={{ fontSize: 12, color: '#999', marginBottom: 8 }}>কোনো ক্লাস নির্বাচিত হয়নি।</div>}
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 8 }}>
                {form.classTeacher.map(id => {
                  const c = classRow(id);
                  return (
                    <span key={id} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, background: '#e8f5e9', borderRadius: 14, padding: '4px 10px', fontSize: 13 }}>
                      {c ? `${c.name} (${c.group_name || c.section})` : '#' + id}
                      <button type="button" style={{ border: 'none', background: 'none', color: '#c62828', cursor: 'pointer', fontSize: 14, lineHeight: 1 }} onClick={() => removeClassTeacher(id)} title="Remove">✕</button>
                    </span>
                  );
                })}
              </div>
              <div className="modal-actions">
                <button type="button" className="btn ghost" onClick={() => setShowForm(false)}>Cancel</button>
                <button type="submit" className="btn">{editing ? 'Update' : 'Create'}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
