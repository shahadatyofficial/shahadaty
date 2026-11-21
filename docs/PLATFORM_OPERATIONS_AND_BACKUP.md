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
