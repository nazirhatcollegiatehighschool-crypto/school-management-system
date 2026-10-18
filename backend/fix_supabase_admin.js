const { Pool } = require('pg');

const pool = new Pool({
  connectionString: 'postgresql://postgres:Jewel@114070Jewel@114070@db.gqonldfvammlizljmtdk.supabase.co:5432/postgres',
  ssl: { rejectUnauthorized: false }
});

(async () => {
  const { rows } = await pool.query('SELECT id, username, role, password_hash FROM users WHERE role = \'admin\'');
  console.log('Admin users:', JSON.stringify(rows, null, 2));
  
  const bcrypt = require('bcrypt');
  const hash = await bcrypt.hash('admin123', 10);
  console.log('New hash:', hash);
  
  await pool.query('UPDATE users SET password_hash = $1 WHERE username = $2', [hash, 'admin']);
  console.log('Password updated in Supabase');
  
  const { rows: updated } = await pool.query('SELECT password_hash FROM users WHERE username = \'admin\'');
  const ok = await bcrypt.compare('admin123', updated[0].password_hash);
  console.log('Verification:', ok);
  
  await pool.end();
})();