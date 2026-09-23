import { useState, useEffect } from 'react';
import { api } from '../api';

export default function SeatPlan() {
  const [classes, setClasses] = useState([]);
  const [events, setEvents] = useState([]);
  const [students, setStudents] = useState([]);
  const [classId, setClassId] = useState('');
  const [eventId, setEventId] = useState('');
  const [rooms, setRooms] = useState(2);
  const [plan, setPlan] = useState(null);
  const [err, setErr] = useState('');
  const [eventName, setEventName] = useState('');

  useEffect(() => {
    api('/admin/classes').then(setClasses).catch(() => {});
    api('/results/events').then(setEvents).catch(() => {});
  }, []);
  useEffect(() => {
    if (!classId) return;
    api('/admin/students').then(all => setStudents(all.filter(s => s.class_id === Number(classId)))).catch(() => {});
  }, [classId]);

  const generate = () => {
    if (!students.length) return;
    const perRoom = Math.ceil(students.length / rooms);
    const roomsArr = [];
    let idx = 0;
    for (let r = 0; r < rooms; r++) {
      const roomStudents = students.slice(idx, idx + perRoom);
      idx += perRoom;
      const seats = [];
      for (let i = 0; i < roomStudents.length; i += 2) {
        seats.push([roomStudents[i], roomStudents[i + 1] || null]);
      }
      roomsArr.push({ room: `Room ${r + 1}`, seats });
    }
    setPlan(roomsArr);
  };

  const ev = events.find(e => e.id === Number(eventId));

  return (
    <div>
      {err && <div className="error-msg no-print">{err}</div>}
      <div className="panel no-print">
        <h3>Seat Plan — পরীক্ষার আসন বিন্যাস</h3>
        <div className="doc-toolbar">
          <div><label>Class</label>
            <select value={classId} onChange={e => { setClassId(e.target.value); setPlan(null); }}>
              <option value="">Select class</option>
              {classes.map(c => <option key={c.id} value={c.id}>{c.name} - {c.section}</option>)}
            </select>
          </div>
          <div><label>Exam Event</label>
            <select value={eventId} onChange={e => { setEventId(e.target.value); setEventName((events.find(x => x.id === Number(e.target.value)) || {}).name || ''); setPlan(null); }}>
              <option value="">Select event</option>
              {events.map(ev2 => <option key={ev2.id} value={ev2.id}>{ev2.name}</option>)}
            </select>
          </div>
          <div><label>Rooms</label>
            <input type="number" min="1" max="20" value={rooms} onChange={e => setRooms(Number(e.target.value) || 1)} style={{ width: 80 }} />
          </div>
          <button className="btn" disabled={!classId || !eventId} onClick={generate}>⚙ Generate Seat Plan</button>
        </div>
      </div>

      {plan && (
        <div className="print-sheet">
          <div className="doc-header">
            <h1>Seat Plan</h1>
            <div className="addr">{eventName}{classId ? ` — ${((classes.find(c => c.id === Number(classId)) || {}).name || '')}` : ''}</div>
          </div>
          {plan.map(r => (
            <div key={r.room} style={{ marginBottom: 20 }}>
              <h3 style={{ marginBottom: 8 }}>{r.room} ({r.seats.length * 2 - r.seats.filter(row => !row[1]).length} students)</h3>
              <table className="seat-table" style={{ width: '100%' }}>
                <thead><tr><th>Desk</th><th>Left Seat</th><th>Right Seat</th></tr></thead>
                <tbody>
                  {r.seats.map((row, i) => (
                    <tr key={i}>
                      <td>{i + 1}</td>
                      <td>{row[0] ? `${row[0].roll}. ${row[0].name}` : ''}</td>
                      <td>{row[1] ? `${row[1].roll}. ${row[1].name}` : '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ))}
          <div className="no-print">
            <button className="btn" onClick={() => window.print()}>🖨️ Print Seat Plan</button>
          </div>
        </div>
      )}
    </div>
  );
}