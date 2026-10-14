import { useState, useEffect } from 'react';
import { api } from '../api';

export default function Dashboard() {
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api('/admin/stats')
      .then(setStats)
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div style={{ padding: '40px 0', textAlign: 'center', color: '#64748b' }}>
        <div style={{ fontSize: 24, marginBottom: 8 }}>⏳</div>
        <div>Loading dashboard statistics...</div>
      </div>
    );
  }

  if (!stats) {
    return <div className="muted">Failed to load statistics. Please refresh.</div>;
  }

  const att = { present: 0, absent: 0, late: 0 };
  (stats.todayAttendance || []).forEach(a => {
    if (a.status in att) att[a.status] = Number(a.cnt) || 0;
  });

  const totalAtt = att.present + att.absent + att.late;
  const presentPct = totalAtt > 0 ? Math.round((att.present / totalAtt) * 100) : 0;

  const statItems = [
    { label: 'Students', count: stats.students, icon: '🎓', color: '#2563eb', bg: '#eff6ff' },
    { label: 'Teachers', count: stats.teachers, icon: '👨‍🏫', color: '#0d9488', bg: '#f0fdfa' },
    { label: 'Classes & Sections', count: stats.classes, icon: '🏫', color: '#7c3aed', bg: '#f5f3ff' },
    { label: 'Registered Guardians', count: stats.guardians, icon: '👨‍👩‍👧', color: '#0284c7', bg: '#f0f9ff' },
    { label: 'Exams & Tests', count: stats.exams, icon: '📝', color: '#ea580c', bg: '#fff7ed' },
  ];

  return (
    <div>
      {/* Top Welcome Header */}
      <div style={{
        background: 'linear-gradient(135deg, #1e293b, #0f172a)',
        color: '#ffffff',
        padding: '24px 28px',
        borderRadius: 16,
        marginBottom: 24,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        flexWrap: 'wrap',
        gap: 16,
        boxShadow: '0 4px 20px rgba(0,0,0,0.08)'
      }}>
        <div>
          <h2 style={{ fontSize: 22, fontWeight: 800, margin: 0, letterSpacing: '-0.4px', color: '#fff' }}>
            Administrative Control Center
          </h2>
          <p style={{ margin: '4px 0 0', color: '#94a3b8', fontSize: 13.5 }}>
            Nazirhat Collegiate High School • Real-time operational overview
          </p>
        </div>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <span style={{
            background: 'rgba(16, 185, 129, 0.2)',
            color: '#6ee7b7',
            border: '1px solid rgba(16, 185, 129, 0.3)',
            padding: '4px 12px',
            borderRadius: 999,
            fontSize: 12,
            fontWeight: 600,
            display: 'inline-flex',
            alignItems: 'center',
            gap: 6
          }}>
            <span style={{ width: 7, height: 7, background: '#10b981', borderRadius: '50%' }}></span>
            System Live & Ready
          </span>
        </div>
      </div>

      {/* Main Metric Cards */}
      <div className="cards" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))' }}>
        {statItems.map(item => (
          <div key={item.label} className="card" style={{ display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
              <span style={{
                background: item.bg,
                fontSize: 22,
                padding: '8px',
                borderRadius: 10,
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                width: 42,
                height: 42
              }}>
                {item.icon}
              </span>
              <span style={{ fontSize: 11, fontWeight: 700, color: item.color, background: item.bg, padding: '2px 8px', borderRadius: 6 }}>
                Active
              </span>
            </div>
            <div>
              <div className="num" style={{ color: item.color }}>{item.count ?? 0}</div>
              <div className="label">{item.label}</div>
            </div>
          </div>
        ))}
      </div>

      {/* Today's Attendance Overview */}
      <div className="panel" style={{ marginTop: 8 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <h3>📋 Today's Attendance Snapshot</h3>
          {totalAtt > 0 && (
            <span style={{ fontSize: 13, fontWeight: 700, color: '#059669', background: '#ecfdf5', padding: '4px 10px', borderRadius: 8 }}>
              {presentPct}% Present Today
            </span>
          )}
        </div>

        {totalAtt > 0 ? (
          <div>
            {/* Progress Bar */}
            <div style={{
              height: 10,
              background: '#e2e8f0',
              borderRadius: 99,
              overflow: 'hidden',
              display: 'flex',
              marginBottom: 18
            }}>
              <div style={{ width: `${(att.present / totalAtt) * 100}%`, background: '#10b981' }} title="Present" />
              <div style={{ width: `${(att.late / totalAtt) * 100}%`, background: '#f59e0b' }} title="Late" />
              <div style={{ width: `${(att.absent / totalAtt) * 100}%`, background: '#ef4444' }} title="Absent" />
            </div>

            {/* Attendance Counters */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 14 }}>
              <div style={{ background: '#ecfdf5', border: '1px solid #a7f3d0', padding: '14px', borderRadius: 12 }}>
                <div style={{ color: '#065f46', fontSize: 12, fontWeight: 600 }}>PRESENT</div>
                <div style={{ color: '#059669', fontSize: 26, fontWeight: 800, marginTop: 4 }}>{att.present}</div>
              </div>
              <div style={{ background: '#fef2f2', border: '1px solid #fecaca', padding: '14px', borderRadius: 12 }}>
                <div style={{ color: '#991b1b', fontSize: 12, fontWeight: 600 }}>ABSENT</div>
                <div style={{ color: '#dc2626', fontSize: 26, fontWeight: 800, marginTop: 4 }}>{att.absent}</div>
              </div>
              <div style={{ background: '#fffbeb', border: '1px solid #fde68a', padding: '14px', borderRadius: 12 }}>
                <div style={{ color: '#92400e', fontSize: 12, fontWeight: 600 }}>LATE</div>
                <div style={{ color: '#d97706', fontSize: 26, fontWeight: 800, marginTop: 4 }}>{att.late}</div>
              </div>
              <div style={{ background: '#f8fafc', border: '1px solid #e2e8f0', padding: '14px', borderRadius: 12 }}>
                <div style={{ color: '#475569', fontSize: 12, fontWeight: 600 }}>TOTAL LOGGED</div>
                <div style={{ color: '#0f172a', fontSize: 26, fontWeight: 800, marginTop: 4 }}>{totalAtt}</div>
              </div>
            </div>
          </div>
        ) : (
          <div style={{
            background: '#f8fafc',
            border: '1px dashed #cbd5e1',
            borderRadius: 12,
            padding: '24px',
            textAlign: 'center',
            color: '#64748b'
          }}>
            <div style={{ fontSize: 26, marginBottom: 6 }}>📝</div>
            <div style={{ fontWeight: 600, color: '#334155' }}>No attendance recorded yet today</div>
            <div style={{ fontSize: 13, marginTop: 2 }}>
              When teachers take attendance from the mobile app, statistics will appear here in real time.
            </div>
          </div>
        )}
      </div>
    </div>
  );
}