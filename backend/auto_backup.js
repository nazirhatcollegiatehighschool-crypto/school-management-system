#!/usr/bin/env node
// auto_backup.js - Automatic Supabase backup system
const fs = require('fs').promises;
const path = require('path');
const { Pool } = require('pg');
const cron = require('node-cron');

class AutoBackup {
  constructor() {
    this.supabaseUrl = process.env.BACKUP_DATABASE_URL || process.env.DIRECT_URL || process.env.DATABASE_URL;
    if (!this.supabaseUrl) throw new Error('Set BACKUP_DATABASE_URL in the secure process environment.');
    this.backupBase = path.join(__dirname, 'database', 'backups');
    this.schemaBase = path.join(__dirname, 'database', 'schemas');
    this.changesLog = path.join(__dirname, 'database', 'changes.log');
    
    this.supabasePool = new Pool({
      connectionString: this.supabaseUrl,
      ssl: { rejectUnauthorized: false }
    });
  }

  async initialize() {
    // Create backup directories
    await Promise.all([
      fs.mkdir(this.backupBase, { recursive: true }),
      fs.mkdir(this.schemaBase, { recursive: true }),
      fs.mkdir(path.dirname(this.changesLog), { recursive: true })
    ]);
    
    console.log('📁 Backup system initialized');
    console.log(`   Backup location: ${this.backupBase}`);
    console.log(`   Schema location: ${this.schemaBase}`);
    console.log(`   Changes log: ${this.changesLog}`);
  }

  async backupSchema() {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const schemaPath = path.join(this.schemaBase, `schema_${timestamp}.sql`);
    
    // Get all table schemas
    const { rows: tables } = await this.supabasePool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      ORDER BY table_name
    `);

    let schemaSQL = `-- Supabase Schema Backup - ${new Date().toISOString()}\n\n`;
    
    for (const { table_name } of tables) {
      // Get table DDL
      const { rows: ddl } = await this.supabasePool.query(`
        SELECT 'CREATE TABLE IF NOT EXISTS "' || table_name || '" (' || 
               string_agg(
                 column_name || ' ' || data_type || 
                 CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END ||
                 CASE WHEN column_default IS NOT NULL THEN ' DEFAULT ' || column_default ELSE '' END,
                 ', '
               ) || ');' as create_stmt
        FROM information_schema.columns 
        WHERE table_name = $1 AND table_schema = 'public'
        GROUP BY table_name
      `, [table_name]);
      
      if (ddl.length > 0) {
        schemaSQL += ddl[0].create_stmt + '\n\n';
      }
    }
    
    await fs.writeFile(schemaPath, schemaSQL);
    console.log(`📋 Schema backed up: ${schemaPath}`);
    
    return schemaPath;
  }

  async backupTableData(tableName) {
    const today = new Date().toISOString().split('T')[0];
    const tableBackupDir = path.join(this.backupBase, today, tableName);
    await fs.mkdir(tableBackupDir, { recursive: true });
    
    try {
      // Get all data
      const { rows } = await this.supabasePool.query(`SELECT * FROM "${tableName}"`);
      
      if (rows.length === 0) {
        console.log(`   ⚠️  ${tableName}: No data`);
        return null;
      }
      
      // Save as JSON
      const jsonPath = path.join(tableBackupDir, `${tableName}.json`);
      await fs.writeFile(jsonPath, JSON.stringify(rows, null, 2));
      
      // Save as SQL
      const sqlPath = path.join(tableBackupDir, `${tableName}.sql`);
      const sql = this.generateSQLInsert(tableName, rows);
      await fs.writeFile(sqlPath, sql);
      
      console.log(`   📦 ${tableName}: ${rows.length} rows`);
      
      return { jsonPath, sqlPath, rowCount: rows.length };
      
    } catch (error) {
      console.error(`   ❌ ${tableName} backup failed:`, error.message);
      return null;
    }
  }

  generateSQLInsert(tableName, rows) {
    if (rows.length === 0) return `-- No data in ${tableName}\n`;
    
    const columns = Object.keys(rows[0]);
    const sql = rows.map(row => {
      const values = columns.map(col => {
        const val = row[col];
        if (val === null) return 'NULL';
        if (typeof val === 'string') return `'${val.replace(/'/g, "''")}'`;
        if (typeof val === 'object') return `'${JSON.stringify(val).replace(/'/g, "''")}'`;
        return val;
      });
      return `INSERT INTO "${tableName}" (${columns.map(c => `"${c}"`).join(', ')}) VALUES (${values.join(', ')});`;
    }).join('\n');
    
    return `-- ${tableName} data - ${rows.length} rows\n${sql}`;
  }

  async detectChanges(tableName, newData) {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = yesterday.toISOString().split('T')[0];
    
    const oldBackupPath = path.join(this.backupBase, yesterdayStr, tableName, `${tableName}.json`);
    
    try {
      const oldDataStr = await fs.readFile(oldBackupPath, 'utf8');
      const oldData = JSON.parse(oldDataStr);
      
      // Find primary key (assume 'id')
      const pk = 'id';
      
      const changes = {
        newRows: newData.filter(newRow => !oldData.some(oldRow => oldRow[pk] === newRow[pk])),
        deletedRows: oldData.filter(oldRow => !newData.some(newRow => newRow[pk] === oldRow[pk])),
        updatedRows: []
      };
      
      // Check for updates
      newData.forEach(newRow => {
        const oldRow = oldData.find(r => r[pk] === newRow[pk]);
        if (oldRow) {
          const changed = Object.keys(newRow).some(key => 
            JSON.stringify(newRow[key]) !== JSON.stringify(oldRow[key])
          );
          if (changed) {
            changes.updatedRows.push({ 
              id: newRow[pk], 
              changes: Object.keys(newRow).filter(key => 
                JSON.stringify(newRow[key]) !== JSON.stringify(oldRow[key])
              )
            });
          }
        }
      });
      
      if (changes.newRows.length > 0 || changes.deletedRows.length > 0 || changes.updatedRows.length > 0) {
        await this.logChanges(tableName, changes);
        return changes;
      }
      
    } catch (error) {
      // No previous backup or error reading
      console.log(`   ℹ️  No previous backup for ${tableName} comparison`);
    }
    
    return null;
  }

  async logChanges(tableName, changes) {
    const logEntry = {
      timestamp: new Date().toISOString(),
      table: tableName,
      changes
    };
    
    await fs.appendFile(
      this.changesLog,
      JSON.stringify(logEntry) + '\n'
    );
    
    console.log(`   📝 Changes detected in ${tableName}: +${changes.newRows.length} -${changes.deletedRows.length} ~${changes.updatedRows.length}`);
  }

  async runFullBackup() {
    console.log('🚀 Starting full Supabase backup...');
    
    await this.initialize();
    
    // Backup schema first
    await this.backupSchema();
    
    // Get all tables
    const { rows: tables } = await this.supabasePool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name NOT IN ('knex_migrations', 'knex_migrations_lock')
      ORDER BY table_name
    `);
    
    console.log(`📊 Backing up ${tables.length} tables...`);
    
    const backupResults = [];
    
    for (const { table_name } of tables) {
      const result = await this.backupTableData(table_name);
      if (result) {
        backupResults.push({ table: table_name, ...result });
      }
    }
    
    // Create summary
    const summaryPath = path.join(this.backupBase, 'summary.json');
    const summary = {
      timestamp: new Date().toISOString(),
      totalTables: backupResults.length,
      totalRows: backupResults.reduce((sum, r) => sum + (r.rowCount || 0), 0),
      tables: backupResults.map(r => ({
        table: r.table,
        rowCount: r.rowCount,
        jsonPath: r.jsonPath,
        sqlPath: r.sqlPath
      }))
    };
    
    await fs.writeFile(summaryPath, JSON.stringify(summary, null, 2));
    
    console.log('✅ Full backup completed!');
    console.log(`📄 Summary: ${summaryPath}`);
    
    return summary;
  }

  // Start scheduled backups
  startScheduledBackups() {
    // Backup every day at 2:00 AM
    cron.schedule('0 2 * * *', async () => {
      console.log('⏰ Scheduled backup starting...');
      try {
        await this.runFullBackup();
      } catch (error) {
        console.error('❌ Scheduled backup failed:', error);
      }
    });
    
    console.log('⏰ Scheduled backups enabled (daily at 2:00 AM)');
  }
}

// Command line interface
if (require.main === module) {
  const backup = new AutoBackup();
  
  const command = process.argv[2] || 'full';
  
  switch (command) {
    case 'schema':
      backup.initialize().then(() => backup.backupSchema()).then(() => process.exit(0));
      break;
    case 'run':
      backup.runFullBackup().then(() => process.exit(0));
      break;
    case 'schedule':
      backup.initialize().then(() => backup.startScheduledBackups());
      break;
    case 'full':
    default:
      backup.runFullBackup().then(() => process.exit(0));
      break;
  }
}

module.exports = AutoBackup;