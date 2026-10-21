// apps/serve.js - Simple server to serve all 3 apps
const express = require('express')
const path = require('path')
const cors = require('cors')

const app = express()
app.use(cors())
app.use(express.json())

// Serve Teacher App
app.use('/teacher', express.static(path.join(__dirname, 'teacher-app', 'dist')))
// Serve Guardian App
app.use('/guardian', express.static(path.join(__dirname, 'guardian-app', 'dist')))
// Serve Admin App
app.use('/admin', express.static(path.join(__dirname, 'admin-app', 'dist')))

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', apps: ['teacher', 'guardian', 'admin'] })
})

// Redirect root to teacher app
app.get('/', (req, res) => {
  res.redirect('/teacher')
})

const PORT = process.env.PORT || 3000
app.listen(PORT, () => {
  console.log(`
  🚀 School Management System Apps Running!
  
  📱 Teacher App:   http://localhost:${PORT}/teacher
  👨‍👩‍👧 Guardian App: http://localhost:${PORT}/guardian
  ⚙️ Admin Panel:   http://localhost:${PORT}/admin
  
  📡 Backend API:   https://school-management-system-brown-mu.vercel.app
  `)
})