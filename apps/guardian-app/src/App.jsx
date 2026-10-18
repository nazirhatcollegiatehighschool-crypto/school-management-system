import React, { useState } from 'react'
import axios from 'axios'
import './App.css'

const API_URL = 'https://school-management-system-5jqj.onrender.com'

export default function GuardianApp() {
  const [token, setToken] = useState(localStorage.getItem('token') || '')
  const [currentScreen, setCurrentScreen] = useState('login')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [profile, setProfile] = useState(null)
  const [linkedChildren, setLinkedChildren] = useState([])

  const handleLogin = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError('')
    
    try {
      const res = await axios.post(`${API_URL}/api/auth/guardian-login`, {
        username: e.target.username.value,
        password: e.target.password.value
      })
      setToken(res.data.token)
      localStorage.setItem('token', res.data.token)
      setProfile(res.data.user)
      loadChildren(res.data.token)
      setCurrentScreen('dashboard')
    } catch (err) {
      setError(err.response?.data?.error || 'Login failed')
    }
    setLoading(false)
  }

  const loadChildren = async (tk) => {
    try {
      const res = await axios.get(`${API_URL}/api/guardian/dashboard`, {
        headers: { Authorization: `Bearer ${tk}` }
      })
      setLinkedChildren(res.data.siblings || [])
    } catch (err) {
      console.error('Load children failed:', err)
    }
  }

  const handleLogout = () => {
    setToken('')
    localStorage.removeItem('token')
    setCurrentScreen('login')
    setProfile(null)
  }

  if (!token || currentScreen === 'login') {
    return (
      <div className="login-container">
        <div className="login-card">
          <h1>👨‍👩‍👧 Guardian App</h1>
          <h2>School Management System</h2>
          
          {error && <div className="error">{error}</div>}
          
          <form onSubmit={handleLogin}>
            <div className="form-group">
              <label>Email or Phone</label>
              <input type="text" name="username" placeholder="Enter email/phone" required />
            </div>
            <div className="form-group">
              <label>Password</label>
              <input type="password" name="password" placeholder="Enter password" required />
            </div>
            <button type="submit" disabled={loading}>
              {loading ? 'Logging in...' : 'Login'}
            </button>
          </form>

          <div className="server-info">
            <p>📡 Server: {API_URL}</p>
            <p>✅ Status: Ready</p>
          </div>
        </div>
      </div>
    )
  }

  if (currentScreen === 'dashboard') {
    return (
      <div className="mobile-container">
        <div className="header">
          <h1>👨‍👩‍👧 My Children</h1>
          <button onClick={handleLogout} className="logout-btn">Logout</button>
        </div>

        <div className="profile-card">
          <h2>👤 {profile?.name}</h2>
          <p>Contact: {profile?.phone}</p>
        </div>

        <div className="menu-grid" style={{ marginBottom: '30px' }}>
          {linkedChildren.map(child => (
            <div key={child.student.id} className="profile-card" style={{ gridColumn: '1 / -1' }}>
              <h3>{child.student.name}</h3>
              <p>Class: {child.student.class_name} {child.student.section}</p>
              <p>Roll: {child.student.roll}</p>
              <div className="stats-grid">
                <div className="stat">
                  <span className="label">Attendance</span>
                  <span className="value">{child.attendance_summary?.percentage || 0}%</span>
                </div>
                <div className="stat">
                  <span className="label">GPA</span>
                  <span className="value">3.85</span>
                </div>
              </div>
              <button 
                className="menu-item" 
                style={{ width: '100%', marginTop: '15px' }}
                onClick={() => setCurrentScreen(`child-${child.student.id}`)}
              >
                <span>📊 View Details</span>
              </button>
            </div>
          ))}
        </div>

        <button 
          className="menu-item" 
          style={{ width: '100%' }}
          onClick={() => setCurrentScreen('link-sibling')}
        >
          <span className="icon">🔗</span>
          <span>Link Another Child</span>
        </button>
      </div>
    )
  }

  if (currentScreen === 'link-sibling') {
    return (
      <div className="mobile-container">
        <button onClick={() => setCurrentScreen('dashboard')} className="back-btn">← Back</button>
        
        <div className="header">
          <h1>🔗 Link Child</h1>
        </div>

        <div className="profile-card">
          <form>
            <div className="form-group">
              <label>Student Name</label>
              <input type="text" placeholder="Enter student name" />
            </div>
            <div className="form-group">
              <label>Student Code</label>
              <input type="text" placeholder="Enter student code" />
            </div>
            <div className="form-group">
              <label>Reason</label>
              <textarea placeholder="Sibling relationship..."></textarea>
            </div>
            <button type="submit" className="submit-btn">📤 Send Link Request</button>
          </form>
        </div>
      </div>
    )
  }

  return (
    <div className="mobile-container">
      <button onClick={() => setCurrentScreen('dashboard')} className="back-btn">← Back</button>
      <div className="header">
        <h1>📊 Child Details</h1>
      </div>
      <div className="profile-card">
        <h2>📈 Attendance History</h2>
        <div className="stats-grid">
          <div className="stat">
            <span className="label">Present Days</span>
            <span className="value">168</span>
          </div>
          <div className="stat">
            <span className="label">Absent Days</span>
            <span className="value">12</span>
          </div>
          <div className="stat">
            <span className="label">Late Days</span>
            <span className="value">5</span>
          </div>
          <div className="stat">
            <span className="label">Annual %</span>
            <span className="value">92%</span>
          </div>
        </div>
      </div>
    </div>
  )
}