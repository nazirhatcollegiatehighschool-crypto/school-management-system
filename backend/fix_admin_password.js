const bcrypt = require('bcrypt');
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: '127.0.0.1', port: 3306, user: 'root', password: '', database: 'schooldb',
  charset: 'utf8mb4', timezone: 'Z', dateStrings: false,
});

(async () => {
  // Create new hash for 'admin123'
  const newHash = await bcrypt.hash('admin123', 10);
  console.log('New hash:', newHash);
  
  // Update admin password
  await pool.query('UPDATE users SET password_hash = ? WHERE username = ?', [newHash, 'admin']);
  console.log('Admin password updated to: admin123');
  
  // Verify
  const [rows] = await pool.query('SELECT password_hash FROM users WHERE username = ?', ['admin']);
  const ok = await bcrypt.compare('admin123', rows[0].password_hash);
  console.log('Verification:', ok);
  
  pool.end();
})();