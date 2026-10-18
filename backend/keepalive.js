// keepalive.js - Prevents Render free tier from spinning down
const https = require('https');

const URL = 'https://school-management-system-5jqj.onrender.com/ping';

function ping() {
  const start = Date.now();
  
  https.get(URL, (res) => {
    const duration = Date.now() - start;
    console.log(`[${new Date().toISOString()}] 🏓 Ping: ${res.statusCode} (${duration}ms)`);
    
    if (res.statusCode === 200) {
      console.log('✅ Server is awake and responding');
    }
  }).on('error', (err) => {
    console.log(`[${new Date().toISOString()}] ❌ Ping failed: ${err.message}`);
  });
}

// Ping every 10 minutes (600000 ms) to keep Render awake
// Render spins down after 15 minutes of inactivity
const PING_INTERVAL = 10 * 60 * 1000; // 10 minutes

console.log('🚀 Keep-alive service started');
console.log(`📡 Target: ${URL}`);
console.log(`⏰ Interval: Every 10 minutes`);
console.log(`📝 Render free tier spins down after 15 min idle`);
console.log(`✅ This keeps server awake 24/7\n`);

// Initial ping
ping();

// Schedule pings
setInterval(ping, PING_INTERVAL);

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Keep-alive service stopped');
  process.exit(0);
});