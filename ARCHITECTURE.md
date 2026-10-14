# School Management App — Architecture Blueprint (single source of truth)

> Lead-architect working agreement: every feature needs (1) tables/columns,
> (2) API endpoints + logic, (3) UI wiring, (4) security/error handling.
> Update this file whenever any of those change. Pending bigger work lives
> in the 12-item hardening pass (paused goal history + local todos).

## 1. Stack & runtimes (all LOCAL — no cloud dependency at runtime)

| Layer | Tech | Entry point / port |
|---|---|---|
| Database | MariaDB 10.4 via XAMPP (`C:\xampp\mysql`), DB `schooldb`, utf8mb4 | `127.0.0.1:3306`, user `root` |
| Backend | Node 24 + Express 4 (`backend/`, `server.js`) | `0.0.0.0:5000` (`PORT` env) |
| Admin web | React + Vite (`website/admin-site`, `npm run build` → `backend/dist/`) | served by backend `/` |
| Mobile | Flutter 3.47 (teacher_app, guardian_app, admin_app) | APKs in `backend/apks/` |
| Public link | Cloudflare quick tunnel → `localhost:5000` | URL printed by `start-tunnel.bat` |
| Push | Firebase Admin SDK (`backend/firebase-service-account.json`, git-ignored) | device_tokens table |
| PDFs | pdfkit (server-side marksheet/result-card) | `/api/.../*.pdf` routes |

Start order: MariaDB → `node server.js` (or `backend/start-local.bat`) → tunnel (`backend/start-tunnel.bat`). Autostart: Startup-folder `School24x7-AutoStart.bat`.

## 2. RBAC (enforced in `backend/middleware/auth.js` → `auth('role')`)

| Role | Users live | Allowed surface |
|---|---|---|
| `admin` (1) | full control | `/api/admin/*` (18 gates): students, teachers, guardians, classes, sessions, subjects, exams, marks unlock/approve, promotions, routines, notices, holidays, settings; `/api/results/*` (compute/tabulation/publish) |
| `teacher` (21) | own classes/subjects only | `/api/teacher/*` (7 gates): profile, subjects, exams, marks (5h window), attendance (own class only), notify, CT-marks, homework, complaints, routine CRUD, promotion review (read-only), seat/admit PDFs |
| `guardian` (2) | linked students only | `/api/guardian/*` (2 gates): profile/attendance/marks/homework/notifications/result-card/marksheet — all scoped by `guardian_links.status='approved'` |

Rules: JWT 7d (`JWT_SECRET` env, fallback default — set a strong one in production); login rate-limited (20/15m); teachers see only own classes/subjects; guardians see only approved-linked students.

## 3. API inventory (base `/api`)

- `auth`: POST login/guardian-login, GET me, device register/unregister
- `admin`: stats, activity, students CRUD + subjects, teachers CRUD + active, guardians, classes, sessions (+active), class-teacher requests, subjects, exams CRUD, marks view/edit/unlock, **exams/:id/entry + events/:id/entry (entry_open 0/1)**, attendance, monthly, notifications, notices, holidays, settings, photo upload, marks-bulk, publish-admin/unpublish, shares, promote/{review,execute,grace}
- `teacher`: profile(+password), subjects, exams CRUD + marks + publish + coverage, students register, class-teacher-request(s), directory, guardians, attendance(+monthly/today), notify, ct-marks, homework, complaints, OCR, escape patch, promotion/review, mark unlock request/list, events (+result/coverage/entry-subjects/marks/seat-plan/admit), PDF variants
- `guardian`: profile, attendance(monthly), marks, homework, notifications(+read), complaints, result/:examId, exam-events, marksheet, result-card(+pdf), sibling-request(s)
- `results` (admin-only): events CRUD + publish/unpublish/coverage/ensure-session, results/compute, tabulation, marksheet(+pdf), remarks
- `routine`: slots, teacher mine/CRUD + delete-requests, admin CRUD + delete-requests approve/reject, all, conflicts, aliases, student (guardian)
- `cron/routine-alerts`, `health`, `app-version?app=` (APK URLs built from Host), `/apks/*`, `/uploads/*`, `/download` page

## 4. Database blueprint (`schooldb`, 32 tables, InnoDB, FKs enforced)

Core chains:
- `users(1) ──< classes.teacher_id, subjects.teacher_id, routines.teacher_id, guardians via guardian_links`
- `sessions(2) ──< classes.session_id, exam_events.session_id`
- `classes(18) ──< students(11), subjects(258), exams`
- `subjects ──< exams(39), routines(1), ct_marks, student_subjects(90)`
- `exam_events(7) ──< exams(39) ──< marks(6); exam_events ──< results(2); promotions`
- `students(11) ──< attendance(8), marks, results, notifications(86), promotions, guardian_links(3), homework(via class)`
- `routines ──< routine_sections/groups, routine_delete_requests(2), routine_notification_log`
- `homework(9)` → class+subject, delivered to guardians via `notifications(type='homework')` + FCM
- `time_slots(9)`, `holidays`, `app_settings(5)`, `device_tokens(11)`, `activity_log`, `exam_shares`, `mark_edit_requests(1)`, `promotion_grace(18)`, `promotion_history`, `class_teacher_requests(2)`, `subject_aliases(36)`, `sessions`

Key enums: `users.role(admin|teacher|guardian)`, `exams.exam_type(class_test|midterm|final|half_yearly|annual|pretest|test)`, `exams.status(draft|submitted|published)`, `exams.source(admin|teacher)`, `exam_events.exam_kind` + `year` + `is_published` + `promotion_linked`, `marks.edit_until` (5h re-edit window), `exams.entry_open/entry_deadline` (1-click permission), `attendance.status`, `notifications(type,target_type)`, `promotions.decision`, `guardian_links.status`.

Origin: schema introspected from Supabase PG and ported to MySQL (`backend/_gen_local_schema.js` reads `C:/tmp/schema.json`; data via `backend/_copy_live_to_local.js`). Future alterations: run guarded `ALTER TABLE` on `schooldb` directly (mysqldump backup first).

## 5. Environment & secrets (.env guard)

`backend/.env` (git-ignored, never commit): `PORT, DB_HOST/PORT/USER/PASS/NAME, DATABASE_URL=mysql://root@127.0.0.1:3306/schooldb, JWT_SECRET, FIREBASE_SERVICE_ACCOUNT_PATH`. Verified: no `.env`/service-account/pem tracked in git. `opencode.json` denies editing secret files. Mobile base URL is build-time `API_URL` dart-define (default LAN `http://192.168.0.112:5000`) + runtime Server-URL override in secure storage (Profile UI hidden per policy — rebuild to change default).

## 6. Tooling & commands

| Task | Command (run on PC) |
|---|---|
| Backend deps | `cd backend && npm install` (node_modules present; run once) |
| Run backend | `node server.js` (needs MariaDB up; `C:\xampp\mysql\bin\mysqld.exe`) |
| DB backup | `C:\xampp\mysql\bin\mysqldump.exe -uroot schooldb > backup.sql` |
| Admin web build | `cd website/admin-site && npm install && npm run build` (copies to `backend/dist/`) |
| Admin lint | `npm run lint` (oxlint installed as devDep — baseline: 14 warnings, 0 errors) |
| Backend check | `npm run lint` → `node lint.js` (32 files syntax gate, zero-dep) |
| Flutter | `flutter analyze` (teacher app: 0 errors; infos/warnings only) |
| OpenCode plugins | `oh-my-opencode@5.1.19` installed globally (multi-agent orchestration); declared in `opencode.json → plugin` |
| MCP servers | `context7` (remote, no key) + `composio` (local npx, needs `COMPOSIO_API_KEY` env) declared in `opencode.json → mcp` |
| Memory | this file (`opencode.json → instructions`); secret-edit deny rules in `opencode.json → permission` |
| Flutter apps | `flutter pub get && flutter analyze && flutter build apk --release --dart-define=API_URL=...` |
| Tunnel | `C:\Users\WALTON\cloudflared.exe tunnel --url http://localhost:5000` |

MCP/Context7/Composio: `context7` works keyless; `composio` requires `COMPOSIO_API_KEY` in the shell environment before starting opencode (without it the MCP logs an error but opencode still starts). Memory = this file (referenced from `opencode.json → instructions`). After any `opencode.json` change: quit + restart opencode.

## 7. Deployment reality (local-first)

Laptop = server (MariaDB + Node :5000, Startup autostart). LAN: `http://192.168.0.112:5000` (needs one-time Windows Firewall allow — requires admin). Public: Cloudflare quick-tunnel URL (rotates; bake into APK or set via app Server screen). APKs + versioned copies in `backend/apks/`, served + listed at `/download`. In-app update compares installed vs `/api/app-version` (live: teacher 1.3.6, guardian 1.3.2, admin 1.3.0). Full operator guide: `README_LOCAL_SERVER.md`. Legacy cloud docs (`DEPLOY_STEPS.md`, Supabase/Vercel) are **stale** — local is source of truth.
