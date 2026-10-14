# School Management System - Auto Backup Configuration

## Database Backup System

### Location: `backend/database/`

```
database/
├── backups/          # Daily backup snapshots
│   ├── 2026-10-14/   # Date folder
│   │   ├── users.json
│   │   ├── users.sql
│   │   ├── students.json
│   │   ├── students.sql
│   │   └── summary.json
│   └── 2026-10-15/
├── schemas/          # Database schema backups
│   ├── schema_2026-10-14T18-33-15.sql
│   └── schema_latest.sql
└── changes.log       # Change tracking log
```

## API Endpoints

### 1. Sync Schema to Supabase
```bash
GET /api/admin/sync/schema
```
Detects new columns in MySQL and adds them to Supabase tables.

### 2. Backup Supabase Data
```bash
GET /api/admin/sync/backup
```
Creates a complete backup of all Supabase tables locally.

### 3. Full Sync (Schema + Data)
```bash
GET /api/admin/sync/full
```
Runs complete sync: schema sync + data sync + backup.

## Usage Examples

### Manual Sync
```bash
# Sync new schema fields
curl http://localhost:5000/api/admin/sync/schema

# Backup Supabase data
curl http://localhost:5000/api/admin/sync/backup

# Full sync
curl http://localhost:5000/api/admin/sync/full
```

### Using Node
```bash
# Full backup
node backend/auto_backup.js full

# Run backups on schedule (daily at 2:00 AM)
node backend/auto_backup.js schedule

# Manual backup
node backend/auto_backup.js run
```

### Using SupabaseSync Class
```javascript
const SupabaseSync = require('./supabase_sync');
const sync = new SupabaseSync();

async function syncEverything() {
  await sync.initialize();
  
  // Sync schemas
  await sync.syncSchemas();
  
  // Backup data
  const backupPath = await sync.backupSupabaseData();
  console.log('Backup created at:', backupPath);
  
  // Sync data between MySQL and Supabase
  await sync.syncData();
  
  await sync.cleanup();
}
```

## What Gets Backed Up

### Schema Backups (`database/schemas/`)
- Complete PostgreSQL table definitions
- Column names, types, constraints
- Auto-backup on every sync run

### Data Backups (`database/backups/`)
- All table data saved as JSON
- SQL insert statements for easy restoration
- Daily folders with `summary.json`

### Change Tracking
- `changes.log` records:
  - New rows added
  - Rows deleted
  - Fields updated
  - Timestamps and user info

## Adding New Fields

### From MySQL to Supabase
```sql
-- 1. Add column to MySQL
ALTER TABLE students ADD COLUMN address_line2 VARCHAR(255);

-- 2. Sync to Supabase (auto-detects new columns)
GET /api/admin/sync/schema
```

### Manual Field Addition
1. Update MySQL schema: `ALTER TABLE table_name ADD COLUMN new_field VARCHAR(255);`
2. Run schema sync: `GET /api/admin/sync/schema`
3. New field automatically added to Supabase with matching type
4. Existing data preserved
5. Backup created automatically

## Scheduled Backups

The `auto_backup.js` script runs daily at 2:00 AM:

```bash
# To start scheduled backups
node backend/auto_backup.js schedule

# Or use cron directly
0 2 * * * cd /path/to/school-system && node backend/auto_backup.js run >> logs/backup.log 2>&1
```

## Restoring Data

### Restore from SQL Backup
```sql
-- In Supabase SQL Editor
-- Load the SQL file
SOURCE /path/to/database/backups/2026-10-14/users.sql;
```

### Restore from JSON (Node)
```javascript
const fs = require('fs');
const { Pool } = require('pg');

const pool = new Pool({ connectionString: process.env.SUPABASE_URL });

async function restoreTable(tableName) {
  const data = JSON.parse(
    fs.readFileSync(`database/backups/2026-10-14/${tableName}.json`)
  );
  
  for (const row of data) {
    await pool.query(
      `INSERT INTO "${tableName}" (${Object.keys(row).join(', ')}) 
       VALUES (${Object.values(row).map(() => '?').join(', ')})`,
      Object.values(row)
    );
  }
}
```

## Troubleshooting

### Connection Issues
```bash
# Test Supabase connection
node -e "const {Pool}=require('pg');new Pool({connectionString:'postgresql://...'}).query('SELECT 1').then(()=>console.log('OK')).catch(e=>console.error(e))"
```

### Permission Errors
Ensure the PostgreSQL user has:
- CREATE TABLE permissions
- INSERT/UPDATE/DELETE permissions on all tables
- SELECT permissions on information_schema

### Large Data Backup
For tables with 10k+ rows, use the batch sync method in `supabase_sync.js`.

## Integration with Render

The sync endpoints are protected (admin-only). To enable from Render:

1. **Add admin authentication** before calling endpoints
2. **Use Render environment variables** for Supabase credentials
3. **Set up cron job** on Render for automatic daily backups

Example Render cron (add to `.render.yaml`):
```yaml
services:
  - type: web
    name: school-backend
    env: node
    buildCommand: cd backend && npm install
    startCommand: node server.js
    envVars:
      - key: SUPABASE_URL
        sync: false
    cronJobs:
      - name: daily-backup
        schedule: "0 2 * * *"
        runCommand: cd backend && node auto_backup.js run
```

## Notes

- All backups are date-stamped for rollback
- Changes are logged for audit trail
- MySQL ↔ Supabase sync is one-way (MySQL → Supabase) by default
- Schema changes are automatically detected and applied
- No data loss during sync operations