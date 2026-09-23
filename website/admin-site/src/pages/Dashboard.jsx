import { useState, useEffect } from 'react';
import { api } from '../api';

export default function Dashboard() {
  const [stats, setStats] = useState(null);
  useEffect(() => { api('/admin/stats').then(setStats).catch(console.error); }, []);
  if (!stats) return <div className="muted">Loading...</div>;
  const att = {};
  (stats.todayAttendance || []).forEach(a => { att[a.status] = a.cnt; });
  return (
    <div>
      <div className="cards">
        <div className="card"><div className="num">{stats.students}</div><div className="label">Students</div></div>
        <div className="card"><div className="num">{stats.teachers}</div><div className="label">Teachers</div></div>
        <div className="card"><div className="num">{stats.classes}</div><div className="label">Classes</div></div>
        <div className="card"><div className="num">{stats.guardians}</div><div className="label">Guardians</div></div>
        <div className="card"><div className="num">{stats.exams}</div><div className="label">Exams</div></div>
      </div>
      <div className="panel">
        <h3>Today's Attendance</h3>
        <p>Present: <b>{att.present || 0}</b> &nbsp; Absent: <b>{att.absent || 0}</b> &nbsp; Late: <b>{att.late || 0}</b></p>
        {(att.present || 0) + (att.absent || 0) + (att.late || 0) === 0 && (
          <p className="muted">No attendance recorded today yet.</p>
        )}
      </div>
    </div>
  );
}