# Promotion, section merit, and religion-aware routine

Updated: 2026-10-24

## Verified in the code and changed in this pass

1. **Class 8 → Class 9 waiting queue:** the first promotion destination is a
   single `Class 9 / Pending Group` class. The group queue is shared by Admin
   and Class 9 stream teachers. The list now sorts by result grade, then total
   marks; exact ties use a stable event/student hash so the system's random
   choice does not reshuffle on every refresh. Old published events are
   excluded from the current pending queue by destination session.
2. **Group selection:** selecting a student opens Arts/Commerce/Science. Arts
   requires Civics or Economics first, then an optional choice; Commerce offers
   Agriculture or Home Science; Science offers Higher Mathematics, Agriculture,
   or Home Science. The API validates the choices, preserves prior subject
   allocations, records the group choice, then moves the student into that
   Class 9 stream and ranks rolls by grade then total marks.
3. **Section allocation:** the merit-balancing engine already split promoted
   students evenly, but the Admin status Calculate/Execute path was not using
   it. Calculate now reviews all event-participating sibling sections together;
   Execute spreads arrivals across destination sections with the remainder in
   the first sections and then numbers rolls from 1. Class 8 remains the
   intentional exception: all promoted students go to Pending Group.
4. **Two result positions:** publish-time result materialization now ranks by
   grade, then total marks, with a stable random-looking tie-break. It records
   section rank and class/group-wide rank for all sections in the event. Admin
   result views/PDFs and the Guardian result card/PDF show both positions and
   their cohort sizes. New `section_size` and `combined_size` columns keep those
   denominators stable after a student changes class.
5. **Religion-aware routine:** Teacher and Admin routine forms now require one
   or more religions for a religion subject. The scope is stored per routine;
   teacher mark-entry student lists and Guardian routine views filter by the
   student's religion. Four choices are supported: Islam, Hinduism, Buddhism,
   and Christianity.
6. **Publish safety:** removed automatic Class 10 movement from the Test publish
   handler. Publishing makes results available; class promotion stays a
   separate reviewed/admin-executed action.
7. **Build resource limits:** Admin and Guardian Gradle settings had requested
   an 8 GB heap on a 7 GB host. All three Android projects now cap Gradle at a
   2 GB heap, 1 GB metaspace, four JVM processors, and two workers.

## Remaining work before calling this production-ready

1. **P0 — database release:** A read-only connection to the configured
   PostgreSQL database succeeded. Its schema currently lacks
   `routine_religions`, `results.section_size`, and `results.combined_size`.
   The additive migration is ready, but no environment is confirmed as a
   restored staging copy, so no DDL was applied. Back up/restore staging, apply
   the migration there, and verify foreign keys and existing routine rows
   before production.
2. **P0 — promotion safety:** Exercise the promotion workflow against realistic staging data: multiple
   Class 6/7/8 sections, even and odd promoted counts, equal-grade/equal-mark
   ties, retained students, Class 8 Pending Group, retry/concurrent approval,
   and each stream/subject choice. Confirm destination roll uniqueness and
   historical results after session changes.
3. **P1 — publish rules:** The Annual/Test publish-time fail-subject checklist is still not complete.
   It must include mandatory subjects, exclude Class 9/10 optional subjects,
   leave raw marks/GPA intact, label special promotion, and never auto-promote
   absent or incomplete results.
4. **P1 — exception workflow:** The Admin class-wise Non-promoted list and the teacher's own-class list with
   Promote/Retain actions and reason capture are still not complete. Admin-only
   reasoned special promotion for absent/incomplete results must remain a
   separate explicit decision.
5. **P1 — app/release QA:** Release APKs were rebuilt from the current project
   source on 2026-10-24. APK signature, package ID, version/build, and SHA-256
   were verified; all three currently use the same Android Debug certificate.
   Do not distribute these as production updates. A staging-data PDF layout
   review and organization-signed build remain outstanding. Analyzer completed
   without compile errors; it reported 32 Admin, 52 Teacher, and 3 Guardian
   lint/style notices. Teacher release build emitted a Kotlin Gradle Plugin
   compatibility warning for `flutter_timezone`; Admin and Guardian warned for
   `file_picker`/`package_info_plus` and `package_info_plus`, respectively.
6. **P2 — production release:** Production Vercel/Supabase state, secrets, backup restore, APK release
   signatures, and download metadata remain unverified. Do not deploy until the
   migration is applied and staging checks pass.

## Deployment and data safety

No production data, schema, APK storage, or deployment was changed in this pass.
Existing session/history rows and student subject allocations are preserved.
The only required database operation is the new additive migration, which must
be staged and backed up before approval for production use.

## Current Android build verification — 2026-10-24

| App | Package | Version/build | Size | SHA-256 | Signing certificate |
|---|---|---:|---:|---|---|
| Admin | `com.school.admin_app` | `1.4.5+10` | 63,259,915 bytes | `6B60DF04DD8125D6E87E789B5F08FA20668AF373E85BC8ACF49AF896C2D4D86D` | Android Debug (`e6399fd012797c6a…`) |
| Teacher | `com.school.teacher_app` | `1.4.6+2003008` | 65,527,803 bytes | `5A0C7DCA794E94FCE02A788F6D236C723D6D07D678DCFFBFA3E38A80D92482D8` | Android Debug (`e6399fd012797c6a…`) |
| Guardian | `com.school.guardian_app` | `1.4.4+11` | 60,629,655 bytes | `8CBE6A672CDF38786FA52292240D030CD8FB9D94F6081FE6727BDA4FFBBE7D4` | Android Debug (`e6399fd012797c6a…`) |

APK paths are under each app's `build/app/outputs/flutter-apk/app-release.apk`.
The previous APKs were copied to `release_builds/20261024/*_original_before_rebuild/`
before the builds. The shared debug signing identity means these artifacts
cannot be certified as updates to the existing organization-signed installs.
