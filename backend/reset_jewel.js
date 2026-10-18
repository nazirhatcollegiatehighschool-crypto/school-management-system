const mysql = require('mysql2/promise');
const bcrypt = require('bcrypt');
const pool = mysql.createPool({ host: '127.0.0.1', port: 3306, user: 'root', password: '', database: 'schooldb', charset: 'utf8mb4' });

(async () => {
  const [rows] = await pool.query('SELECT id, username, name, role, password_hash FROM users WHERE id = 11');
  console.log('User:', JSON.stringify(rows[0], null, 2));
  
  const ok = await bcrypt.compare('admin123', rows[0].password_hash);
  console.log('Password "admin123" matches:', ok);
  
  // Reset password to admin123
  const hash = await bcrypt.hash('admin123', 10);
  await pool.query('UPDATE users SET password_hash = ? WHERE id = 11', [hash]);
  console.log('Password reset to admin123');
  
  const ok2 = await bcrypt.compare('admin123', hash);
  console.log('Verification:', ok2);
  
  pool.end();
})();