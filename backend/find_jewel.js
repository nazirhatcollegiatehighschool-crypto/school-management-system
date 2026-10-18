const mysql = require('mysql2/promise');
const pool = mysql.createPool({ host: '127.0.0.1', port: 3306, user: 'root', password: '', database: 'schooldb', charset: 'utf8mb4' });

(async () => {
  const [rows] = await pool.query('SELECT id, username, name, role, phone FROM users WHERE name LIKE "%Liakat%" OR name LIKE "%Jewel%" OR username LIKE "%jewel%" OR username LIKE "%liakat%"');
  console.log('Liakat/Jewel users:', JSON.stringify(rows, null, 2));
  pool.end();
})();