const { spawn, spawnSync } = require('child_process');
const path = require('path');
const dotenv = require('dotenv');

const backendDir = path.join(__dirname, '..');
dotenv.config({ path: path.join(backendDir, '.env.localdb'), override: true });
const syncScript = path.join(__dirname, 'cloud-to-local-sync.cjs');

function runSync() {
  const result = spawnSync(process.execPath, [syncScript], {
    cwd: backendDir,
    stdio: 'inherit',
    env: process.env,
  });
  return result.status === 0;
}

runSync();

const server = spawn(process.execPath, ['server.js'], {
  cwd: backendDir,
  stdio: 'inherit',
  env: process.env,
});

const timer = setInterval(() => runSync(), 15 * 60 * 1000);

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    clearInterval(timer);
    server.kill(signal);
  });
}

server.on('exit', (code) => process.exit(code ?? 0));
