# Database and APK reliability plan

This document describes the safe path to production reliability. It does not
apply migrations, alter production storage, or move existing APK objects.

## Full application audit — 2026-10-23

| Area | Finding | Action / status |
|---|---|---|
| Class 8 → Class 9 | Pending Group queue, shared rank ordering, teacher stream authorization, retries, subject-choice validation and serialized destination roll assignment were present in the working tree. | Kept; backend lint and schema validation are the safe checks available without production data. |
| Guardian history | Published exam history is keyed by event/session and event-class records; older subject allocations are retained when Class 9 choices are added. | Guardian archive is labeled session-wise; no production student data was used for visual verification. |
| API security | Supabase sync handlers had no auth middleware; a public debug endpoint checked a hard-coded password; cron handlers accepted unauthenticated requests; production JWT fell back to a known key if missing. | Sync now requires admin auth, debug URL returns 410, production cron calls require `CRON_SECRET`, and production JWT auth fails closed. Configure `CRON_SECRET` and a strong `JWT_SECRET` in the deployment environment before relying on scheduled jobs/auth. |
| Database | Several legacy SQL migration variants, Prisma PostgreSQL schema, MySQL SQL translation, and request-time schema DDL coexist. Production catalog/backups are not available to this read-only audit. | No live DDL or data changes. Use the single reviewed migration workflow below after staging/baseline/restore validation. |
| PostgreSQL SQL adapter | `INSERT IGNORE` statements were not translated and `DATE_SUB` had no PostgreSQL rewrite. | Fixed both translations and added three isolated regression tests; all pass without connecting to the database. |
| App PDFs | Admin, Teacher, and Guardian app code generates offered PDFs locally after receiving data. | App routes use JSON payloads; server PDF routes remain for compatibility. |
| Android release | App `pubspec.yaml` values match hard-coded API version/build values. Release Gradle configs still sign with the debug key; no release keystore is present in the workspace. | As of 2026-10-24, all three APKs were rebuilt from the current source and package/version/build/hash/signature metadata were verified. They use the Android Debug certificate and were not installed. They are review artifacts only; a safe update over an organization-signed install cannot be certified. Previous local APKs were copied under `release_builds/20261024/` before rebuilding. |
| Device install | Admin and Teacher packages were already on the connected Samsung SM-A155F; Guardian was not. | Admin + Teacher updated with `adb install -r` (data-preserving); Guardian installed. Device reports Admin 1.4.5+10, Teacher 1.4.6+2003008, Guardian 1.4.4+11. |
| Static analysis | Release builds compile all three apps. Flutter analyzer reports 31 Admin, 51 Teacher, and 3 Guardian lint/style notices; no compile errors. Teacher's isolated parser suite passes all 7 tests. | Notices are mostly formatting/deprecation and unused legacy code; they do not block these builds, but should be addressed in a dedicated cleanup after behavior review. |
| Production release | APKs are bundled by Vercel config; a fresh read-only `/api/app-version` request returned HTTP 500 `FUNCTION_INVOCATION_FAILED`. | No production deploy, storage change, or live migration was performed. Investigate Vercel function logs before release. |

## Database backup, retention, and restore

- Keep automated encrypted database backups in a separate account/project from
  the live Supabase project. Retain daily backups for 35 days and monthly
  snapshots for 12 months; retain point-in-time recovery/WAL according to the
  Supabase plan and verify the configured recovery window after plan changes.
- Include students and guardian links, marks/results/exams, attendance,
  student_subjects, promotions, group_selections, promotion_history,
  promotion_runs/section_allocations, and the migration ledger in the backup.
  Do not treat APK files or generated PDFs as a substitute for database records.
- Before every schema release, take and record a restorable snapshot. Run the
  migration against a restored staging copy first; record the migration ID,
  checksum, start/end time, and outcome. Never make serverless cold start run
  DDL or data backfills.
- At least quarterly, restore a backup into an isolated project, compare
  student/marks/attendance/promotion counts and key foreign-key/index checks,
  and confirm that Admin, Teacher, and Guardian read-only flows work. Record
  restore duration and the latest recoverable timestamp. Never test restore by
  overwriting production.

## One migration workflow

The current repository mixes a PostgreSQL Prisma schema, an initial Prisma
migration, many hand-maintained Supabase SQL files, runtime SQL translation,
and request-time schema creation. These are not yet one reliable workflow.
Prisma's schema is also only a partial description of the raw-SQL application's
tables, so `prisma migrate deploy` alone cannot currently manage the whole
database safely.

Adopt ordered, immutable SQL migrations under `backend/prisma/migrations/` as
the sole schema-change source, with a migration ledger, checksums, and a
reviewed migration command run once in CI/release against the PostgreSQL
DIRECT_URL (not Supavisor transaction pooling). Keep Prisma schema in sync with
each SQL migration and use `prisma validate`/`prisma generate` in CI; do not
use `db push`, startup DDL, or an HTTP migration endpoint. First inventory and
baseline the existing Supabase schema, compare all runtime tables, columns,
indexes, unique constraints and foreign keys, and reconcile the baseline in a
maintenance release. Do not change the current production schema until that
baseline and restore have been reviewed.

The MySQL adapter is a separate compatibility mode, not a Prisma-supported
deployment target. The current regex SQL translator only covers a subset of
PostgreSQL syntax: placeholder conversion does not lex comments/quoted
identifiers fully, conflict rewriting assumes simple `EXCLUDED.column`
assignments, `INSERT IGNORE` can hide non-duplicate errors, and PostgreSQL
arrays, `NULLS LAST`, `RETURNING`, date functions, and transaction/locking
semantics need integration coverage. Keep PostgreSQL/Supabase as the supported
production target. If MySQL remains supported, define a separate migration set
and run dialect-specific integration tests for UPSERT, date/time zones,
rollback, uniqueness races, and lock behavior before claiming compatibility.

Vercel uses small per-instance pools (`DB_POOL_MAX`, default 2); calculate the
maximum as instance count times pool size plus migration/admin connections
against the Supabase connection cap. Continue using pooled DATABASE_URL for
runtime and a direct connection only for controlled migrations. A failed
migration must stop release, leave the previous app deployment available, and
be repaired with a forward migration; do not partially swallow errors or
automatically roll back destructive DDL.

## APK object storage/CDN proposal

The current deployment bundles three APKs (about 180 MB combined) through
`vercel.json` `includeFiles`. Keep release builds and APKs outside the Vercel
function bundle. Proposed target: a private S3-compatible object bucket with
immutable version/build-addressed object keys, served through a CDN with
HTTPS. Store object keys, version/build, byte length, and SHA-256 in a
release manifest/API configuration; never accept arbitrary upload paths from
clients.

Migration sequence, requiring explicit approval before any production storage
change:

1. Choose and provision the storage account, region, access policy, CDN domain,
   and retention rules; keep bucket writes private and downloads read-only.
2. Upload each already-reviewed APK to a versioned key without replacing the
   existing Vercel files. Compare size and SHA-256 against the local artifact
   and verify HTTP range/download behavior from the CDN.
3. Update `/api/app-version` to return the immutable CDN URL and checksum;
   validate all three clients' update/install checks against staged objects.
4. Release API metadata first with old links as fallback, then switch links
   after successful download/install verification. Keep old APKs available for
   at least two release cycles and provide a quick metadata rollback.
5. Remove APKs from Vercel `includeFiles` only after the fallback window and
   verify the deployment artifact drops in size. Never delete the source APKs
   until the CDN copy is verified and the owner has approved retention.

No storage provider has been selected or modified by this work.

## Release checks

Admin, Teacher, and Guardian versions/build numbers must come from one release
manifest or be validated against each Flutter `pubspec.yaml` before release.
The backend currently hardcodes these values and points at mutable APK names;
`/api/app-version` hashes whichever files are present at startup. Release CI
should verify APK package IDs, version names/codes, file hashes, metadata URLs,
and that each downloadable artifact matches its manifest. Production checks
must be read-only unless a separately approved deployment applies.

## 2026–future session lifecycle and publish behavior — 2026-10-23

- The Bangladesh calendar year (`Asia/Dhaka`) is the active academic session. The
  scheduled `academic-session` Vercel cron runs at 00:05 Dhaka time; an API
  dashboard read also reconciles the current session as a fallback. Prior
  sessions remain in the session/event tables for historical results.
- Reconciliation now calls the idempotent canonical event provisioner even
  when the session row already exists. This repairs the case where a 2026
  session existed but its five canonical shells did not. The kinds are
  Half-Yearly, Annual, Pre-Test, Test, and Special Model Test. For each year,
  regular annual/half-yearly scopes are Classes 6–9, Pre-Test/Test are Class 10,
  and the model test is SSC Batch. Newly created year scopes remain locked until
  an admin unlocks them. Test promotions and model-test eligibility use the
  destination session, so students moved from Class 9 in 2026 can sit the 2027
  Class 10 Test; verify against the live class/session rows before release.
- Result > Running now lists unlocked, unpublished events only. Publishing
  locks the event row and changes event/exam state in one transaction. A retry
  returns the already-published result. The Annual/Test publish-time
  fail-subject override remains unimplemented. The school rule is now confirmed:
  Annual/Test publish should allow the admin to select failed subjects for
  special consideration, including mandatory subjects, while Class 9/10 optional
  subjects stay outside that list. Absent or incomplete results must not be
  auto-promoted. The publish checklist and explicit reasoned exception flow are
  still outstanding; no override behavior has been released.
- Production database and Vercel environment could not be checked from this
  host: DB hostname lookup returned `ENOTFOUND`, and no Vercel CLI/session is
  available. Consequently no production session repair, secret verification,
  release deployment, or production APK link check was performed.
