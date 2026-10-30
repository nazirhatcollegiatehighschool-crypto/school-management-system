# Backup ও Restore নির্দেশিকা (বাংলা)

এই নথিটি school-system-এর দুই ধরনের backup যাচাই ও restore করার জন্য। **Production database-এ restore করবেন না**; সব restore test isolated/temporary database-এ করুন। Backup-এ student, guardian ও staff-এর ব্যক্তিগত তথ্য থাকে—ফাইল, hash বা log কোথাও share করবেন না।

## ১. Backup artifact চেনা

### Supabase (PostgreSQL) encrypted backup

অবস্থান: `runtime/secure_backups/`

প্রতিটি backup-এর তিনটি ফাইল থাকে:

| ফাইল | কাজ |
|---|---|
| `supabase-live-<timestamp>.dump.sbk` | AES-256-GCM encrypted PostgreSQL custom dump |
| `supabase-live-<timestamp>.key.dpapi` | backup key, Windows DPAPI `CurrentUser` দিয়ে সুরক্ষিত |
| `supabase-live-<timestamp>.manifest.json` | SHA-256, size, table-data entry count, project ref |

সর্বশেষ যাচাইকৃত artifact (2026-10-30):

- `supabase-live-2026-10-30T06-57-39-378Z.dump.sbk`
- encrypted SHA-256: `7A04A041423EC8CA4DC766F2835AC6DFAC8C70868AF0550722A0CE3C4A1F40DB`
- bytes: 550,080
- table-data entries: 100 (62 public table-এর মধ্যে নতুন 4টি empty table সহ)
- manifest: `decrypted_archive_listed: true`

আগের যাচাইকৃত artifact (migration-এর আগে, 58 public table):

- `supabase-live-2026-10-30T05-59-01-635Z.dump.sbk`
- SHA-256: `38716BFF99AF223212970BD401AB8E04E043F505399D6096749CA4333BA3580B`
- table-data entries: 96

### Local MariaDB backup

অবস্থান: `database_backups/`

প্রতিটি backup-এর সঙ্গে `.sha256` ও `.manifest.json` থাকে। সর্বশেষ:

- `school_system_local_mariadb_20261030_125531.sql.gz`
- SHA-256: `E69774BA8AC21467AC153D363A93C9629FBFA97B3A90E6988E388A357F43C051`
- compressed bytes: 427,479
- decompressed bytes: 2,024,236
- 132টি `CREATE TABLE` statement (system table সহ), 65টি `INSERT`, সম্পূর্ণ decompress করে completion marker যাচাই করা

আগের artifact (38-table পুরোনো snapshot, restore test করা হয়েছে):

- `school_system_local_mariadb_20261030_013048.sql.gz`
- SHA-256: `7061D5C9E70CC76C16CE88903C0449DDAEA2E51EEFB6612DDDD25BCF8CFE89F0`

`school_system_mariadb_datadir_20261030_012907.zip` হলো live data-directory-র copy; এটিকে verified restore backup হিসেবে ব্যবহার করবেন না।

## ২. Encrypted Supabase backup verify

Project root থেকে:

```bat
node scripts\restore_supabase_secure.cjs --verify
```

নির্দিষ্ট archive:

```bat
node scripts\restore_supabase_secure.cjs --verify --archive "runtime\secure_backups\supabase-live-2026-10-30T06-57-39-378Z.dump.sbk"
```

এটি DPAPI key খুলে archive decrypt করে, SHA-256 মিলিয়ে `pg_restore --list` চালায় এবং manifest-এর table-data entry count-এর সঙ্গে মেলায়। Secret value কোথাও print হয় না।

শুধু decrypted dump দরকার হলে (সাধারণত দরকার নেই):

```bat
node scripts\restore_supabase_secure.cjs --decrypt-to "runtime\secure_backups\manual-restore.dump" --archive "..."
```

Decrypted dump-এ ব্যক্তিগত তথ্য থাকে; কাজ শেষে অবশ্যই delete করুন। Tool শুধু `runtime/secure_backups/`-এর ভিতরে লিখতে দেয়।

## ৩. Supabase backup restore (isolated database-এ)

### ৩.১ একটি isolated PostgreSQL database তৈরি করুন

Production project-এর database নয়—আলাদা temporary/staging project বা local temporary PostgreSQL cluster ব্যবহার করুন। Target database-এর নাম `restore_`, `staging_` বা `test_` দিয়ে শুরু হতে হবে।

```text
CREATE DATABASE restore_test_20261030;
```

### ৩.২ Restore চালান

```bat
node scripts\restore_supabase_secure.cjs --restore "postgresql://USER:PASSWORD@HOST:PORT/restore_test_20261030" --confirm-target restore_test_20261030 --archive "runtime\secure_backups\supabase-live-2026-10-30T06-57-39-378Z.dump.sbk"
```

Tool নিজে থেকে refuse করবে যদি:

- target live `DATABASE_URL`-এর database-ই হয়;
- `--confirm-target` না মেলে;
- database-এর নাম `restore_`/`staging_`/`test_` দিয়ে শুরু না হয় (জানিয়ে `--allow-non-test-target` না দিলে)।

Restore শেষে tool শুধু target database name ও public table count দেখাবে; row value দেখাবে না।

### ৩.৩ Restore যাচাই

Target database-এ row count/constraint মিলিয়ে দেখুন। Production-এর সঙ্গে compare করতে চাইলে শুধু **count** ও **constraint** দেখুন, কোনো student row দেখবেন না।

2026-10-30-এ করা যাচাই:

- migration-এর আগের encrypted backup একটি isolated PostgreSQL copy-তে restore করা হয়েছিল।
- ফল: 58 public table, 3,035 row, remote-এর সঙ্গে **0 table count mismatch**।
- Constraint: 78 foreign key, 97 unique index, 58 primary key—live Supabase-এর সঙ্গে মিলেছে।
- Dump-এ Supabase-specific `supabase_vault`/`storage` extension থাকায় শুধু `public` schema restore করা হয়েছিল; local PostgreSQL-এ ওই extension নেই। Production restore-এর জন্য Supabase-এর নিজস্ব backup/restore path ব্যবহার করুন।

**সীমাবদ্ধতা:** এই Windows environment-এ PostgreSQL-এর multi-user server low-integrity sandbox token-এর কারণে start হচ্ছিল না; তাই restore test-টি single-user mode + `pg_restore` table-only SQL দিয়ে করা হয়েছে। Normal Windows session-এ উপরের `--restore` কমান্ডটি সরাসরি ব্যবহার করুন।

## ৪. Local MariaDB backup restore

### ৪.১ কখন করবেন

Local MariaDB শুধু Supabase-এর mirror। সাধারণ অবস্থায় restore করার দরকার নেই—mirror service চালু করলে Supabase থেকে data আবার নেমে আসবে। Local restore দরকার শুধু তখন, যখন Supabase/ইন্টারনেট ছাড়া local copy থেকে জরুরি read চালাতে হবে।

**গুরুত্বপূর্ণ:** restored local data কখনো Supabase-এ push করবেন না। এতে duplicate/conflict তৈরি হবে।

### ৪.২ Production local DB-তে restore (জরুরি অবস্থায়)

1. Backend ও mirror service বন্ধ করুন (দুটো আলাদা window হলে বন্ধ করুন)।
2. বর্তমান local DB-র আরেকটি backup নিন:
   ```bat
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\backup_database.ps1
   ```
3. gzip খুলুন এবং `schooldb`-এ restore করুন:
   ```powershell
   $src = [IO.File]::OpenRead('database_backups\school_system_local_mariadb_20261030_125531.sql.gz')
   $gz  = [IO.Compression.GzipStream]::new($src, [IO.Compression.CompressionMode]::Decompress)
   $dst = [IO.File]::Create('database_backups\restore_temp.sql')
   try { $gz.CopyTo($dst) } finally { $dst.Dispose(); $gz.Dispose(); $src.Dispose() }
   ```
   ```bat
   runtime\mysql\bin\mysql.exe --host=127.0.0.1 --port=3306 --user=root --one-database schooldb < database_backups\restore_temp.sql
   ```
4. Restore শেষে `restore_temp.sql` delete করুন।
5. Mirror service আবার চালু করুন; এটা Supabase থেকে current data আবার নামিয়ে আনবে।

### ৪.৩ Isolated restore test (recommended)

একই MySQL server-এ production `schooldb`-কে touch না করে আলাদা temporary MariaDB instance বানান:

```bat
runtime\mysql\bin\mysql_install_db.exe -d .tmp\mariadb_restore_test\data
runtime\mysql\bin\mysqld.exe --datadir=".tmp\mariadb_restore_test\data" --port=3307 --basedir="runtime\mysql" --console
runtime\mysql\bin\mysql.exe --host=127.0.0.1 --port=3307 --user=root --execute="CREATE DATABASE schooldb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
runtime\mysql\bin\mysql.exe --host=127.0.0.1 --port=3307 --user=root --one-database schooldb < database_backups\restore_temp.sql
```

Restore যাচাই (row value ছাড়া):

```bat
runtime\mysql\bin\mysql.exe --host=127.0.0.1 --port=3307 --user=root --skip-column-names --batch --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='schooldb' AND table_type='BASE TABLE'; SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_schema='schooldb' AND constraint_type='FOREIGN KEY'"
```

2026-10-30-এ isolated MariaDB restore test:

- 38-table পুরোনো backup: 38 table, 1,354 row, 54 FK—সফলভাবে restore হয়েছে (পুরোনো snapshot)।
- 58-table backup: 58 table, 3,035 row, 93 FK—সফলভাবে restore হয়েছে।
- সর্বশেষ 62-table backup (`20261030_125531`): isolated `schooldb_restore_62`-এ restore করে **62 table, 3,035 row, 107 FK** পাওয়া গেছে; restore-এর পর test database drop করা হয়েছে।

কাজ শেষে temporary instance বন্ধ করুন:

```bat
runtime\mysql\bin\mysqladmin.exe --host=127.0.0.1 --port=3307 --user=root shutdown
```

এরপর `.tmp\mariadb_restore_test` delete করুন।

## ৫. Backup retention ও নিরাপত্তা

- Local backup: 30 দিনের পুরোনো `school_system_local_mariadb_*.sql.gz` স্বয়ংক্রিয়ভাবে মুছে যায়; সঙ্গে `.sha256`/`.manifest.json`-ও।
- Encrypted Supabase backup: default সর্বশেষ 14 set রাখা হয় (`SUPABASE_BACKUP_RETENTION` দিয়ে বদলানো যায়, minimum 3)।
- `database_backups/` ও `runtime/`—দুটোই `.gitignore` ও `.vercelignore`-এ আছে। কোনো backup Git commit বা Vercel upload-এ যাবে না।
- DPAPI key শুধু যে Windows user backup নিয়েছে তার জন্য খোলে। ওই user profile/key হারালে encrypted backup restore করা যাবে না; key-এর নিরাপদ offline copy রাখুন।
- Backup folder-এ access শুধু authorized operator-কে দিন।

## ৬. Excel export সম্পর্কে

চাইলে database-এর tableগুলো worksheet-এ export করা সম্ভব (read/analysis-এর জন্য)। কিন্তু `.xlsx` কখনো restore backup নয়—এতে constraint, index, foreign key বা পূর্ণ relational data থাকে না। এখনই Excel export প্রয়োজন নেই; আলাদা করে বললে তখন করা হবে।
