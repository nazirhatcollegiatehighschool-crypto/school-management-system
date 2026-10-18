import React, { useState, useEffect } from 'react'
import axios from 'axios'
import './App.css'

const API_URL = 'https://school-management-system-5jqj.onrender.com'

export default function App() {
  const [token, setToken] = useState(localStorage.getItem('token') || '')
  const [currentScreen, setCurrentScreen] = useState('login')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [profile, setProfile] = useState(null)
  const [attendance, setAttendance] = useState([])
  const [demographics, setDemographics] = useState(null)

  // Login handler
  const handleLogin = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError('')
    
    const username = e.target.username.value
    const password = e.target.password.value

    try {
      const res = await axios.post(`${API_URL}/api/auth/login`, { username, password })
      const newToken = res.data.token
      setToken(newToken)
      localStorage.setItem('token', newToken)
      setCurrentScreen('dashboard')
      loadProfile(newToken)
    } catch (err) {
      setError(err.response?.data?.error || 'Login failed')
    }
    setLoading(false)
  }

  // Load profile
  const loadProfile = async (tk) => {
    try {
      const res = await axios.get(`${API_URL}/api/teacher/profile`, {
        headers: { Authorization: `Bearer ${tk}` }
      })
      setProfile(res.data)
      loadDemographics(tk, res.data.class_id)
    } catch (err) {
      console.error('Profile load failed:', err)
    }
  }

  // Load class demographics
  const loadDemographics = async (tk, classId) => {
    try {
      const res = await axios.get(`${API_URL}/api/teacher/class-demographics?class_id=${classId}`, {
        headers: { Authorization: `Bearer ${tk}` }
      })
      setDemographics(res.data)
    } catch (err) {
      console.error('Demographics load failed:', err)
    }
  }

  // Take attendance
  const handleTakeAttendance = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError('')

    try {
      await axios.post(
        `${API_URL}/api/teacher/attendance/take`,
        { class_id: profile.class_id, date: new Date().toISOString().split('T')[0], attendance },
        { headers: { Authorization: `Bearer ${token}` } }
      )
      alert('✅ Attendance submitted successfully')
      setCurrentScreen('dashboard')
    } catch (err) {
      setError(err.response?.data?.error || 'Attendance submission failed')
    }
    setLoading(false)
  }

  // Logout
  const handleLogout = () => {
    setToken('')
    localStorage.removeItem('token')
    setCurrentScreen('login')
    setProfile(null)
  }

  // Login screen
  if (!token || currentScreen === 'login') {
    return (
      <div className="login-container">
        <div className="login-card">
          <h1>🏫 Teacher App</h1>
          <h2>School Management System</h2>
          
          {error && <div className="error">{error}</div>}
          
          <form onSubmit={handleLogin}>
            <div className="form-group">
              <label>Username</label>
              <input type="text" name="username" placeholder="Enter username" required />
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

  // Dashboard
  if (currentScreen === 'dashboard') {
    return (
      <div className="mobile-container">
        <div className="header">
          <h1>📊 Dashboard</h1>
          <button onClick={handleLogout} className="logout-btn">Logout</button>
        </div>

        <div className="profile-card">
          <h2>👤 {profile?.name}</h2>
          <p>Role: {profile?.role}</p>
          <p>Class: {profile?.class_name} {profile?.section}</p>
        </div>

        {demographics && (
          <div className="demographics-card">
            <h3>📈 Class Demographics</h3>
            <div className="stats-grid">
              <div className="stat">
                <span className="label">Total Students</span>
                <span className="value">{demographics.total_students}</span>
              </div>
              <div className="stat">
                <span className="label">Male</span>
                <span className="value">{demographics.male_count}</span>
              </div>
              <div className="stat">
                <span className="label">Female</span>
                <span className="value">{demographics.female_count}</span>
              </div>
              <div className="stat">
                <span className="label">Islam</span>
                <span className="value">{demographics.islam_count}</span>
              </div>
            </div>
          </div>
        )}

        <div className="menu-grid">
          <button 
            className="menu-item"
            onClick={() => setCurrentScreen('attendance')}
          >
            <span className="icon">✍️</span>
            <span>Take Attendance</span>
          </button>
          <button 
            className="menu-item"
            onClick={() => setCurrentScreen('midday')}
          >
            <span className="icon">⏰</span>
            <span>Mid-Day Status</span>
          </button>
          <button 
            className="menu-item"
            onClick={() => setCurrentScreen('reports')}
          >
            <span className="icon">📋</span>
            <span>Reports</span>
          </button>
          <button 
            className="menu-item"
            onClick={() => setCurrentScreen('requests')}
          >
            <span className="icon">🔓</span>
            <span>Unlock Requests</span>
          </button>
        </div>
      </div>
    )
  }

  // Attendance screen
  if (currentScreen === 'attendance') {
    return (
      <div className="mobile-container">
        <button onClick={() => setCurrentScreen('dashboard')} className="back-btn">← Back</button>
        
        <div className="header">
          <h1>✍️ Take Attendance</h1>
        </div>

        {error && <div className="error">{error}</div>}

        <form onSubmit={handleTakeAttendance} className="attendance-form">
          <div className="info-box">
            <p>📅 Date: {new Date().toDateString()}</p>
            <p>⏰ Time: {new Date().toLocaleTimeString()}</p>
            <p>🔒 Lock time: 11:10 AM</p>
          </div>

          <div className="attendance-list">
            <h3>Students</h3>
            {[1, 2, 3, 4, 5].map(i => (
              <div key={i} className="attendance-item">
                <label>
                  <input type="checkbox" defaultChecked onChange={(e) => {
                    const newAttendance = [...attendance]
                    newAttendance[i-1] = { student_id: i, status: e.target.checked ? 'present' : 'absent' }
                    setAttendance(newAttendance)
                  }} />
                  <span>Student {i}</span>
                </label>
              </div>
            ))}
          </div>

          <button type="submit" disabled={loading} className="submit-btn">
            {loading ? 'Submitting...' : '✅ Submit Attendance'}
          </button>
        </form>
      </div>
    )
  }

  // Mid-day status screen
  if (currentScreen === 'midday') {
    return (
      <div className="mobile-container">
        <button onClick={() => setCurrentScreen('dashboard')} className="back-btn">← Back</button>
        
        <div className="header">
          <h1>⏰ Mid-Day Status</h1>
        </div>

        <div className="info-box">
          <p>📍 5th Period Real-Time Tracking</p>
          <p>⏰ Current Time: {new Date().toLocaleTimeString()}</p>
        </div>

        <div className="status-buttons">
          <button className="status-btn normal">🟢 Normal</button>
          <button className="status-btn ranaway">🔴 Ran Away</button>
          <button className="status-btn leave">🔵 On Leave</button>
          <button className="status-btn early">🟣 Early Departure</button>
        </div>

        <div className="students-list">
          <h3>Track Students</h3>
          {[1, 2, 3, 4, 5].map(i => (
            <div key={i} className="student-row">
              <span>Student {i}</span>
              <div className="status-badge normal">🟢 Normal</div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  // Reports screen
  if (currentScreen === 'reports') {
    return (
      <div className="mobile-container">
        <button onClick={() => setCurrentScreen('dashboard')} className="back-btn">← Back</button>
        
        <div className="header">
          <h1>📋 Reports</h1>
        </div>

        <div className="report-buttons">
          <button className="report-btn">📊 Weekly Attendance</button>
          <button className="report-btn">📈 Monthly Statistics</button>
          <button className="report-btn">🎓 Student Performance</button>
          <button className="report-btn">📉 Trends</button>
        </div>
      </div>
    )
  }

  // Requests screen
  if (currentScreen === 'requests') {
    return (
      <div className="mobile-container">
        <button onClick={() => setCurrentScreen('dashboard')} className="back-btn">← Back</button>
        
        <div className="header">
          <h1>🔓 Unlock Requests</h1>
        </div>

        <div className="info-box">
          <p>Request permission to edit attendance after 11:10 AM</p>
        </div>

        <form className="request-form">
          <div className="form-group">
            <label>Student</label>
            <select>
              <option>Select student...</option>
              <option>Student 1</option>
              <option>Student 2</option>
            </select>
          </div>
          <div className="form-group">
            <label>New Status</label>
            <select>
              <option>Present</option>
              <option>Absent</option>
              <option>Late</option>
              <option>Leave</option>
            </select>
          </div>
          <div className="form-group">
            <label>Reason</label>
            <textarea placeholder="Explain why you need to unlock..."></textarea>
          </div>
          <button type="submit" className="submit-btn">📤 Submit Request</button>
        </form>
      </div>
    )
  }
}