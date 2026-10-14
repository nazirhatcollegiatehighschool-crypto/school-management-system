// Zero-dependency JS syntax gate for the backend (no eslint configured).
// Usage: node lint.js [dir]  (default: this file's directory, recursive routes)
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = process.argv[2] ? path.resolve(process.argv[2]) : __dirname;
const files = [];
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (['routes', 'api', 'middleware', 'lib'].includes(e.name) || dir === root) walk(p); }
    else if (e.name.endsWith('.js')) files.push(p);
  }
})(root);

let fail = 0;
for (const f of files) {
  try {
    execFileSync(process.execPath, ['--check', f], { stdio: 'pipe' });
  } catch (e) {
    fail++;
    console.error('SYNTAX FAIL:', path.relative(root, f));
    console.error(String(e.stderr || e.message).split('\n').slice(0, 4).join('\n'));
  }
}
console.log(fail === 0 ? `lint OK (${files.length} files)` : `lint FAILED (${fail}/${files.length})`);
process.exit(fail ? 1 : 0);
