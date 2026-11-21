# Platform operations, integration checks, and backup boundaries

This document describes the current verified route connections and the operational backup boundary for the live Shahadaty project.

## Connected workflows tracked by CI

- Institution administration: approval/listing, package and subscription review, and payment confirmation RPCs.
- Institution workspace: branches, staff invitations/roles, course runs, attendance, certificate issuance, and automatic graduate-account creation.
- Graduate portal: profile publication consent, private Gold uploads, certificate retrieval, job applications, and application withdrawal.
- Company portal: approved-company alumni search, access requests, consent-gated contact/document access, job ads, and application review.
- Admin support: visitor conversations, message replies, read state, and conversation status.
- The CI integration guard checks that these route-to-backend integration points and their tracked migrations remain present. It does not create or mutate production data.

## Database backups

Open the Supabase-managed backup page for this project:

https://supabase.com/dashboard/project/snteiiavvaaumgaegazn/database/backups

Review the backup schedule, retention period, and the most recent successful backup in the Supabase dashboard. Availability and retention depend on the project's Supabase plan and configuration.

**Important boundaries**
- A database backup is not a complete copy of Storage object bytes. Private uploaded files in buckets such as `institution-documents`, `alumni-private`, `graduate-gold-private`, and `graduate-payment-proofs` need a separate object-backup process.
- A spreadsheet report export is not a restorable database backup.
- Restoring a database backup can replace current database state. Do not trigger restore as a routine test; it requires a separate, explicit operational decision and a recovery window.
- This repository/connector does not currently have a configured database-dump credential or an object-storage backup destination. Therefore no automated off-site backup job is claimed or enabled by this change.

## Production-safe verification

- CI performs syntax checks and structural integration regression checks.
- Read-only production introspection can confirm schema, RLS policies, bucket privacy, migration state, and row counts.
- No synthetic accounts, certificates, job applications, support conversations, or other test rows are to be inserted into production.
- End-to-end login and cross-account authorization tests require authorized real accounts and must be performed with explicit controlled test identities, not fabricated production records.

## Andalus Center pilot — 2026-11-21

- Code baseline before the pilot: commit `0e5def5a58ce315c5a9d63c97cceac1a45cfa621`, preserved on branch `baseline/2026-11-21-pre-andalus-pilot`.
- Pilot development branch: `pilot/andalus-center-2026-11-21`.
- The existing approved institution record for **مركز الاندلس للتدريب** is reused; do not create a duplicate institution.
- The pilot readiness panel is read-only and counts the center's existing branches, team, trainees, courses, groups, trainers, sessions, enrollments, attendance, and certificates.
- No production rows, migrations, Auth users, storage objects, or Edge Functions are created or changed by this pilot UI update.
- Initial read-only snapshot: 1 active team membership, 0 branches, 1 trainee, 0 courses, 0 course runs, 0 trainers, 0 sessions, 0 enrollments, 0 attendance rows, and 1 certificate.
- Code rollback: revert the pilot PR/merge commit and redeploy the prior `main` version. The preserved baseline branch identifies the exact pre-pilot source commit.
- Database caution: code rollback does not erase operational records entered by the center during the pilot. Do not bulk-delete those records or restore the whole production database as a shortcut; any data cleanup requires a separate reviewed, center-scoped decision and a verified backup.
- Before real staff enter new business records, confirm the latest successful Supabase database backup and arrange separate backup for private Storage objects. This pilot has not triggered a restore or claimed a new backup.
