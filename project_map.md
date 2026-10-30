# School System — Project Map

> **Historical audit (2026-10-25).** Current operational status, schema (62 tables), mirror/backup state and feature status are maintained in [PROJECT_GUIDE_BN.md](PROJECT_GUIDE_BN.md). Do not treat the blockers below as current without re-checking.

Last reviewed: 2026-10-25 (fresh release audit). This guide maps the local source tree, primary data paths, and verified production deployment metadata. It does not certify release readiness; see `docs/AUDIT_RELEASE_STATUS_2026-10-25.md` for the latest decision.

## Repository at a glance

```text
apps/
  admin_app/       Flutter app for school administrators
  teacher_app/     Flutter app for teachers and Class Teachers
  guardian_app/    Flutter app for guardians
  release_builds/  isolated local review APK/PDF/build outputs
backend/
  server.js        Express API, middleware, health checks, and cron handlers
  api/index.js     Vercel function wrapper that exports server.js
  routes/          role-scoped API route handlers
  lib/             shared domain helpers
  migrations/      hand-maintained SQL migration variants
  prisma/          Prisma schema and migration history (not the full runtime schema)
  test/            isolated Node regression tests
docs/              reliability, release, and operational notes
release_builds/    retained earlier APK backups and audit PDFs
vercel.json        repository-root deployment config
```

The connected Vercel project is `school-management-system`; read-only inspection confirmed repository root (`.`), so root `vercel.json` is authoritative. `backend/vercel.json` conflicts and must not be treated as active unless the Vercel root setting changes. Current root config bundles mutable APK pointers and declares three cron routes. Flutter apps call `/api/...` using `Config.api` and may override the server URL in app settings. Offline cache and write replay live in each app's `lib/sync_store.dart`; replayed mutations must be safe against retries and duplicates.

Production read-only checks on 2026-10-25 returned `/api/health` status `ok`, database `connected`, and old app metadata: Admin 1.4.5+10, Teacher 1.4.6+2003008, Guardian 1.4.4+11. Current local candidate metadata is Admin 1.4.6+11, Teacher 1.4.7+2003009, Guardian 1.4.4+11. Admin and Teacher production versions therefore do not match current local candidates. No production deployment was made in this audit. Vercel production variable *names* inspected without reading values: `CRON_SECRET`, `DATABASE_URL`, `DIRECT_URL`, `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `VERCEL_UPLOAD_DIR`, `FIREBASE_SERVICE_ACCOUNT_PATH`, and `PORT`.

## App navigation and feature ownership

### Admin app

Navigation is assembled in [home_screen.dart](apps/admin_app/lib/screens/home_screen.dart). The screen-to-feature map is:

| Home option | Main screen | Main API/data owner |
|---|---|---|
| Students | [students_screen.dart](apps/admin_app/lib/screens/students_screen.dart) | `/api/admin/students`; `backend/routes/admin.js` |
| Teachers | [teachers_screen.dart](apps/admin_app/lib/screens/teachers_screen.dart) | `/api/admin/teachers`; `backend/routes/admin.js` |
| Classes | [classes_screen.dart](apps/admin_app/lib/screens/classes_screen.dart) | `/api/admin/classes`; class rows, sections/groups, Class Teacher assignment and student count |
| School Exam · Class 6–10 | [exam_center_screen.dart](apps/admin_app/lib/screens/exam_center_screen.dart), [exam_dashboard_screen.dart](apps/admin_app/lib/screens/exam_dashboard_screen.dart), [exam_catalog_screen.dart](apps/admin_app/lib/screens/exam_catalog_screen.dart) | `/api/admin/...` exam routes; `backend/routes/admin.js`, `backend/routes/results.js`, `backend/lib/exam_dashboard.js`, `backend/lib/exam_progress.js` |
| Results | [results_screen.dart](apps/admin_app/lib/screens/results_screen.dart) | `backend/routes/results.js`, `backend/grading.js`, `backend/lib/exam_progress.js` |
| Routines | [routines_screen.dart](apps/admin_app/lib/screens/routines_screen.dart) | `backend/routes/routine.js` |
| Attendance | [attendance_screen.dart](apps/admin_app/lib/screens/attendance_screen.dart) | `backend/routes/attendance.js`, `backend/attendance_v2.js` |
| Notices, approvals, promotion, settings | `notices_screen.dart`, `approvals_screen.dart`, `promotion_screen.dart`, `settings_screen.dart` | Primarily `backend/routes/admin.js`; role and validation rules are server-side |

Student profile edit is a cross-layer feature. The Admin form sends `PUT /api/admin/students/:id`; the backend route is in `backend/routes/admin.js`, and allowlisted partial-update construction is in `backend/lib/student_update.js`. The Class Teacher form sends `PUT /api/teacher/students/:id`, authorized against the student's assigned class in `backend/routes/teacher.js`. PostgreSQL `BOOLEAN` columns must receive booleans (`true`/`false`), not integer `1`/`0`; this matters for `birth_cert_placeholder` and `receives_scholarship`. For Classes, the screen edits `name`, `section`, `group_name`, and `teacher_id`; validation/normalization is in `backend/lib/class_management.js`. Class 9–10 must retain a valid academic group (Arts/Humanities, Science, or Commerce/Business). Do not remove `group_name` from edit requests.

### Teacher app

Main navigation and dashboards are in `apps/teacher_app/lib/screens/home_screen.dart` and `dashboard_screen.dart`.

| Feature | Main UI | Main API/data owner |
|---|---|---|
| Class list and attendance | `class_students_screen.dart`, `attendance_screen.dart`, `attendance_analytics_screen.dart` | `/api/teacher/...`, `/api/attendance/...`; `backend/routes/teacher.js`, `backend/routes/attendance.js`, `backend/attendance_v2.js` |
| Student profile/history | [student_profile_screen.dart](apps/teacher_app/lib/screens/student_profile_screen.dart), `student_progress_screen.dart` | `/api/teacher/students/:id` and profile/history routes in `backend/routes/teacher.js` |
| Class Teacher registration | `student_registration_screen.dart` | `POST /api/teacher/students`; server checks assigned class |
| Exams and marks | `event_list_screen.dart`, `event_detail_screen.dart`, `exams_screen.dart`, `exam_detail_screen.dart`, `create_exam_screen.dart` | `backend/routes/teacher.js`, `backend/routes/results.js`, `backend/lib/exam_progress.js` |
| Routine and “Who is free” | `routine_screen.dart`, `who_is_free_screen.dart` | `backend/routes/routine.js` |
| Homework and OCR | `homework_screen.dart`, `ocr_capture_screen.dart` | Teacher routes and app-side OCR flow |
| Promotion review | `promotion_screen.dart` | UI currently selects published Annual (Classes 6–9) and Test (Class 10) events and loads `/api/teacher/promotion/review`; a teacher grace-limit route exists. Admin has separate preview/decision/execution/history/report endpoints under `/api/admin/promotion/*`. Per-subject fail exceptions and equivalent Class Teacher preview/decision/execution/history are not complete. |
| Offline status and queued writes | `widgets/offline_sync_banner.dart`, `lib/sync_store.dart` | App-side queue; backend mutations must be idempotent |

Class Teacher student edits use `PUT /api/teacher/students/:id`; backend checks the student's assigned class in `backend/routes/teacher.js`. A server error after the `UPDATE` can otherwise be ambiguous, so check both the route's response and the subsequent read before retrying a real record.

### Guardian app

Navigation is in `apps/guardian_app/lib/screens/home_screen.dart` and `student_tabs_screen.dart`. Student switching/sibling requests are in `add_sibling_screen.dart`; result and activity PDFs are in `marksheet_screen.dart` and `lib/pdf/`. Guardian data access is scoped in `backend/routes/guardian.js`; do not replace that scoping with client-only filtering.

## Backend request path

1. `backend/server.js` creates the Express app, security/rate-limit middleware, cron authorization, and health endpoints.
2. Role routes are mounted below `/api`: `auth`, `admin`, `teacher`, `guardian`, `results`, `routine`, and `attendance`.
3. Authentication is in `backend/middleware/auth.js`; production JWT configuration fails closed when its secret is missing. Cron handlers require the configured cron secret.
4. Route handlers use the compatibility pool in `backend/db.js` and primarily issue raw SQL using `?` placeholders.
5. Shared logic belongs in `backend/lib/` (exam dashboard/progress, student activities, curriculum, school logos/signatures, and student/class update helpers).

`backend/api/index.js` simply exports the Express app for Vercel. The runtime API is therefore the server app plus route modules, not a separate generated REST layer.

## Data model, sessions, and migrations

- Runtime tables and SQL expectations live across `backend/schema_optimized.sql`, `backend/migrations/`, route SQL, and migration scripts in `backend/`.
- The missing `routine_religions`, `results.section_size`, and `results.combined_size` objects have idempotent dialect-specific migration source under `backend/migrations/mysql/` and `backend/migrations/postgres/`. These files are preparation only; they have not been applied to the connected database.
- [Prisma schema](backend/prisma/schema.prisma) is useful for validation and generation but is a partial map of the raw-SQL runtime schema; do not assume `prisma migrate deploy` manages every table.
- [db.js](backend/db.js) supports PostgreSQL/Supabase as the intended production target plus a limited MySQL compatibility adapter. Translation is not full dialect equivalence; new SQL needs tests in both supported paths before claiming compatibility.
- Exam/session catalog and result lifecycle live primarily in `backend/routes/results.js`, `backend/exam_catalog.js`, `backend/lib/exam_dashboard.js`, and `backend/lib/exam_progress.js`.
- Current-session reconciliation and canonical exam creation are idempotent paths in `backend/routes/results.js` and `backend/server.js`; the scheduled endpoint is `/api/cron/academic-session`.
- Promotions and group moves are in `backend/promotion_engine.js` and promotion routes in `backend/routes/admin.js` / `backend/routes/teacher.js`.
- Attendance and activity flow spans `backend/attendance_v2.js`, attendance routes, `backend/lib/student_activities.js`, and the three app PDF generators.

**Database safety:** use only read-only inspection until a disposable staging database restored from a known backup is explicitly identified. Never use real student records as fake-data test fixtures. No migration should run from server startup or an HTTP request. Keep schema changes ordered, immutable, checksummed, and tested on restored staging before deployment.

## PDFs and activity pagination

- Shared subject marksheet row/layout helpers: `apps/admin_app/lib/pdf/marksheet_template.dart`, `apps/teacher_app/lib/pdf/marksheet_template.dart`, `apps/guardian_app/lib/pdf/marksheet_template.dart`.
- Admin/Teacher result PDF builders: `apps/admin_app/lib/pdf/admin_pdfs.dart`, `apps/teacher_app/lib/pdf/teacher_pdfs.dart`.
- Guardian result PDF screen: `apps/guardian_app/lib/screens/marksheet_screen.dart`.
- Teacher regression fixture: `apps/teacher_app/test/exam_marksheet_pdf_test.dart` covers the 35-student page boundary and long daily-activity pagination using synthetic in-memory data.

## Build and release

- App version/package settings: each app's `pubspec.yaml`, Android Gradle files, and `Config`/API client.
- Android release signing is configured in all three `android/app/build.gradle.kts` files to require the local organization signing environment for release builds; debug signing remains available for debug variants. A new local release identity is at `.release-signing/school-system-release.jks`; its password is stored as Windows DPAPI-protected data in `.release-signing/password.dpapi`. The directory is excluded from Git and Vercel packaging. Use `scripts/build_release_apks.ps1` to build signed APKs without putting the password in source or chat. This is a newly created signing identity, not a recovered pre-existing organization or Play App Signing key; retain secure offline backups or future updates cannot be signed if this key is lost.
- Local review APKs/backups are retained under `apps/release_builds/` and `release_builds/`. Do not overwrite or delete them without a verified copy and retention decision.
- Android install uses data-preserving `adb install -r` only after package/version/certificate checks. A signing mismatch must never be resolved by uninstalling or clearing app data.
- Current review APKs use a newly generated local release identity, not a recovered organizational or Play App Signing identity. Treat them as review candidates until the owner confirms the identity is suitable for permanent distribution. Never read or disclose its DPAPI-protected password.

## Deployment configuration and current blocker

- Repository-root [vercel.json](vercel.json) builds `backend/server.js`, bundles the Admin/Teacher/Guardian APKs, and declares cron routes.
- [backend/vercel.json](backend/vercel.json) instead targets `backend/api/index.js` and does not declare the same build/include/cron configuration.
- Vercel project and root are confirmed by read-only CLI inspection: `school-management-system`, root `.`. The root config is active; `backend/vercel.json` conflicts. Deployment remains blocked pending staging restore/migration verification and authenticated smoke tests.
- App default API URL is configured in each `lib/config.dart`; a runtime server override is stored locally in app preferences.
- Backend environment variable names are defined/used in code and deployment settings (for example `DATABASE_URL`, `DIRECT_URL`, `JWT_SECRET`, `CRON_SECRET`, and pool/SSL controls). This map intentionally contains no values.

## Tests and useful local checks

Run backend checks from `backend/`:

```text
npm run lint
node --test test/*.test.js
npx prisma validate
```

Run Flutter checks from each app folder after dependencies are available:

```text
flutter analyze --no-pub
flutter test
flutter build apk --release --no-pub
```

Only run DB-backed tests against an explicitly disposable database. The current DB connection could not be verified as staging and the schema is missing required objects (`routine_religions`, `results.section_size`, and `results.combined_size`); do not run migrations against it.

## Known open release blockers (2026-10-25)

1. Identify a restorable disposable staging DB and run role, marks-publish, promotion, session/lock, and route-level fake-data tests there.
2. Complete the requested per-subject promotion policy and equivalent Class Teacher promotion execution/history flow.
3. Confirm and reconcile the schema gaps on staging; do not migrate the configured live/unknown database.
4. The Vercel project/root has been identified. Reconcile the conflicting backend config and root build/runtime settings, then deploy only after staging DB verification and run authenticated smoke checks. Production environment variable names were inspected without revealing values; `CRON_SECRET` was added as a sensitive production variable and takes effect only after a deployment.
5. Use the organization's established signing key through secure local configuration, rebuild all three apps from the final source, and verify package/version/hash/certificate.
6. After production deployment and smoke checks, install the final signed apps on an authorized device and exercise profile update, Classes, attendance, marks, and Guardian result flows without fabricated production records.

Until these steps pass, this repository is **not fully production-ready**. The latest profile and Classes source changes are local review work and have not been deployed. The latest Admin review APK is available at `apps/release_builds/review_20261025_final/admin-app-release.apk`; Teacher latest-source review build could not be completed in the current environment. Neither review APK is organization-signed or suitable for production distribution.

## Complete feature inventory and latest live observations (2026-10-25)

The screen-file inventory below is cross-referenced to the feature/API ownership map above. At a glance, Admin has 19 screens covering identity/roster/teacher/class management, exams/results, attendance/routines, notices/approvals, sibling requests, promotion/settings and audit logs; Teacher/Class Teacher has 21 screens covering profile, class/student workflows, registration, attendance, exams/marks, schedules, homework/OCR and promotion review; Guardian has 6 screens covering login, student/sibling selection, published results and marksheets. Their API owners and role-scoping points are mapped above and in the audit report.

The public production alias `school-management-system-brown-mu.vercel.app` remains on Admin 1.4.5+10, Teacher 1.4.6+2003008 and Guardian 1.4.4+11. Health returned `ok/connected`. All three served production APK bytes matched the public version endpoint's SHA-256. Unauthenticated role API requests returned 401. However, an unauthenticated request to the deployed academic-session cron returned 200 and invoked current-session sync; the local source's `authorizeCron` guard is therefore not evidence of deployed protection. Preview deployment URLs returned a Vercel login page, not API responses.

Backend lint (79 files), backend tests (17/17), Prisma validation and local APK metadata/signature verification passed. Full Flutter analyzer commands hung without output and were interrupted. A disposable PostgreSQL cluster could be initialized locally, but its client connection was denied, so fake-student database tests and migration rehearsal remain unverified. Production backup/staging evidence is still missing. The profile-update source fix is local only. No phone install was performed, no migration was run, and no fake student was written to production.



Security follow-up: the working tree has been sanitized of hard-coded PostgreSQL URLs; old reset scripts refuse writes; the legacy admin database-sync API is disabled and excluded from Vercel packaging. Git history still contains prior committed credential-bearing files, so rotate the old database credential and scrub/publish a clean repository history before claiming secret-clean release status. No history rewrite or force-push has been made.

Exact screen-file inventory:

- Admin: `approvals_screen`, `attendance_screen`, `classes_screen`, `delete_logs_screen`, `exam_catalog_screen`, `exam_center_screen`, `exam_dashboard_screen`, `exams_screen`, `home_screen`, `login_screen`, `notices_screen`, `promotion_screen`, `results_screen`, `routines_screen`, `settings_screen`, `sibling_request_screen`, `splash_screen`, `students_screen`, `teachers_screen`.
- Teacher/Class Teacher: `attendance_analytics_screen`, `attendance_screen`, `class_students_screen`, `create_exam_screen`, `dashboard_screen`, `event_detail_screen`, `event_list_screen`, `exam_detail_screen`, `exams_screen`, `home_screen`, `homework_screen`, `login_screen`, `ocr_capture_screen`, `profile_screen`, `promotion_screen`, `routine_screen`, `splash_screen`, `student_profile_screen`, `student_progress_screen`, `student_registration_screen`, `who_is_free_screen`.
- Guardian: `add_sibling_screen`, `home_screen`, `login_screen`, `marksheet_screen`, `splash_screen`, `student_tabs_screen`.


Supabase connection preparation: `.mcp.json` now scopes the official MCP to the owner-provided project reference in read-only database mode. Endpoint reachability returned the expected unauthenticated 401; the active task has no Supabase MCP tools until OAuth authentication/reload. No database data or backup has been accessed through Supabase yet.
