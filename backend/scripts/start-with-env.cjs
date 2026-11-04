'use strict';

const path = require('path');
const { spawn } = require('child_process');
const dotenv = require('dotenv');

const envFile = process.argv[2];
if (!envFile) throw new Error('Environment file is required.');
const resolved = path.resolve(process.cwd(), envFile);
const loaded = dotenv.config({ path: resolved, override: true });
if (loaded.error) throw loaded.error;
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is missing from the selected environment.');

const mysql = /^mysql:\/\//i.test(process.env.DATABASE_URL);
console.log(`Starting backend with ${mysql ? 'local MariaDB/MySQL' : 'Supabase PostgreSQL'}.`);
const child = spawn(process.execPath, [path.resolve(process.cwd(), 'server.js')], {
  stdio: 'inherit',
  env: process.env,
});
child.on('exit', (code) => process.exit(code == null ? 1 : code));
