'use strict';

const path = require('path');
const { spawnSync } = require('child_process');
const dotenv = require('dotenv');

const envFile = process.argv[2];
if (!envFile) throw new Error('Environment file is required.');
const resolved = path.resolve(process.cwd(), envFile);
const loaded = dotenv.config({ path: resolved, override: true });
if (loaded.error) throw loaded.error;
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is missing from the selected environment.');

const script = process.argv[3] || '20261030_profile_attendance_workflows.sql';
const result = spawnSync(
  process.execPath,
  [path.resolve(process.cwd(), '../scripts/apply_additive_migration.cjs'), script],
  { stdio: 'inherit', env: process.env }
);
process.exit(result.status == null ? 1 : result.status);
