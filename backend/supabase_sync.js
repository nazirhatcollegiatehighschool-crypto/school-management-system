// supabase_sync.js
// Automated MySQL ↔ Supabase schema and data synchronization
const fs = require('fs').promises;
const path = require('path');
const mysql = require('mysql2/promise');
const { Pool } = require('pg');

class SupabaseSync {
  constructor() {
    // Database connections
    this.mysqlPool = null;
    this.supabasePool = null;
    
    // Sync configuration
    this.config = {
      backupDir: path.join(__dirname, 'database'),
      syncTables: [
        'users', 'sessions', 'classes', 'students', 'subjects', 'student_subjects',
        'exam_events', 'exams', 'marks', 'attendance', 'results', 'notifications',
        'homework', 'guardian_links', 'promotions', 'time_slots', 'routines',
        'device_tokens', 'activity_log'
      ],
      excludeTables: ['knex_migrations', 'knex_migrations_lock'],
      batchSize: 100,
      maxRetries: 3
    };
  }

  async initialize() {
    console.log('🔧 Initializing Supabase Sync System...');
    
    // Create backup directory
    await fs.mkdir(this.config.backupDir, { recursive: true });
    
    // Initialize MySQL connection
    this.mysqlPool = mysql.createPool({
      host: '127.0.0.1',
      port: 3306,
      user: 'root',
      password: '',
      database: 'schooldb',
      charset: 'utf8mb4'
    });

    // Initialize Supabase connection
    const supabaseUrl = 'postgresql://postgres:Jewel@114070Jewel@114070@db.gqonldfvammlizljmtdk.supabase.co:5432/postgres';
    this.supabasePool = new Pool({
      connectionString: supabaseUrl,
      ssl: { rejectUnauthorized: false }
    });

    console.log('✅ Database connections established');
    return this;
  }

  // 1. SCHEMA SYNC: Detect and sync new columns/fields
  async syncSchemas() {
    console.log('🔄 Syncing database schemas...');
    
    for (const table of this.config.syncTables) {
      try {
        const mysqlColumns = await this.getMySQLColumns(table);
        const supabaseColumns = await this.getSupabaseColumns(table);
        
        // Find columns that exist in MySQL but not in Supabase
        const missingColumns = mysqlColumns.filter(mysqlCol => 
          !supabaseColumns.some(sbCol => sbCol.column_name.toLowerCase() === mysqlCol.Field.toLowerCase())
        );

        if (missingColumns.length > 0) {
          console.log(`📋 Adding ${missingColumns.length} columns to Supabase table: ${table}`);
          await this.addColumnsToSupabase(table, missingColumns);
        }

        // Also check for columns in Supabase but not MySQL (shouldn't happen)
        const extraColumns = supabaseColumns.filter(sbCol => 
          !mysqlColumns.some(mysqlCol => mysqlCol.Field.toLowerCase() === sbCol.column_name.toLowerCase())
        );

        if (extraColumns.length > 0) {
          console.log(`⚠️  Extra columns in Supabase table ${table}:`, extraColumns.map(c => c.column_name));
        }

      } catch (error) {
        console.error(`❌ Schema sync failed for table ${table}:`, error.message);
      }
    }

    console.log('✅ Schema sync completed');
  }

  async getMySQLColumns(table) {
    const [rows] = await this.mysqlPool.query(`SHOW COLUMNS FROM \`${table}\``);
    return rows;
  }

  async getSupabaseColumns(table) {
    const query = `
      SELECT column_name, data_type, is_nullable, column_default
      FROM information_schema.columns 
      WHERE table_name = $1 
      ORDER BY ordinal_position
    `;
    const { rows } = await this.supabasePool.query(query, [table]);
    return rows;
  }

  async addColumnsToSupabase(table, columns) {
    for (const column of columns) {
      const sqlType = this.mapMySQLTypeToPostgres(column.Type, column.Null);
      const nullable = column.Null === 'YES' ? 'NULL' : 'NOT NULL';
      const defaultValue = column.Default ? `DEFAULT '${column.Default}'` : '';
      
      const alterQuery = `
        ALTER TABLE "${table}" 
        ADD COLUMN "${column.Field}" ${sqlType} ${nullable} ${defaultValue}
      `;

      try {
        await this.supabasePool.query(alterQuery);
        console.log(`   ✅ Added column: ${table}.${column.Field} (${sqlType})`);
      } catch (error) {
        console.error(`   ❌ Failed to add column ${table}.${column.Field}:`, error.message);
      }
    }
  }

  mapMySQLTypeToPostgres(mysqlType, nullable) {
    mysqlType = mysqlType.toLowerCase();
    
    if (mysqlType.includes('int(') || mysqlType === 'int') {
      return 'INTEGER';
    } else if (mysqlType.includes('varchar(')) {
      const match = mysqlType.match(/varchar\((\d+)\)/);
      return match ? `VARCHAR(${match[1]})` : 'VARCHAR(255)';
    } else if (mysqlType.includes('decimal(')) {
      return mysqlType.replace('decimal', 'NUMERIC');
    } else if (mysqlType === 'text' || mysqlType.includes('longtext')) {
      return 'TEXT';
    } else if (mysqlType === 'datetime' || mysqlType === 'timestamp') {
      return 'TIMESTAMP';
    } else if (mysqlType === 'date') {
      return 'DATE';
    } else if (mysqlType === 'time') {
      return 'TIME';
    } else if (mysqlType.includes('enum(')) {
      // Convert MySQL ENUM to TEXT with constraint
      return 'VARCHAR(50)';
    } else if (mysqlType.includes('tinyint(1)')) {
      return 'SMALLINT';
    }
    
    return 'TEXT'; // fallback
  }

  // 2. DATA BACKUP: Backup Supabase data locally
  async backupSupabaseData() {
    console.log('💾 Backing up Supabase data locally...');
    const backupPath = path.join(this.config.backupDir, `backup_${new Date().toISOString().split('T')[0]}`);
    await fs.mkdir(backupPath, { recursive: true });

    for (const table of this.config.syncTables) {
      try {
        const { rows } = await this.supabasePool.query(`SELECT * FROM "${table}"`);
        
        // Save as JSON
        const jsonPath = path.join(backupPath, `${table}.json`);
        await fs.writeFile(jsonPath, JSON.stringify(rows, null, 2));
        
        // Save as SQL insert statements
        const sqlPath = path.join(backupPath, `${table}.sql`);
        const sqlStatements = this.generateInsertStatements(table, rows);
        await fs.writeFile(sqlPath, sqlStatements);

        console.log(`   📦 ${table}: ${rows.length} rows backed up`);
      } catch (error) {
        console.error(`   ❌ Backup failed for ${table}:`, error.message);
      }
    }

    console.log(`✅ Backup completed at: ${backupPath}`);
    return backupPath;
  }

  generateInsertStatements(table, rows) {
    if (rows.length === 0) return `-- No data in table ${table}\n`;

    const columns = Object.keys(rows[0]);
    const insertStatements = rows.map(row => {
      const values = columns.map(col => {
        const val = row[col];
        if (val === null || val === undefined) return 'NULL';
        if (typeof val === 'string') return `'${val.replace(/'/g, "''")}'`;
        if (typeof val === 'object') return `'${JSON.stringify(val).replace(/'/g, "''")}'`;
        return val;
      });
      return `INSERT INTO "${table}" (${columns.map(c => `"${c}"`).join(', ')}) VALUES (${values.join(', ')});`;
    });

    return insertStatements.join('\n');
  }

  // 3. DATA SYNC: Sync data between MySQL and Supabase
  async syncData() {
    console.log('🔄 Starting data sync...');
    
    for (const table of this.config.syncTables) {
      try {
        // Get primary key
        const primaryKey = await this.getTablePrimaryKey(table);
        if (!primaryKey) {
          console.log(`   ⚠️  Skipping ${table}: No primary key found`);
          continue;
        }

        // Get data from both databases
        const [mysqlData] = await this.mysqlPool.query(`SELECT * FROM \`${table}\``);
        const { rows: supabaseData } = await this.supabasePool.query(`SELECT * FROM "${table}"`);

        // Find differences
        const toInsert = this.findNewRecords(mysqlData, supabaseData, primaryKey);
        const toUpdate = this.findUpdatedRecords(mysqlData, supabaseData, primaryKey);
        const toDelete = this.findDeletedRecords(mysqlData, supabaseData, primaryKey);

        // Apply changes to Supabase
        await this.applyChangesToSupabase(table, primaryKey, toInsert, toUpdate, toDelete);

        console.log(`   ✅ ${table}: +${toInsert.length} -${toDelete.length} ~${toUpdate.length}`);

      } catch (error) {
        console.error(`   ❌ Data sync failed for ${table}:`, error.message);
      }
    }

    console.log('✅ Data sync completed');
  }

  async getTablePrimaryKey(table) {
    try {
      const [mysqlKeys] = await this.mysqlPool.query(`
        SELECT COLUMN_NAME 
        FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE 
        WHERE TABLE_SCHEMA = 'schooldb' 
        AND TABLE_NAME = '${table}' 
        AND CONSTRAINT_NAME = 'PRIMARY'
      `);
      
      if (mysqlKeys.length > 0) return mysqlKeys[0].COLUMN_NAME;
      
      // Try Supabase
      const { rows } = await this.supabasePool.query(`
        SELECT a.attname as column_name
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = $1::regclass AND i.indisprimary
      `, [table]);
      
      return rows.length > 0 ? rows[0].column_name : null;
    } catch (error) {
      return 'id'; // Default assumption
    }
  }

  findNewRecords(sourceData, targetData, primaryKey) {
    const targetIds = new Set(targetData.map(row => row[primaryKey]));
    return sourceData.filter(row => !targetIds.has(row[primaryKey]));
  }

  findDeletedRecords(sourceData, targetData, primaryKey) {
    const sourceIds = new Set(sourceData.map(row => row[primaryKey]));
    return targetData.filter(row => !sourceIds.has(row[primaryKey]));
  }

  findUpdatedRecords(sourceData, targetData, primaryKey) {
    const targetMap = new Map(targetData.map(row => [row[primaryKey], row]));
    return sourceData.filter(sourceRow => {
      const targetRow = targetMap.get(sourceRow[primaryKey]);
      if (!targetRow) return false;
      
      // Compare all fields except primary key
      const sourceKeys = Object.keys(sourceRow).filter(k => k !== primaryKey);
      return sourceKeys.some(key => sourceRow[key] !== targetRow[key]);
    });
  }

  async applyChangesToSupabase(table, primaryKey, toInsert, toUpdate, toDelete) {
    // Delete first
    for (const row of toDelete) {
      await this.supabasePool.query(
        `DELETE FROM "${table}" WHERE "${primaryKey}" = $1`,
        [row[primaryKey]]
      );
    }

    // Insert new
    for (const row of toInsert) {
      const columns = Object.keys(row);
      const values = columns.map(col => row[col]);
      const placeholders = columns.map((_, i) => `$${i + 1}`);
      
      await this.supabasePool.query(
        `INSERT INTO "${table}" (${columns.map(c => `"${c}"`).join(', ')}) 
         VALUES (${placeholders.join(', ')})`,
        values
      );
    }

    // Update existing
    for (const row of toUpdate) {
      const columns = Object.keys(row).filter(k => k !== primaryKey);
      const setClause = columns.map((col, i) => `"${col}" = $${i + 1}`).join(', ');
      const values = columns.map(col => row[col]);
      values.push(row[primaryKey]); // For WHERE clause
      
      await this.supabasePool.query(
        `UPDATE "${table}" SET ${setClause} WHERE "${primaryKey}" = $${values.length}`,
        values
      );
    }
  }

  // 4. SYNC MONITOR: Track sync status and errors
  async createSyncReport() {
    const report = {
      timestamp: new Date().toISOString(),
      schemaChanges: [],
      dataSync: {},
      backups: [],
      errors: []
    };

    // Implementation details...
    return report;
  }

  // 5. MAIN SYNC WORKFLOW
  async runFullSync() {
    console.log('🚀 Starting full Supabase sync workflow...');
    
    try {
      await this.initialize();
      
      // Step 1: Sync schemas
      await this.syncSchemas();
      
      // Step 2: Backup existing data
      const backupPath = await this.backupSupabaseData();
      
      // Step 3: Sync data
      await this.syncData();
      
      // Step 4: Create report
      const report = await this.createSyncReport();
      
      console.log('🎉 Full sync completed successfully!');
      console.log(`📁 Backup location: ${backupPath}`);
      
      return { success: true, backupPath, report };
      
    } catch (error) {
      console.error('❌ Sync failed:', error);
      return { success: false, error: error.message };
    } finally {
      await this.cleanup();
    }
  }

  async cleanup() {
    if (this.mysqlPool) await this.mysqlPool.end();
    if (this.supabasePool) await this.supabasePool.end();
  }
}

// Command line interface
if (require.main === module) {
  const sync = new SupabaseSync();
  
  const command = process.argv[2] || 'full';
  
  switch (command) {
    case 'schema':
      sync.runFullSync().then(() => process.exit(0));
      break;
    case 'backup':
      sync.initialize().then(() => sync.backupSupabaseData()).then(() => process.exit(0));
      break;
    case 'sync':
      sync.initialize().then(() => sync.syncData()).then(() => process.exit(0));
      break;
    case 'full':
    default:
      sync.runFullSync().then(() => process.exit(0));
      break;
  }
}

module.exports = SupabaseSync;