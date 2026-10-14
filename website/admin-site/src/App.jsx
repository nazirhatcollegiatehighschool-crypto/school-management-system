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
import Promotions from './pages/Promotions';
import AdmitCards from './pages/AdmitCards';
import SeatPlan from './pages/SeatPlan';
import Settings from './pages/Settings';
import SiblingRequests from './pages/SiblingRequests';
import Routines from './pages/Routines';

const PAGES = [
  ['dashboard', 'Dashboard', Dashboard, '📊'],
  ['students', 'Students', Students, '🎓'],
  ['teachers', 'Teachers', Teachers, '👨‍🏫'],
  ['classes', 'Classes & Subjects', Classes, '🏫'],
  ['exams', 'Exams & Marks', Exams, '📝'],
  ['results', 'Events & Results', Results, '🏆'],
  ['published', 'Published Exams', () => <Results initialTab="published" />, '📢'],
  ['marksheet', 'Marksheet', Marksheet, '📜'],
  ['promotions', 'Promotions', Promotions, '⬆️'],
  ['routines', 'Routines Matrix', Routines, '📅'],
  ['admitcards', 'Admit Cards', AdmitCards, '🎫'],
  ['seatplan', 'Seat Plan', SeatPlan, '🪑'],
  ['siblings', 'Sibling Requests', SiblingRequests, '👨‍👩‍👧'],
  ['attendance', 'Attendance', Attendance, '✅'],
  ['notifications', 'Notifications', Notifications, '🔔'],
  ['settings', 'Settings & Holidays', Settings, '⚙️']
];

export default function App() {
  const [token, setTok] = useState(localStorage.getItem('token') || '');
  const [page, setPage] = useState('dashboard');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');

  useEffect(() => {
    window.__onSessionExpired = () => { setToken(''); setTok(''); };
    return () => { delete window.__onSessionExpired; };
  }, []);

  const login = async e => {
    e.preventDefault();
    setErr('');
    setLoading(true);
    try {
      final: {
        const r = await api('/auth/login', { method: 'POST', body: { username, password } });
        if (r.user.role !== 'admin') {
          setErr('Admin access only. Use the mobile apps for teacher and guardian logins.');
          break final;
        }
        setToken(r.token);
        setTok(r.token);
      }
    } catch (ex) {
      setErr(ex.message || 'Login failed. Please check credentials.');
    } finally {
      setLoading(false);
    }
  };

  if (!token) {
    return (
      <div className="login-wrap">
        <div className="login-box">
          <div style={{ textAlign: 'center', marginBottom: 20 }}>
            <div style={{
              width: 64, height: 64, margin: '0 auto 14px',
              background: 'linear-gradient(135deg, #2563eb, #1e40af)',
              borderRadius: '50%', display: 'flex', alignItems: 'center',
              justifyContent: 'center', fontSize: 32, boxShadow: '0 8px 16px rgba(37,99,235,0.3)'
            }}>
              🏫
            </div>
            <h1>School Administration</h1>
            <p>Nazirhat Collegiate High School • Admin Portal</p>
          </div>
          {err && <div className="error-msg">{err}</div>}
          <form onSubmit={login}>
            <div style={{ marginBottom: 14 }}>
              <label style={{ fontSize: 13, fontWeight: 600, color: '#334155', display: 'block', marginBottom: 6 }}>
                Username
              </label>
              <input
                placeholder="Enter admin username"
                value={username}
                onChange={e => setUsername(e.target.value)}
                autoFocus
                required
              />
            </div>
            <div style={{ marginBottom: 20, position: 'relative' }}>
              <label style={{ fontSize: 13, fontWeight: 600, color: '#334155', display: 'block', marginBottom: 6 }}>
                Password
              </label>
              <div style={{ position: 'relative' }}>
                <input
                  type={showPassword ? 'text' : 'password'}
                  placeholder="Enter password"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  style={{ paddingRight: 40 }}
                  required
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(s => !s)}
                  style={{
                    position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)',
                    background: 'none', border: 'none', cursor: 'pointer', fontSize: 16,
                    color: '#64748b'
                  }}
                  title={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? '👁️' : '👁️‍🗨️'}
                </button>
              </div>
            </div>
            <button
              className="btn"
              style={{ width: '100%', padding: '12px', fontSize: 15 }}
              type="submit"
              disabled={loading}
            >
              {loading ? 'Signing in...' : 'Sign In to Dashboard'}
            </button>
          </form>
        </div>
      </div>
    );
  }

  const Active = PAGES.find(p => p[0] === page)[2];
  const [menuOpen, setMenuOpen] = useState(false);
  const go = id => { setPage(id); setMenuOpen(false); };
  const activePageInfo = PAGES.find(p => p[0] === page);

  return (
    <div className="app-col">
      <header className="menubar no-print">
        <div className="brand">
          <span>🏫 Nazirhat Collegiate</span>
          <span className="brand-badge">ADMIN</span>
        </div>
        <button className="menu-toggle" onClick={() => setMenuOpen(o => !o)} aria-label="Menu">
          ☰
        </button>
        <nav className={menuOpen ? 'open' : ''}>
          {PAGES.map(([id, label, , icon]) => (
            <button key={id} className={page === id ? 'active' : ''} onClick={() => go(id)}>
              <span>{icon}</span>
              <span>{label}</span>
            </button>
          ))}
        </nav>
        <div className="topbar-right">
          <h2>{activePageInfo[3]} {activePageInfo[1]}</h2>
          <button className="logout" onClick={() => { setToken(''); setTok(''); }}>
            Logout
          </button>
        </div>
      </header>
      <main className="main">
        <ErrorBoundary key={page}>
          <Active />
        </ErrorBoundary>
      </main>
    </div>
  );
}