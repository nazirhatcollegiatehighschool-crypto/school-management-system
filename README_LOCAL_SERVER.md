# School 24/7 — Laptop সার্ভার (সংক্ষিপ্ত বাংলা গাইড)

> পূর্ণ নির্দেশনা: [PROJECT_GUIDE_BN.md](PROJECT_GUIDE_BN.md) · Backup/restore: [docs/RESTORE_GUIDE_BN.md](docs/RESTORE_GUIDE_BN.md)

## গুরুত্বপূর্ণ পরিবর্তন

আগের নথিতে লেখা ছিল "Vercel/Supabase লাগবে না"—এটি আর সঠিক নয়। বর্তমান architecture:

- **Supabase PostgreSQL** হলো মূল database; তিন app-এর সব live write Vercel API দিয়ে এখানেই যায়।
- **Vercel API** সবসময় online; laptop বন্ধ থাকলেও app চলে।
- **Local MariaDB (`schooldb`)** শুধু Supabase-এর read-only mirror; laptop চালু থাকলে প্রতি ৫ মিনিটে sync হয়।
- Local DB-তে app write করে না; local data Supabase-এ push করবেন না।

## চালানো

```bat
start-all.bat
```

এটি MariaDB → mirror service → backend :5000 → tunnel → watchdog চালু করে। শুধু DB+mirror+API:

```bat
backend\start-local.bat
```

Health: `http://localhost:5000/api/health`

Windows login-এ `School24x7-AutoStart.vbs` / `start-local.bat` নিজে চালু হয়; `watchdog.bat` প্রতি ৬০ সেকেন্ডে mirror-ও restart করে।

## Mirror দেখার কমান্ড

```bat
node scripts\local_db_mirror.js --check
node scripts\local_db_mirror.js --verify --deep
```

Log: `logs\local_db_mirror.log`। `SYNC OK` মানে count+constraint verified; `SYNC PARTIAL` মানে data গেছে কিন্তু repair/verification বাকি।

## Backup

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\backup_database.ps1
node scripts\backup_supabase_secure.cjs
```

Backup `database_backups/` ও `runtime/secure_backups/`-এ থাকে; Git/Vercel-এ যায় না। Restore কখনো production-এ নয়—isolated DB-তে; বিস্তারিত restore guide-এ।

## App install / server URL

- App-এর default API: `https://school-management-system-mobile-api.vercel.app`
- LAN-এ local API ব্যবহার করতে চাইলে app-এর Server setting-এ `http://<laptop-ip>:5000` দিন; `localhost` দিলে ফোন নিজের localhost খোঁজে।
- Tunnel চালু করলে তার HTTPS URL app-এর Server setting-এ দিন। Tunnel restart হলে URL বদলাতে পারে।

## নতুন APK

```bat
cd apps\teacher_app
flutter build apk --release
copy build\app\outputs\flutter-apk\app-release.apk ..\..\backend\apks\TeacherApp.apk
```

Admin/Guardian-এর জন্য সংশ্লিষ্ট folder ও APK নাম। Build/version/signing নিয়ম `PROJECT_GUIDE_BN.md`-এ।

## সমস্যা

| সমস্যা | করণীয় |
|---|---|
| API health fail | Vercel deployment Status, Supabase project status দেখুন |
| Mirror বন্ধ | `logs\local_db_mirror.log` / `logs\local_db_mirror_error.log`; `logs\local_db_mirror.pid` |
| Local DB বন্ধ | `runtime\mysql\bin\mysqladmin.exe -uroot ping`; `db\my.ini` |
| App login fail | app-এর Server URL, Vercel API health, internet |
| Laptop restart | Startup folder-এর `School24x7-AutoStart.vbs` আছে কিনা দেখুন |

## নিরাপত্তা

`.env`, `DATABASE_URL`, `JWT_SECRET`, `CRON_SECRET`, Supabase/backup key—কোথাও copy বা share করবেন না। Backup-এ ব্যক্তিগত data থাকে; access সীমিত রাখুন।
