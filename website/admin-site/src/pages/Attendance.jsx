import { useState, useEffect } from 'react';
import { api } from '../api';

export default function Attendance() {
  const [rows, setRows] = useState([]);
  const [classes, setClasses] = useState([]);
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [classId, setClassId] = useState('');
  const [err, setErr] = useState('');
  useEffect(() => { api('/admin/classes').then(setClasses).catch(() => {}); }, []);
  useEffect(() => {
    const p = new URLSearchParams();
    if (date) p.set('date', date);
    if (classId) p.set('class_id', classId);
    api('/admin/attendance?' + p.toString()).then(setRows).catch(e => setErr(e.message));
  }, [date, classId]);

  return (
    <div>
      {err && <div className="error-msg">{err}</div>}
      <div className="panel">
        <h3>Attendance</h3>
        <div className="filters">
          <input type="date" value={date} onChange={e => setDate(e.target.value)} />
          <select value={classId} onChange={e => setClassId(e.target.value)}>
            <option value="">All classes</option>
            {classes.map(c => <option key={c.id} value={c.id}>{c.name} - {c.section}</option>)}
          </select>
        </div>
        <table>
          <thead><tr><th>Date</th><th>Student</th><th>Class</th><th>Roll</th><th>Status</th><th>Remark</th></tr></thead>
          <tbody>
            {rows.length === 0 && <tr><td colSpan="6" className="muted">No records found.</td></tr>}
            {rows.map(a => (
              <tr key={a.id}>
                <td>{a.date.slice(0, 10)}</td>
                <td>{a.student_name}</td>
                <td>{a.class_name} ({a.section})</td>
                <td>{a.roll}</td>
                <td><span className={'badge ' + a.status}>{a.status}</span></td>
                <td>{a.remark || '-'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}