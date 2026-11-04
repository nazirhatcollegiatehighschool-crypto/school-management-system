# School System — বাংলা প্রকল্প নির্দেশিকা

সর্বশেষ যাচাই: 2026-10-30 (Asia/Dhaka)। এই নথিতে server চালানো, Vercel/Supabase, local MariaDB mirror, backup/restore, Excel export এবং feature-গুলোর বর্তমান অবস্থা লেখা আছে। কোনো secret, student data বা পূর্ণ connection string এখানে নেই।

## ১. এক নজরে

```text
Admin / Teacher / Guardian Android app
                │  HTTPS  /api
                ▼
        Vercel API (school-management-system)
                │
                ▼
     Supabase PostgreSQL  ←── সব live write এখানে
                │
                │  একমুখী read-only mirror (প্রতি ৫ মিনিট)
                ▼
     Local MariaDB (schooldb) — শুধু PC চালু থাকলে
```

- তিনটি app-এর সব live write Vercel API হয়ে **Supabase**-এ যায়। App কখনো সরাসরি local MariaDB-তে লেখে না।
- Local MariaDB হলো Supabase-এর **mirror**। PC বন্ধ থাকলে local DB চলে না, কিন্তু Vercel API ও Supabase online থাকায় app চলে।
- PC চালু হলে mirror service সঙ্গে সঙ্গে Supabase থেকে catch-up করে, তারপর প্রতি ৫ মিনিটে refresh করে।
- দুই database-এ আলাদা write বা bidirectional sync নেই। Local DB-র data Supabase-এ push করবেন না।

## ২. বর্তমান cloud অবস্থা (read-only যাচাই)

- Account mapping: GitHub/Supabase = `nazirhatcollegiatehighschool@gmail.com`; Vercel = `asad6ullah7775@gmail.com`। এই account separation পরিবর্তন করবেন না।
- মূল project link: [`school-management-system`](https://school-management-system-brown-mu.vercel.app)।
- `backend/.vercel/project.json`-এর পুরোনো project link `nazirhatcollegiatehighschool-2397`। Production deployment root project থেকে চালাতে হবে; backend folder-এর stale link দিয়ে deploy করলে mismatch হতে পারে।
- Vercel project: `school-management-system` (Production)।
- সর্বশেষ Production deployment: **Ready**, `school-management-system-brown-mu.vercel.app` alias; 2026-10-30-এ deploy ও যাচাই করা হয়েছে。
- `https://school-management-system-brown-mu.vercel.app/api/health` → `{"status":"ok","db":"connected"}`।
- তিন app-এর default API: `https://school-management-system-brown-mu.vercel.app` (override করলে সেটি আগে)।
- `vercel.json`-এ cron:
  - `/api/cron/attendance-reminders` — প্রতিদিন ০৯:০০
  - `/api/cron/daily-maintenance` — প্রতিদিন ১৮:০০
- Production-এ প্রযোজনীয় environment variable-এর নাম আছে; value কোথাও দেখা/দেখানো হয়নি।
- `/api/cron/daily-maintenance` ও protected Admin API-তে token ছাড়া request `401` দেয়।
- Latest app build: Admin `1.4.7+14`, Teacher `1.4.8+2003012`, Guardian `1.4.5+14`; তিন APK production-এ আছে।

## ৩. Local server চালানো

Project root: `C:\Users\WALTON\Desktop\school-system`

### পুরো stack

```bat
start-all.bat
```

এটি ক্রমে MariaDB, mirror service, backend (port 5000), tunnel ও watchdog চালু করে। Windows login-এ `School24x7-AutoStart.vbs` → `start-all.bat` চলে; `backend\start-local.bat`-ও mirror start করে। `watchdog.bat` প্রতি ৬০ সেকেন্ডে DB/mirror/backend/tunnel check করে এবং বন্ধ থাকলে আবার চালু করে।

### শুধু DB + mirror + API

```bat
backend\start-local.bat
```

- MariaDB: project-এর `runtime/mysql` binary, data directory `db/data`, schema `schooldb`, port 3306।
- API: `http://localhost:5000`, health: `http://localhost:5000/api/health`।
- LAN-এর ফোনে `http://<laptop-ip>:5000`; `localhost` দিলে ফোন নিজের localhost খোঁজে।

### Backend হাতে চালানো

MariaDB চালু থাকলে:

```bat
cd backend
node server.js
```

`PORT` না থাকলে 5000। Backend-এর `DATABASE_URL` PostgreSQL হলে Supabase-এ যায়; `mysql://` হলে local MariaDB-তে যায়। **এই mirror architecture-এ backend-এর `DATABASE_URL` কখনো local MariaDB-তে বদলাবেন না**—নাহলে দুই database-এ write হয়ে conflict হবে।

## ৪. Supabase → Local MariaDB mirror

### কাজের নিয়ম

- Source: `backend/.env`-এর `DATABASE_URL` (Supabase PostgreSQL)।
- Target: local `schooldb`।
- `LOCAL_MIRROR_INTERVAL_SECONDS` default **300** (৫ মিনিট, minimum 60)।
- Service চালু হওয়ার সঙ্গে সঙ্গে প্রথম catch-up চলে; তারপর periodic।
- একই সময়ে একাধিক mirror process চলতে দেয় না—`logs/local_db_mirror.pid` lock; crash হলে stale PID শনাক্ত করে নতুন process lock নেয়।
- Service ব্যর্থ হলেও Vercel/Supabase-এ চলা online app বন্ধ হয় না।
- Local DB-তে কোনো local-only write করা হয় না; backend local mode-এ চালালেও সেটি Supabase-এ লেখে।

### হাতের কমান্ড

```bat
node scripts\local_db_mirror.js --check
node scripts\local_db_mirror.js --verify
node scripts\local_db_mirror.js --verify --deep
node scripts\local_db_mirror.js --once
node scripts\local_db_mirror.js
```

- `--check`: শুধু schema metadata (table/column/constraint/enum), data লেখে না।
- `--verify`: schema + সব table-এর row count + constraint যাচাই; `--deep` দিলে primary-key content hash-ও মেলায়। কোনো row value print হয় না।
- `--once`: একবার পূর্ণ refresh করে exit।
- না দিলে service mode (৫ মিনিট interval)।

### Log/status অর্থ

- `SYNC OK: N tables; M rows ... counts and constraints verified.` — পূর্ণ সফল।
- `SYNC PARTIAL (data committed): ...` — data commit হয়েছে, কিন্তু constraint/nullability repair বা verification বাকি। এটিকে পূর্ণ সফল ধরবেন না।
- `SYNC failed (CODE); no local data was committed.` — transaction rollback হয়েছে; local snapshot আগের মতোই আছে।

Log: `logs/local_db_mirror.log`; service-এর stderr: `logs/local_db_mirror_error.log`। Lock: `logs/local_db_mirror.pid`।

### Mirror-এর নিরাপত্তা

- Remote থেকে data পড়া হয় একটি repeatable-read snapshot-এ; মাঝপথে app লিখলে half-old/half-new mirror হয় না।
- Data refresh একটি transaction-এ DELETE+INSERT; row count মিললেই commit।
- Constraint তুলনা column order-insensitive (unique key-এর column order বদলালেও একই constraint ধরা হয়); একই নামের ভিন্ন index থাকলে নিরাপদ বিকল্প নাম ব্যবহার করে, অথবা সমতুল্য হলে কিছু করে না।
- PostgreSQL `DATE` value local calendar day হিসেবে লেখা হয়—timezone-এর কারণে এক দিন সরে যাওয়ার bug ঠিক করা হয়েছে।

### বর্তমান mirror অবস্থা

সর্বশেষ `--verify --deep`:

```text
Supabase tables=62; local tables=62; rows=3046; missing tables=0;
missing columns=0; missing constraints=0; row-count mismatches=0;
deep PK-hash mismatches=0
```

মানে local `schooldb` এখন Supabase-এর সম্পূর্ণ schema (62 table) ও 3,046 row-এর verified mirror। Mirror worker চলছে; সাম্প্রতিক একটি periodic attempt `ENOTFOUND`-এ ব্যর্থ হলেও local data commit হয়নি। Deep verification-এ দুই database-এর content মিলে গেছে।

## ৫. Database schema ও migration

- Supabase-এ বর্তমানে **62 public table**।
- 2026-10-30-এ add-only migration apply করা হয়েছে:
  - `students.guardian_profile_locked_at`, `class10_start_year`, `is_irregular`
  - `users.teacher_dob/address/blood_group/index_number/pns_number/degree/joining_date`
  - `notifications.target_user_id`, `uq_notifications_dedup` unique index
  - `attendance_delegation.expires_at_epoch`
  - `attendance_summary.early_departure_with_leave`, `early_departure_no_leave`
  - নতুন table: `attendance_access_requests`, `student_profile_edit_requests`, `student_uniform_reports`, `teacher_notification_reads`
- Migration-এর আগে ও পরে 58টি পুরোনো table-এর row count মিলিয়ে দেখা হয়েছে—কোনো row মুছেনি।
- Guardian profile: যেসব existing student-এর required profile fields সম্পূর্ণ, তাদের lock করা হয়েছে (31 জন); অসম্পূর্ণ 82 জন guardian একবার complete করতে পারবেন।
- Migration চালানোর নিরাপদ উপায় (ভবিষ্যতে):

```bat
node scripts\apply_additive_migration.cjs <migration-file.sql>
```

Scriptটি `DROP TABLE`/`TRUNCATE`/`DELETE FROM`/`DROP COLUMN` দেখলে refuse করে; PostgreSQL-এ transaction-এ চালায় এবং row count বদলালে rollback করে। MySQL-এ DDL auto-commit, তাই migration files idempotent রাখা হয়েছে।

- Runtime/HTTP request থেকে schema change বন্ধ করা হয়েছে। Schema শুধু reviewed migration দিয়ে বদলাবে।
- Local mirror schema add-only: নতুন column/table যোগ হয়, কিছু drop করে না।

## ৬. Backup ও restore

বিস্তারিত: [docs/RESTORE_GUIDE_BN.md](docs/RESTORE_GUIDE_BN.md)

### Local MariaDB backup

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\backup_database.ps1
```

সব database-এর compressed logical dump, সম্পূর্ণ decompress করে completion marker যাচাই, SHA-256 + manifest, 30-day retention। সর্বশেষ:

- `database_backups/school_system_local_mariadb_20261030_125531.sql.gz`
- SHA-256: `E69774BA8AC21467AC153D363A93C9629FBFA97B3A90E6988E388A357F43C051`
- 62-table বর্তমান local snapshot

### Supabase encrypted backup

```bat
node scripts\backup_supabase_secure.cjs
```

pg_dump custom archive → AES-256-GCM → DPAPI-protected key; decrypt/list verification সফল হলেই manifest লেখে; default 14 set retention। সর্বশেষ:

- `runtime/secure_backups/supabase-live-2026-10-30T06-57-39-378Z.dump.sbk`
- encrypted SHA-256: `7A04A041423EC8CA4DC766F2835AC6DFAC8C70868AF0550722A0CE3C4A1F40DB`
- table-data entries: 100

Restore test isolated DB-তে করা হয়েছে; production-এ নয়। কীভাবে করবেন, কী warn করবেন—সব `docs/RESTORE_GUIDE_BN.md`-এ।

### Backup কখনো commit/upload হবে না

`database_backups/`, `runtime/`, `.tmp/`, `release_builds/`, `apps/release_builds/`—সব `.gitignore`-এ আছে; `database_backups/` ও `runtime/` `.vercelignore`-এও আছে। `.tmp/`-এ database copy/decrypted dump রাখা হয় না (কাজ শেষে delete করা হয়)।

## ৭. Excel export

চাইলে database tableগুলো `.xlsx` worksheet-এ export করা যায়—পড়া/বিশ্লেষণের copy হিসেবে। কিন্তু এটি restore backup নয়: constraint, index, foreign key, relational integrity থাকে না। এখনই Excel export প্রয়োজন নেই; আলাদা করে বললে তখন করা হবে।

## ৮. তিনটি app

| App | কাজ | default API |
|---|---|---|
| Admin | student/teacher/class, exam/result, attendance, promotion, settings, PDF | Vercel API |
| Teacher | class/student, attendance, marks, routine, homework, promotion review, notifications | Vercel API |
| Guardian | সন্তানের profile, attendance, result, routine, homework, complaint, notification | Vercel API |

Offline cache/outbox প্রতিটি app-এর `lib/sync_store.dart`-এ; network ফিরলে queue replay হয়। App বদলালে queue সঙ্গে যায় না। Server URL override app settings-এ; build-এ `--dart-define=API_URL=...`।

## ৯. Feature বাস্তবায়ন অবস্থা

2026-10-30-এর code audit ও synthetic test অনুযায়ী:

| # | Feature | অবস্থা | যাচাই |
|---|---|---|---|
| 1 | Teacher quick-add: Roll, Birth Certificate, Birthdate, Guardian Phone; Admin student form-এ Roll/Birth Cert/Birthdate এক কলামে | সম্পূর্ণ | API synthetic pass; duplicate roll 409; Admin release build |
| 2 | Guardian profile completion-এ DOB ও Birth Certificate-সহ required fields, একবার submit-এ lock, Edit Request Admin+Class Teacher-এর কাছে | সম্পূর্ণ | server-side required-field/date/phone validation; prior synthetic lock flow |
| 3 | Class 10 retained: original session year, স্থায়ী Irregular tag, exam running calendar year | সম্পূর্ণ (data backfill সহ) | profile API-তে irregular+year pass; promotion calendar code review |
| 4 | একই subject-এ দুই teacher marks; প্রথম submit official lock; race/unique constraint | সম্পূর্ণ | দুই teacher draft + first submit 200 + second 409 pass |
| 5 | Attendance delegation daily/period; class teacher direct, অন্য teacher request, accept/reject, delegated read-only history | সম্পূর্ণ | synthetic pass |
| 6 | Attendance request in-app Accept/Reject, result, expiry, disabled expired button | সম্পূর্ণ | API expiry pass; UI 30s timer + disabled button code |
| 7 | Guardian dashboard: চলমান class banner, class/subject/teacher/phone tap-to-call, routine/attendance cards; teacher-এর অন্য student profile bug | সম্পূর্ণ | guardian banner widget test pass; profile access check fix + 403 test |
| 8 | Admin religion dropdown DB values; gender canonical spelling | সম্পূর্ণ | DB distinct values + canonical normalization; synthetic Female save pass |
| 9 | Uniform-only report; uniform missing result count; complaint Homework/Ajker menu আলাদা | সম্পূর্ণ | uniform separate report pass; complaint UI code review |
| 10 | Admin online/offline status teacher app-এর মতো; অপ্রয়োজনীয় “online চালু” বাদ | সম্পূর্ণ | admin offline banner code review |
| 11 | Attendance roster selected class, roll order, uniform field নেই; শুধু updated student-এর guardian report; untouched data অপরিবর্তিত | সম্পূর্ণ | daily report notification only-one-student + dedup pass |
| 12 | Teacher optional birthdate/address/blood/index/PNS/degree/joining; Guardian শুধু নাম+ফোন | সম্পূর্ণ | API synthetic pass; guardian query code review |
| 13 | Admin school report PDF: watermark, school name, EIIN 104417, English address, established 1954; teacher name/degree/phone/signature blank/comment; Head+Assistant Head signature blank | সম্পূর্ণ | PDF widget tests pass; layout code review |
| 14 | Teacher notification fully functional; click deep-link relevant screen | সম্পূর্ণ | notification API + deep-link code review |
| 15 | Admin settings English address; Head/Assistant Head dropdown selection source of truth; Senior/Assistant logic | সম্পূর্ণ | leadership selection API pass; designation code review |
| 16 | আগের conversation-এর সব নির্দেশনা cross-check | সম্পূর্ণ | এই audit-এ 1–15 মিলিয়ে দেখা হয়েছে |
| 17 | Fake/synthetic data দিয়ে তিন app flow test; cleanup | আগের isolated API run pass; এই release-এ full E2E পুনরায় করা বাকি | আগের 30/30 API pass-এর evidence আছে; এইবার disposable test DB ও সংযুক্ত ফোন পাওয়া যায়নি |

## ১০. Test evidence (2026-10-30)

- **Mirror:** 62 table, 3,054 row, 0 missing table/column/constraint, 0 count/hash mismatch (deep PK hash verify, 2026-10-30)।
- **Backend:** 53/53 Node regression tests pass; `node lint.js` → `lint OK (98 files)`।
- **Flutter tests:** Teacher 20, Admin 4, Guardian 7—সব pass।
- **Flutter analyze:** তিন app compile errors ছাড়া pass; Admin 23, Teacher 34, Guardian 6 info-level lint দেখিয়েছে (analyzer non-zero শুধু info findings-এর জন্য)।
- **Synthetic API flow:** আগের 30/30 pass report রয়েছে; এই release-এ তা পুনরায় চালানো হয়নি, কারণ disposable test database configured ছিল না। Production-এ fake student লেখা হয়নি।
- **Backup/restore:** encrypted Supabase backup decrypt/list verified; isolated PostgreSQL-এ 58 table/3,035 row/78 FK/97 unique restore; local MariaDB-এ সর্বশেষ backup restore করে 62 table/3,035 row/107 FK পাওয়া গেছে।
- Synthetic test production data ব্যবহার করেনি; test DB (`schooldb_feature_test`) কাজ শেষে drop করা হয়েছে।

## ১১. এই release-এ সম্পন্ন ও বাকি

- **Vercel Production:** deployment `dpl_4F5rWkRdzGi4WDiqDiEvBvUnWMB5` `READY`; stable alias health `ok/db connected`; তিন app-এর version/build/SHA-256 live metadata নতুন APK-এর সঙ্গে মেলে; signing secrets উপস্থিত, অপরিবর্তিত।
- **তিন Android release:** Admin `1.4.8+15`, Teacher `1.4.9+2003013`, Guardian `1.4.6+15`; একই production release certificate-এ signed, Vercel-এ প্রকাশিত।
- সর্বশেষ APK রাখা হয়েছে `apps/release_builds/release_20261030_complete2/` এবং production copy `backend/apks/`-এ; পুরোনো release APK files সরানো হয়েছে।
- **Phone install:** এই update-এর সময় ADB-তে কোনো device দেখা যায়নি, তাই নতুন APK ফোনে বসানো/launch smoke test বাকি। আগের release-এ Admin/Teacher uninstall-reinstall এবং Guardian in-place update করা হয়েছিল।
- **Fake-student authenticated E2E:** এই release-এ চালানো বাকি। disposable DB configured নেই; কোনো fake student Production-এ লেখা হয়নি।
- **UI scope:** Admin/Teacher/Guardian widget test ও release build pass; নতুন release-এ authenticated screen-by-screen phone test হয়নি। PDF-এর printed/real-data visual layout-ও এইবার যাচাই হয়নি।
- Future schema changes হলে reviewed add-only migration দরকার; Production schema change এই release-এ করা হয়নি।

## ১২. পরবর্তী নিরাপদ কাজ

1. Authenticated fake-student flow পুনরায় চালাতে আগে আলাদা disposable/staging DB configure করুন; production student data ব্যবহার করবেন না।
2. Backup ও DPAPI key-এর offline নিরাপদ copy রাখুন।

## ১৩. Troubleshooting

| লক্ষণ | দেখুন |
|---|---|
| Mirror চলছে না | `logs/local_db_mirror.log`, `logs/local_db_mirror_error.log`, `logs/local_db_mirror.pid` |
| Mirror `SYNC PARTIAL` | log-এ constraint/table name; `--verify` চালান; data commit হয়েছে কিন্তু constraint বাকি |
| API health fail | Vercel deployment status, Supabase project status, `DATABASE_URL` presence (value নয়) |
| Local DB খুলছে না | `db/my.ini`, `runtime/mysql/bin/mysqladmin -uroot ping`, `db/data` |
| App online কিন্তু data পুরোনো | app-এর server URL override, Vercel deployment, network; local mirror app data-র source নয় |
| Backup restore fail | `docs/RESTORE_GUIDE_BN.md`; DPAPI key একই Windows user কি না; target DB isolated কি না |

## ১৪. নিরাপত্তা

- `.env`, `DATABASE_URL`, `JWT_SECRET`, `CRON_SECRET`, Supabase key, backup key—কখনো chat/log/screenshot/Git-এ দেবেন না।
- Backup-এ ব্যক্তিগত data থাকে; access সীমিত রাখুন।
- Production-এ destructive schema/data operation, secret rotation বা অপ্রয়োজনীয় redeploy করবেন না।
- Local DB-র data Supabase-এ push করবেন না; mirror একমুখী।
