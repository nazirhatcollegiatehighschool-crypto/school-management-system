const bcrypt = require('bcrypt');

(async () => {
  const password = 'admin123';
  const hash = '$2b$10$PpajhtXUESOGK3QGry.3A.yLGHxHAAqUTNCt6UGrPKEBKBt6kj6va';
  
  const ok = await bcrypt.compare(password, hash);
  console.log('Password match:', ok);
  
  // Test wrong password
  const ok2 = await bcrypt.compare('wrong', hash);
  console.log('Wrong password match:', ok2);
})();