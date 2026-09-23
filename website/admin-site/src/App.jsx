import { useState, useEffect } from 'react';
import { api, setToken } from './api';
import ErrorBoundary from './ErrorBoundary';
import Dashboard from './pages/Dashboard';
import Students from './pages/Students';
import Teachers from './pages/Teachers';
import Classes from './pages/Classes';
import Exams from './pages/Exams';
import Attendance from './pages/Attendance';
import Notifications from './pages/Notifications';
import Results from './pages/Results';
import Marksheet from './pages/Marksheet';
import AdmitCards from './pages/AdmitCards';
import SeatPlan from './pages/SeatPlan';
import Settings from './pages/Settings';
import SiblingRequests from './pages/SiblingRequests';
import Routines from './pages/Routines';

const PAGES = [
  ['dashboard', 'Dashboard', Dashboard],
  ['students', 'Students', Students],
  ['teachers', 'Teachers', Teachers],
  ['classes', 'Classes & Subjects', Classes],
  ['exams', 'Exams & Marks', Exams],
  ['results', 'Events & Results', Results],
  ['marksheet', 'Marksheet', Marksheet],
  ['routines', 'Routines Matrix', Routines],
  ['admitcards', 'Admit Cards', AdmitCards],
  ['seatplan', 'Seat Plan', SeatPlan],
  ['siblings', 'Sibling Requests', SiblingRequests],
  ['attendance', 'Attendance', Attendance],
  ['notifications', 'Notifications', Notifications],
  ['settings', 'Settings & Holidays', Settings]
];

export default function App() {
  const [token, setTok] = useState(localStorage.getItem('token') || '');
  const [page, setPage] = useState('dashboard');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState('');

  useEffect(() => {
    window.__onSessionExpired = () => { setToken(''); setTok(''); };
    return () => { delete window.__onSessionExpired; };
  }, []);

  const login = async e => {
    e.preventDefault(); setErr('');
    try {
      const r = await api('/auth/login', { method: 'POST', body: { username, password } });
      if (r.user.role !== 'admin') { setErr('Admin only. Use the mobile apps for teacher/guardian.'); return; }
      setToken(r.token);
      setTok(r.token);
    } catch (ex) { setErr(ex.message); }
  };

  if (!token) {
    return (
      <div className="login-wrap">
        <div className="login-box">
          <h1>School Admin</h1>
          <p>Management dashboard login</p>
          {err && <div className="error-msg">{err}</div>}
          <form onSubmit={login}>
            <input placeholder="Username" value={username} onChange={e => setUsername(e.target.value)} />
            <input type="password" placeholder="Password" value={password} onChange={e => setPassword(e.target.value)} />
            <button className="btn" style={{ width: '100%' }} type="submit">Login</button>
          </form>
        </div>
      </div>
    );
  }

  const Active = PAGES.find(p => p[0] === page)[2];

  return (
    <div className="app">
      <aside className="sidebar">
        <h1>🏫 School Admin</h1>
        <nav>
          {PAGES.map(([id, label]) => (
            <button key={id} className={page === id ? 'active' : ''} onClick={() => setPage(id)}>{label}</button>
          ))}
        </nav>
      </aside>
      <main className="main">
        <div className="topbar">
          <h2>{PAGES.find(p => p[0] === page)[1]}</h2>
          <button className="logout" onClick={() => { setToken(''); setTok(''); }}>Logout</button>
        </div>
        <ErrorBoundary key={page}>
          <Active />
        </ErrorBoundary>
      </main>
    </div>
  );
}