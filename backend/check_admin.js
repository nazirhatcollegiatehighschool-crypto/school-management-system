const mysql = require('mysql2/promise');
const pool = mysql.createPool({
  host: '127.0.0.1', port: 3306, user: 'root', password: '', database: 'schooldb',
  charset: 'utf8mb4', timezone: 'Z', dateStrings: false,
});

(async () => {
  const [rows] = await pool.query('SELECT id, username, role, password_hash FROM users WHERE role="admin"');
  console.log('Admin users:', JSON.stringify(rows, null, 2));
  pool.end();
})();