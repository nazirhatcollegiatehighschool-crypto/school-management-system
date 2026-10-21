require('dotenv').config({ quiet: true });
const { Pool } = require('pg');
const p = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 15000 });

(async () => {
  const client = await p.connect();
  try {
    await client.query('BEGIN');

    // 1. Promotion rules per class/exam_type
    await client.query(`
      CREATE TABLE IF NOT EXISTS promotion_rules (
        id SERIAL PRIMARY KEY,
        class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
        exam_type VARCHAR(20) NOT NULL, -- 'annual', 'test', 'pretest', 'model_test'
        is_promotion_source BOOLEAN DEFAULT false,
        weight_annual NUMERIC(3,2) DEFAULT 1.0,
        weight_test NUMERIC(3,2) DEFAULT 1.0,
        min_passing_gpa NUMERIC(3,2) DEFAULT 2.0,
        allow_conditional BOOLEAN DEFAULT true,
        grace_failed_subjects INTEGER DEFAULT 0,
        mandatory_subjects TEXT[] DEFAULT '{}',
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE(class_id, exam_type)
      )`);
    console.log('promotion_rules table ready');

    // 2. Student promotion status tracking
    await client.query(`
      CREATE TABLE IF NOT EXISTS student_promotion_status (
        id SERIAL PRIMARY KEY,
        student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
        from_class_id INTEGER NOT NULL REFERENCES classes(id),
        target_class_id INTEGER REFERENCES classes(id),
        target_session_id INTEGER REFERENCES sessions(id),
        source_event_id INTEGER REFERENCES exam_events(id),
        status VARCHAR(30) DEFAULT 'pending_results', -- pending_results, eligible, not_eligible, conditional, pending_review, approved, retained, admin_override
        decision VARCHAR(30), -- promoted, retained, conditional, admin_override
        final_gpa NUMERIC(4,2),
        failed_subjects TEXT[] DEFAULT '{}',
        mandatory_failed_subjects TEXT[] DEFAULT '{}',
        grace_used INTEGER DEFAULT 0,
        admin_note TEXT,
        reviewed_by INTEGER REFERENCES users(id),
        reviewed_at TIMESTAMPTZ,
        approved_by INTEGER REFERENCES users(id),
        approved_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE(student_id, target_session_id)
      )`);
    console.log('student_promotion_status table ready');

    // 3. Promotion audit log
    await client.query(`
      CREATE TABLE IF NOT EXISTS promotion_audit_log (
        id SERIAL PRIMARY KEY,
        student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
        action VARCHAR(50) NOT NULL, -- 'eligible_calculated', 'reviewed', 'approved', 'retained', 'admin_override', 'bulk_approved', 'retention_overridden'
        from_status VARCHAR(30),
        to_status VARCHAR(30),
        from_class_id INTEGER REFERENCES classes(id),
        to_class_id INTEGER REFERENCES classes(id),
        target_session_id INTEGER REFERENCES sessions(id),
        admin_id INTEGER REFERENCES users(id),
        reason TEXT,
        metadata JSONB,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )`);
    console.log('promotion_audit_log table ready');

    // 4. Create indexes for performance
    await client.query(`CREATE INDEX IF NOT EXISTS idx_promotion_rules_class ON promotion_rules(class_id);`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_student_promo_status_student ON student_promotion_status(student_id);`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_student_promo_status_session ON student_promotion_status(target_session_id);`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_student_promo_status_class ON student_promotion_status(from_class_id);`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_promotion_audit_student ON promotion_audit_log(student_id);`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_promotion_audit_session ON promotion_audit_log(target_session_id);`);
    console.log('Indexes created');

    // 5. Backfill promotion_rules for existing classes with defaults
    const classes = await client.query('SELECT id, name FROM classes');
    for (const c of classes.rows) {
      const isClass10 = /class\s*10/i.test(String(c.name));
      const isClass9 = /class\s*9/i.test(String(c.name));
      const isClass6to8 = /class\s*[6-8]\b/i.test(String(c.name));

      if (isClass10) {
        await client.query(`
          INSERT INTO promotion_rules (class_id, exam_type, is_promotion_source, weight_test, min_passing_gpa, allow_conditional, grace_failed_subjects, mandatory_subjects)
          VALUES ($1, 'test', true, 1.0, 2.0, true, 0, '{}')
          ON CONFLICT (class_id, exam_type) DO NOTHING
        `, [c.id]);
        await client.query(`
          INSERT INTO promotion_rules (class_id, exam_type, is_promotion_source, weight_annual, min_passing_gpa, allow_conditional, grace_failed_subjects, mandatory_subjects)
          VALUES ($1, 'annual', false, 1.0, 2.0, true, 0, '{}')
          ON CONFLICT (class_id, exam_type) DO NOTHING
        `, [c.id]);
      } else if (isClass9) {
        await client.query(`
          INSERT INTO promotion_rules (class_id, exam_type, is_promotion_source, weight_annual, min_passing_gpa, allow_conditional, grace_failed_subjects, mandatory_subjects)
          VALUES ($1, 'annual', true, 1.0, 2.0, true, 0, '{}')
          ON CONFLICT (class_id, exam_type) DO NOTHING
        `, [c.id]);
        await client.query(`
          INSERT INTO promotion_rules (class_id, exam_type, is_promotion_source, weight_test, min_passing_gpa, allow_conditional, grace_failed_subjects, mandatory_subjects)
          VALUES ($1, 'test', false, 1.0, 2.0, true, 0, '{}')
          ON CONFLICT (class_id, exam_type) DO NOTHING
        `, [c.id]);
      } else if (isClass6to8) {
        await client.query(`
          INSERT INTO promotion_rules (class_id, exam_type, is_promotion_source, weight_annual, min_passing_gpa, allow_conditional, grace_failed_subjects, mandatory_subjects)
          VALUES ($1, 'annual', true, 1.0, 2.0, true, 0, '{}')
          ON CONFLICT (class_id, exam_type) DO NOTHING
        `, [c.id]);
        await client.query(`
          INSERT INTO promotion_rules (class_id, exam_type, is_promotion_source, weight_test, min_passing_gpa, allow_conditional, grace_failed_subjects, mandatory_subjects)
          VALUES ($1, 'test', false, 1.0, 2.0, true, 0, '{}')
          ON CONFLICT (class_id, exam_type) DO NOTHING
        `, [c.id]);
      }
    }
    console.log('Promotion rules backfilled for', classes.rows.length, 'classes');

    // 6. Sync promotion_grace with promotion_rules
    await client.query(`
      INSERT INTO promotion_grace (class_id, exam_type, grace_failed, notes)
      SELECT class_id, exam_type, grace_failed_subjects, 'synced from promotion_rules'
      FROM promotion_rules
      ON CONFLICT (class_id, exam_type) DO UPDATE SET grace_failed = EXCLUDED.grace_failed, notes = EXCLUDED.notes
    `);
    console.log('promotion_grace synced with promotion_rules');

    await client.query('COMMIT');
    console.log('Migration completed successfully');
    process.exit(0);
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('FAIL:', e.message);
    process.exit(1);
  } finally {
    client.release();
    p.end();
  }
})();