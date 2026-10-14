# School 24/7 — Laptop সার্ভার সেটআপ (Bangla Guide)

Laptop থেকেই স্কুল সিস্টেম ২৪/৭ চালানোর সম্পূর্ণ নির্দেশনা। Vercel/Supabase আর লাগবে না —
Database + Backend সব এই কম্পিউটারেই চলবে, মোবাইল ডাটা/বাইরে থেকে Cloudflare Tunnel দিয়ে ঢোকা যাবে।

## ১. যা যা তৈরি আছে

| জিনিস | অবস্থান |
|---|---|
| Database (MariaDB, `schooldb`, সব live data সহ) | `db\data` (project folder-এর ভেতর, চলছে port 3306) |
| DB binaries | `runtime\mysql\bin` (project folder-এর ভেতর — XAMPP install লাগে না) |
| Backend (Node, port **5000**) | `backend\start-local.bat` |
| Public Tunnel (Cloudflare) | `backend\start-tunnel.bat` |
| Auto-start (laptop on করলেই চালু) | Startup folder → `School24x7-AutoStart.bat` |
| Teacher/Guardian APK | `backend\apks\TeacherApp.apk`, `GuardianApp.apk` |
| Admin Panel | ব্রাউজারে `http://localhost:5000` (একই laptop) |

Login: **admin / 123456#** • সব teacher: **username / 123456** (teacher app-এর Profile → Password পরিবর্তন থেকে নিজে বদলাতে পারবে)।

## ২. প্রতিদিন চালানো (সাধারণত auto-start-ই যথেষ্ট)

1. Laptop on করুন → ৩০ সেকেন্ড অপেক্ষা করুন (DB + Backend + Tunnel নিজে চালু হবে)।
2. Tunnel window-তে যে `https://....trycloudflare.com` লিংক দেখাবে — **এটাই public link** (মোবাইল ডাটা থেকে চলবে)।
3. Admin panel: public link-এ ব্রাউজার থেকে খুলুন, অথবা laptop-এ `http://localhost:5000`।

হাতে চালাতে হলে: `backend\start-local.bat` → তারপর `backend\start-tunnel.bat`।

## ৩. মোবাইলে App install + Server বসানো

1. মোবাইলের browser-এ public tunnel link খুলে `/apks/TeacherApp.apk` বা `/apks/GuardianApp.apk` download করে install করুন।
   - সরাসরি: `https://....trycloudflare.com/apks/TeacherApp.apk`
2. App-এর **Login screen → নিচে Server লেখা** → সেখানে tunnel link (অথবা wifi-তে থাকলে `http://192.168.0.112:5000`) বসিয়ে **Test → Save** চাপুন।
3. তারপর login করুন। App **offline-ও চলবে** — net এলে data auto-sync হবে।

> ⚠️ Tunnel restart হলে link বদলায় — নতুন link app-এর Server setting-এ বসিয়ে নিন (rebuild লাগে না)। স্থায়ী একই link চাইলে নিচের ৬ নম্বর দেখুন।

## ৪. Wifi (LAN) থেকে সরাসরি (tunnel ছাড়া)

- URL: `http://192.168.0.112:5000` (laptop-এর IP বদলালে `ipconfig` দিয়ে দেখে app-এ বসান)।
- প্রথমবার Windows Firewall allow চাইতে পারে — **Admin password দিয়ে Allow** করুন (একবারই)। না করলে wifi-এর ফোন ঢুকতে পারবে না (tunnel দিয়ে তখনো চলবে)।

## ৫. নতুন APK বানানো (code বদলালে)

```bat
cd apps\teacher_app
flutter build apk --release --dart-define=API_URL=http://192.168.0.112:5000
copy build\app\outputs\flutter-apk\app-release.apk ..\..\backend\apks\TeacherApp.apk
```
Guardian-এর জন্য `apps\guardian_app` + `GuardianApp.apk`। Version: `backend\server.js` → `APP_VERSIONS` বাড়ান (যেমন teacher `1.3.3` → `1.3.4`) — app নিজে থেকেই update চাইবে, browser লাগবে না।

## ৬. স্থায়ী একই public link (optional, advanced)

Quick tunnel প্রতিবার নতুন link দেয়। একই link সবসময় চাইলে (বছরে ~১ বার setup):
1. cloudflare.com-এ free account + একটা domain (বা subdomain) নিন।
2. `bin\cloudflared.exe tunnel login` (project folder থেকে) → browser-এ approve করুন।
3. `cloudflared.exe tunnel create school` → `tunnel --hostname school.apnardomain.com` দিয়ে `backend\start-tunnel.bat`-এর লাইন বদলে দিন।

## ৭. সমস্যা হলে

| সমস্যা | করণীয় |
|---|---|
| `localhost:5000` চলে না | `backend\start-local.bat` চালু আছে কিনা দেখুন; `runtime\mysql\bin\mysqladmin.exe -uroot ping` দিয়ে DB check |
| Tunnel link কাজ করে না | Tunnel window খোলা আছে কিনা + link-টা নতুন কিনা দেখুন |
| App-এ login হয় না | App-এর Server setting-এ **বর্তমান** tunnel link/LAN IP আছে কিনা দেখুন |
| Laptop restart-এর পর | Startup folder-এর `School24x7-AutoStart.bat` আছে কিনা দেখুন |
| পুরনো Supabase-এ ফেরত যেতে চাইলে | `backend\.env.supabase.bak` → `.env` নামে copy করে server restart |

## ৮. Backup

- Database backup: `runtime\mysql\bin\mysqldump.exe -uroot schooldb > backup.sql`
- `.env` (password সহ) ও `backend\apks\` মাঝে মাঝে অন্য জায়গায় copy রাখুন।
