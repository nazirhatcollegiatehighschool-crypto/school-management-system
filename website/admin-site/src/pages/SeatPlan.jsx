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
  const cls = classes.find(c => c.id === Number(classId));
  const school = 'Nazirhat Collegiate High School';
  const year = ev && ev.year ? ev.year : (ev ? (ev.session_name || '') : '');
  const secLabel = cls ? (cls.group_name ? `${cls.group_name} Group` : `Section ${cls.section}`) : '';
  // Flatten rooms into bench stickers with running bench numbers.
  const stickers = [];
  (plan || []).forEach(r => {
    let bench = 0;
    r.seats.forEach(row => {
      [row[0], row[1]].forEach(stu => {
        if (!stu) return;
        bench += 1;
        stickers.push({ ...stu, room: r.room, bench });
      });
    });
  });

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
          <div className="doc-header no-print" style={{ border: 'none' }}>
            <h2 style={{ fontSize: 18 }}>Preview — {stickers.length} bench stickers</h2>
          </div>
          <div className="sp-sheet">
            <div className="sp-header">{eventName}{year ? ` ${year}` : ''} — {cls ? `${cls.name} (${secLabel})` : ''}</div>
            {stickers.map(s => (
              <div className="sp-sticker" key={`${s.room}-${s.bench}`}>
                <div className="sp-head">
                  <span className="sp-emblem">N</span>
                  <div className="sp-school">{school}<small>{eventName} {year}</small></div>
                </div>
                <div className="sp-roll">Roll {s.roll}</div>
                <div className="sp-name">{s.name}</div>
                <div className="sp-id">ID: {s.student_code}</div>
                <div className="sp-meta">{cls ? cls.name : ''} · {secLabel} · Session {year}</div>
                <div className="sp-foot"><span className="sp-room-label">Room No: {String(s.room).replace(/\D/g, '') || s.room}</span><span className="sp-room-label">Bench No: {s.bench}</span></div>
              </div>
            ))}
          </div>
          <div className="no-print" style={{ marginTop: 16 }}>
            <button className="btn" onClick={() => window.print()}>🖨️ Print Seat Plan</button>
          </div>
        </div>
      )}
    </div>
  );
}