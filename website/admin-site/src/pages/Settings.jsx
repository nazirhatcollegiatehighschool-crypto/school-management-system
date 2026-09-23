import { useState, useEffect } from 'react';
import { api } from '../api';

export default function Settings() {
  const [form, setForm] = useState({ school_name: '', school_address: '', school_eiin: '', headmaster: '', exam_term_name: '' });
  const [holidays, setHolidays] = useState([]);
  const [hDate, setHDate] = useState('');
  const [hTitle, setHTitle] = useState('');
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');

  const load = () => {
    api('/admin/settings').then(s => setForm(f => ({ ...f, ...s }))).catch(e => setErr(e.message));
    api('/admin/holidays').then(setHolidays).catch(() => {});
  };
  useEffect(load, []);

  const save = async e => {
    e.preventDefault(); setErr(''); setMsg('');
    try {
      await api('/admin/settings', { method: 'PUT', body: form });
      setMsg('Settings saved — documents এখন এই তথ্য ব্যবহার করবে');
    } catch (ex) { setErr(ex.message); }
  };

  const addHoliday = async e => {
    e.preventDefault(); setErr('');
    try {
      await api('/admin/holidays', { method: 'POST', body: { date: hDate, title: hTitle } });
      setHDate(''); setHTitle(''); load();
    } catch (ex) { setErr(ex.message); }
  };

  const delHoliday = async d => {
    try { await api('/admin/holidays/' + d, { method: 'DELETE' }); load(); }
    catch (ex) { setErr(ex.message); }
  };

  return (
    <div>
      {err && <div className="error-msg">{err}</div>}
      {msg && <div className="success-msg">{msg}</div>}
      <div className="panel">
        <h3>School Settings — marksheet/admit card-এ ব্যবহৃত হয়</h3>
        <form onSubmit={save}>
          <div className="form-row">
            <div><label>School Name</label><input value={form.school_name} onChange={e => setForm({ ...form, school_name: e.target.value })} /></div>
            <div><label>EIIN</label><input value={form.school_eiin} onChange={e => setForm({ ...form, school_eiin: e.target.value })} /></div>
          </div>
          <div className="form-row">
            <div><label>Address</label><input value={form.school_address} onChange={e => setForm({ ...form, school_address: e.target.value })} /></div>
            <div><label>Headmaster Name</label><input value={form.headmaster} onChange={e => setForm({ ...form, headmaster: e.target.value })} /></div>
          </div>
          <div className="form-row">
            <div><label>Default Exam Term Name</label><input value={form.exam_term_name} onChange={e => setForm({ ...form, exam_term_name: e.target.value })} /></div>
          </div>
          <button className="btn" type="submit">Save Settings</button>
        </form>
      </div>

      <div className="panel">
        <h3>Holidays — ছুটির দিন (attendance-তে বাদ যাবে)</h3>
        <form onSubmit={addHoliday} style={{ display: 'flex', gap: 10, marginBottom: 14, flexWrap: 'wrap' }}>
          <input type="date" value={hDate} onChange={e => setHDate(e.target.value)} style={{ width: 170 }} required />
          <input placeholder="কী ছুটি? যেমন: ঈদুল ফিতর" value={hTitle} onChange={e => setHTitle(e.target.value)} style={{ flex: 1, minWidth: 200 }} required />
          <button className="btn" type="submit">+ Add</button>
        </form>
        <table>
          <thead><tr><th>Date</th><th>Title</th><th></th></tr></thead>
          <tbody>
            {holidays.length === 0 && <tr><td colSpan="3" className="muted">No holidays added.</td></tr>}
            {holidays.map(h => (
              <tr key={h.date}>
                <td>{String(h.date).slice(0, 10)}</td><td>{h.title}</td>
                <td><button className="btn sm red" onClick={() => delHoliday(String(h.date).slice(0, 10))}>Delete</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}