import { useState, useEffect } from 'react';
import { api } from '../api';

export default function AdmitCards() {
  const [classes, setClasses] = useState([]);
  const [events, setEvents] = useState([]);
  const [students, setStudents] = useState([]);
  const [classId, setClassId] = useState('');
  const [eventId, setEventId] = useState('');
  const [settings, setSettings] = useState({});
  const [err, setErr] = useState('');

  useEffect(() => {
    api('/admin/classes').then(setClasses).catch(e => setErr(e.message));
    api('/results/events').then(setEvents).catch(() => {});
    api('/admin/settings').then(setSettings).catch(() => {});
  }, []);
  useEffect(() => {
    if (!classId) return;
    api('/admin/students').then(all => setStudents(all.filter(s => s.class_id === Number(classId)))).catch(() => {});
  }, [classId]);

  const ev = events.find(e => e.id === Number(eventId));
  const cls = classes.find(c => c.id === Number(classId));

  return (
    <div>
      {err && <div className="error-msg no-print">{err}</div>}
      <div className="panel no-print">
        <h3>Admit Cards — প্রবেশপত্র</h3>
        <div className="doc-toolbar">
          <div><label>Class</label>
            <select value={classId} onChange={e => setClassId(e.target.value)}>
              <option value="">Select class</option>
              {classes.map(c => <option key={c.id} value={c.id}>{c.name} - {c.section}</option>)}
            </select>
          </div>
          <div><label>Exam Event</label>
            <select value={eventId} onChange={e => setEventId(e.target.value)}>
              <option value="">Select event</option>
              {events.map(ev => <option key={ev.id} value={ev.id}>{ev.name}</option>)}
            </select>
          </div>
        </div>
      </div>

      {classId && eventId && students.length > 0 && (
        <div className="print-sheet">
          <div className="doc-header no-print" style={{ border: 'none' }}>
            <h2 style={{ fontSize: 18 }}>Preview — {students.length} admit cards</h2>
          </div>
          <div className="admit-grid">
            {students.map(s => (
              <div className="admit-card" key={s.id}>
                <div className="head">{settings.school_name || 'My School'}</div>
                <div style={{ textAlign: 'center', fontSize: 12, padding: '4px', fontWeight: 700 }}>
                  {ev ? ev.name.toUpperCase() : ''} — ADMIT CARD
                </div>
                <div className="body">
                  <div className="stu-photo" style={{ width: 70, height: 85 }}>{s.photo ? <img src={`/uploads/${s.photo}`} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : 'Photo'}</div>
                  <div className="info">
                    <div><b>Name:</b> {s.name}</div>
                    <div><b>ID:</b> {s.student_code}</div>
                    <div><b>Class:</b> {s.class_name} ({s.section})</div>
                    <div><b>Roll:</b> {s.roll}</div>
                    <div><b>DOB:</b> {s.dob ? String(s.dob).slice(0, 10) : '-'}</div>
                  </div>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 12px', fontSize: 11 }}>
                  <span style={{ borderTop: '1px solid #0f172a' }}>Guardian's Signature</span>
                  <span style={{ borderTop: '1px solid #0f172a' }}>Headmaster</span>
                </div>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 16 }} className="no-print">
            <button className="btn" onClick={() => window.print()}>🖨️ Print All Admit Cards</button>
          </div>
        </div>
      )}
    </div>
  );
}