import { useState, useEffect } from 'react';
import { api } from '../api';

const EMPTY = { title: '', body: '', target_type: 'all', class_id: '', section: '' };

export default function Notifications() {
  const [rows, setRows] = useState([]);
  const [classes, setClasses] = useState([]);
  const [students, setStudents] = useState([]);
  const [notice, setNotice] = useState(EMPTY);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const load = () => api('/admin/notifications').then(setRows).catch(e => setErr(e.message));
  useEffect(() => {
    load();
    api('/admin/classes').then(setClasses).catch(() => {});
    api('/admin/students').then(setStudents).catch(() => setStudents([]));
  }, []);

  const send = async e => {
    e.preventDefault(); setErr(''); setMsg('');
    try {
      const body = { title: notice.title, body: notice.body, target_type: notice.target_type };
      if (notice.target_type === 'class' || notice.target_type === 'section') {
        if (!notice.class_id) throw new Error('Select a class');
        body.class_id = Number(notice.class_id);
      }
      if (notice.target_type === 'section') {
        if (!notice.section) throw new Error('Select a section');
        body.section = notice.section;
      }
      await api('/admin/notices', { method: 'POST', body });
      setMsg('Notice sent to guardian apps');
      setNotice(EMPTY);
      load();
    } catch (ex) { setErr(ex.message); }
  };

  const classRows = classes.filter(c => !notice.class_id || c.id === Number(notice.class_id));
  const sections = [...new Set(classRows.map(c => c.section))].sort();
  const classStudents = students.filter(s => !notice.class_id || s.class_id === Number(notice.class_id));

  return (
    <div>
      {err && <div className="error-msg">{err}</div>}
      {msg && <div className="success-msg">{msg}</div>}
      <div className="panel">
        <h3>Send Notice (guardian app-এ notification হিসেবে যাবে)</h3>
        <form onSubmit={send}>
          <div className="form-row">
            <div><label>Title *</label><input value={notice.title} onChange={e => setNotice({ ...notice, title: e.target.value })} required /></div>
            <div style={{ maxWidth: 220 }}>
              <label>Target</label>
              <select value={notice.target_type} onChange={e => setNotice({ ...notice, target_type: e.target.value })}>
                <option value="all">All guardians</option>
                <option value="class">One class</option>
                <option value="section">A class section</option>
              </select>
            </div>
          </div>
          {(notice.target_type === 'class' || notice.target_type === 'section') && (
            <div className="form-row">
              <div><label>Class *</label>
                <select value={notice.class_id} onChange={e => setNotice({ ...notice, class_id: e.target.value })} required>
                  <option value="">Select class</option>
                  {classes.map(c => <option key={c.id} value={c.id}>{c.name} - {c.section}</option>)}
                </select>
              </div>
              {notice.target_type === 'section' && (
                <div><label>Section *</label>
                  <select value={notice.section} onChange={e => setNotice({ ...notice, section: e.target.value })} required>
                    <option value="">Select section</option>
                    {sections.map(s => <option key={s} value={s}>Section {s}</option>)}
                  </select>
                </div>
              )}
            </div>
          )}
          <div className="form-row">
            <div><label>Message</label><textarea rows="3" value={notice.body} onChange={e => setNotice({ ...notice, body: e.target.value })} /></div>
          </div>
          <div style={{ marginBottom: 12 }} className="muted">
            {notice.target_type === 'all' && 'Will go to all guardians.'}
            {notice.target_type === 'class' && `Will go to ${classStudents.length} student(s) in the selected class.`}
            {notice.target_type === 'section' && `Will go to students of section ${notice.section || '…'} in the selected class.`}
          </div>
          <button className="btn" type="submit">Send Notice</button>
        </form>
      </div>

      <div className="panel">
        <h3>Notification Log</h3>
        <table>
          <thead><tr><th>Type</th><th>Title</th><th>Student / Class</th><th>Sent By</th><th>Time</th></tr></thead>
          <tbody>
            {rows.map(n => (
              <tr key={n.id}>
                <td><span className={'badge ' + (n.type === 'attendance' ? 'absent' : n.type === 'result' ? 'paid' : '')}>{n.type}</span></td>
                <td>{n.title}<br /><span className="muted">{n.body}</span></td>
                <td>{n.student_name || (n.class_name ? n.class_name + ' (' + n.section + ')' : 'All')}</td>
                <td>{n.sender_name || '-'}</td>
                <td className="muted">{new Date(n.created_at).toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}