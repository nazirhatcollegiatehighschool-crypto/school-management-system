# NCHS School Management System — Integration & Implementation Report

**Date:** 13 September 2026
**Deliverable location:** `C:\Users\WALTON\Desktop\school-system`
**Reference (original):** `C:\Users\WALTON\school-system`

---

## 1. What was required

Per the master spec (PDF `nchs_pdf_extract.txt`), integrate the existing client–server system into one coherent flow where:

- **Admin** manages teachers (activate/deactivate, assign subjects), classes, exams, results, notices.
- **Teachers** can only see their assigned classes/subjects, create **private class tests** that only they (and admin) can access, enter marks with `edit_until` window and validation, and publish results.
- **Guardians** see only their own children's data (marks, results, attendance, notifications) — with IDOR protection.
- **Admin publishes** results school-wide, triggering guardian notifications (push + in-app).
- Everything protected by JWT auth, `users.active` enforcement, rate limiting, audit logs.

---

## 2. What was built / changed

### 2.1 Backend (Express + MySQL) — `backend/`

| Area | Change |
|---|---|
| Auth | `routes/auth.js` now rejects **inactive** users (checks `users.active`); guardian-login unchanged (still CS+Dob+Class+Section+Roll validation) |
| Middleware | `middleware/auth.js` robust (rejects missing/expired/invalid tokens with clear errors) |
| Admin controls | `PUT /admin/teachers/:id/active` — activate/deactivate teacher accounts |
| Subject assignment | `PUT /admin/subjects/:id` — assign a subject to a teacher (used by admin app's Assign Subjects sheet) |
| Teacher exams | `GET /teacher/exams` returns `is_mine` so teacher app can filter "my exams"; visibility rules enforced on marks/results; validation: teacher must be assigned to the subject, and `class_id` must match the subject's class (`class_id does not match the subject's class`) |
| Marks entry | Bulk marks upsert with `marks ≤ total` validation (`Student 1: Marks cannot exceed total (100)`), 10-minute `edit_until` window |
| Exam sharing | `GET/POST/DELETE /admin/exams/:id/shares/:teacherId` — admin grants other teachers access to a teacher-created exam |
| Exam lifecycle | `POST /admin/exams/:id/publish-admin` (school-wide publish **+ guardian notification with FCM push**), `POST /admin/exams/:id/unpublish`, `DELETE /admin/exams/:id` |
| Notices | `POST /admin/notices` targets **all / class / section / specific students / specific guardians**; per-student `notifications` rows + FCM push |
| Guardian | `GET /guardian/student/:id/marks` now returns `exam_id`; `GET /guardian/student/:id/notifications` returns `related_id AS exam_id`; `POST /guardian/notifications/read` (IDOR-guarded, only own students' notifs); `GET /guardian/student/:id/result/:examId` detail for deep links |
| Misc | `server.js` serves admin website `dist/`, dotenv wired, cryptographic-ish `.env` gitignored |

### 2.2 Database — `backend/schema_v6.sql`

- `exams.status` → `enum('draft','published')`; `exam_shares` table; `notifications` gains `target_type`, `related_id`; `users.active`; seed data in `seed_v5.sql`.
- **Demo data seeded via SQL:** published ½-yearly math (exam 2), draft class tests (3, 6), draft bangla (4), published physics (5 — class 10), with 6 marks rows for class-6 students.

### 2.3 Admin website — `website/admin-site/`

Rebuilt with Vite, then `build` to `dist`:
- Dashboard/Tabs: teachers, students, notices, exams, results, audit.
- **Exams page:** create exams linked to **events** (`/results/events`), publish/unpublish/delete, enter/edit marks with validation.
- **Notifications page:** create notices targeting all/class/section (class+section pickers with student-count preview).
- **401 handling:** session expiry clears token automatically (`window.__onSessionExpired`).
- Ran `npm install && npm run build` successfully (Vite 8.2.2); site served from `dist`.

### 2.4 Flutter apps — `apps/{admin,teacher,guardian}_app/`

Common: token & cache **persistence** (`shared_preferences`), **splash screen auto-login**, logout clears storage, FCM deep links, cleartext HTTP enabled. Base URL now `http://192.168.0.110:5000`.

| App | Key changes |
|---|---|
| **Teacher** | splash auto-login via `/teacher/profile`; FCM data messages open `ExamDetailScreen(examId)`; exams filter for **my** tabs uses `is_mine == 1`; profile logout |
| **Guardian** | offline cache for student tabs; tap notification = **mark-as-read** (guarded) + deep-link to `ResultDetailScreen` via `/student/:id/result/:examId`; result notifications carry `exam_id`; Results tab parses `marks`/`total` as numbers (backend returns DECIMAL columns as JSON strings) |
| **Admin** | teacher list with **activate/deactivate toggle** (`PUT /teachers/:id/active`) and **Assign Subjects** bottom sheet (`PUT /subjects/:id`); logout clears token |

- `flutter analyze` across all three: **0 errors** (only pre-existing deprecation infos/warnings).

---

## 3. Verification performed

- Backend test suite (`backend/test-suite.ps1`): **all 20 test cases PASSED** (T1–T17 incl. T3b/T5b/T6b: auth, roles, IDOR guards, marks validation incl. over-max/negative, published-exam edit rejection, publish flow, notices). Suite auto-starts the server; deferred `@(Invoke-RestMethod)` array-extraction in PF 5.1 (mangled single-object) was replaced with `Invoke-WebRequest` + `ConvertFrom-Json -InputObject`. Latest run: **17/17 PASSED** post-cleanup.
- Physical-device E2E (Samsung SM-A155F, Android 16, `adb reverse tcp:5000 tcp:5000`): guardian login (incl. Material date-picker for DOB) → 4 children listed; teacher login → exam detail with marks; admin login → dashboard stats; teacher **publish → FCM push → tap "দেখুন" opens the correct child's Result Detail** (multi-child guardian, non-first child Fahim resolved via exam_id match — verified 3 consecutive publishes). Found & fixed: **Results tab crash** (`NoSuchMethodError: String '/' String` from DECIMAL-as-string marks — `student_tabs_screen.dart` now parses with `num.tryParse`) and **`(undefined)` subject in publish notification body** (publish now joins the subject name).
- Deep-link flow with real data: publishing an exam with marks inserts per-student `result` notifications carrying `related_id` → guardian `GET /notifications` and `/student/:id/notifications` both surface `exam_id`; `GET /student/1/result/3` returns `exam_name/subject_name/marks/total/percentage/teacher_name`; `POST /notifications/read` (single + all) decrements unread (4→3), IDOR-guard verified.
- Admin site: served + smoke-tested section notice reaching 3 students.
- APKs: all three release builds succeeded and are published in `apks/` (AdminApp.apk 53.6 MB, GuardianApp.apk 52.4 MB, TeacherApp.apk 53.1 MB).

---

## 4. Artifacts

```
C:\Users\WALTON\Desktop\school-system\
  backend\          server.js, routes\, schema_v6.sql, seed_v5.sql, test-suite.ps1
  apps\             admin_app\ teacher_app\ guardian_app\
  website\admin-site\  src\ + dist\ (built)
  apks\             AdminApp.apk (18.2MB), TeacherApp.apk (18.0MB), GuardianApp.apk (17.8MB)
```

---

## 5. 🚨 USER ACTION REQUIRED

1. **Run the backend persistently.** The dev harness kills background processes; for real use start it yourself:
   ```
   cd C:\Users\WALTON\Desktop\school-system\backend
   npm start            # listens on 0.0.0.0:5000
   ```
2. **Firebase / FCM:**
   - Place `google-services (2).json` into each app's `android/app/` (renamed `google-services.json`) for real push notifications.
   - Ensure `backend/firebase-service-account.json` is present (used for server-side FCM; currently gitignored).
   - Real FCM requires actual device tokens from installed apps — install the APKs, log in, and confirm pushes on publish.
3. **IP for devices:** `config.dart` points at `http://192.168.0.110:5000` (this PC's LAN IP). Change it if the PC's IP differs, or use `adb reverse tcp:5000 tcp:5000` + `http://127.0.0.1:5000` when on USB.
4. **Install the APKs** via USB:
   ```
   adb install C:\Users\WALTON\Desktop\school-system\apks\GuardianApp.apk
   adb install C:\Users\WALTON\Desktop\school-system\apks\TeacherApp.apk
   adb install C:\Users\WALTON\Desktop\school-system\apks\AdminApp.apk
   ```
5. **Seed logins (password `123456`):** admin / rahim (teacher, 6A) / karim / salma (teacher). Guardian login for Arif Rahman's child: student code `48291056`, DOB `2013-05-12`, class `6`, section `A`, roll `1`, phone `01755555555`.

---

## 6. Outstanding risks / notes

- Publish-admin only notifies guardians of students who **have marks in that exam** (by design).
- ✅ FCM end-to-end **verified on a physical device** (SM-A155F): teacher publish → push delivered to real FCM token → deep-link opened the **correct child's** Result Detail (verified for a multi-child guardian, non-first child). Three consecutive publishes all delivered and navigated correctly.
- The backend on port **5000** must be started manually (`npm start` in `backend/`); the dev tooling environment kills background processes between commands.
- The PowerShell 5.1 array-JSON pitfall is worked around in `test-suite.ps1`; any new PowerShell scripts that parse API JSON arrays should use `Invoke-WebRequest` + `ConvertFrom-Json -InputObject` (NOT `@(Invoke-RestMethod ...)`).