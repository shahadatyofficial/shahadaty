# Shahadaty — Repository Audit Notes

Audit date: 2026-11-06  
Repository baseline inspected: `main`  
Audit branch: `development/phase-0-audit`

## Repository inventory
The recursive Git tree for `main` returned 14 tracked files:
- `index.html`, `landing.html`
- `admin.html`, `institution.html`, `register.html`
- `packages.html`, `verify.html`, `certificate.html`
- `graduate.html`, `talent.html`
- `logo.png`
- `sql_setup.sql`, `supabase_admin_hardening.sql`, `fix_missing_rpcs.sql`
- `DEPLOY_PHASE_1.md`

No test suite, package manifest, or GitHub Actions workflow appeared in the returned repository tree. This is a repository-tree observation, not proof that no external deployment or test system exists.

## Frontend RPC inventory
RPC names referenced in the inspected pages:

| Page | RPCs |
|---|---|
| `admin.html` | `is_platform_admin`, `admin_list_institutions`, `admin_approve_institution`, `admin_reject_institution`, `admin_suspend_institution`, `admin_update_institution_quota`, `admin_list_institution_documents`, `review_document`, `admin_list_certificates`, `admin_revoke_certificate`, `verify_certificate`, `admin_list_recruitment_requests`, `admin_update_recruitment_status`, `admin_list_companies`, `admin_update_company`, `admin_platform_stats` |
| `institution.html` | `issue_certificate`, `issue_certificates_bulk`, `verify_certificate`, `update_my_institution_contact` |
| `register.html` | `register_institution` |
| `verify.html`, `certificate.html` | `verify_certificate` |
| `graduate.html` | `graduate_my_certificates` |
| `talent.html`, `packages.html` | No direct `.rpc()` calls detected by the simple source scan |

The current `sql_setup.sql` text contains definitions for 26 public functions, including the above core workflows. A source-level name match does not prove that the deployed database has those functions or that their signatures match the frontend calls.

## Database-script observations
- `sql_setup.sql` contains a `CREATE TABLE` statement for `public.certificate_sequences`; the file also alters/references other application tables. It is therefore not a self-contained clean-install schema.
- `supabase_admin_hardening.sql` contains administrative RPC definitions that call `public.is_platform_admin()`; the inspected text does not create a `platform_admins` table.
- The inspected hardening script relies on an existing authorization helper and existing business tables. It must not be applied blindly to an unknown database state.
- `fix_missing_rpcs.sql` drops and recreates `public_platform_stats()` and `graduate_my_certificates()`. It is a targeted repair script, not a baseline migration.
- The scripts must be reconciled into ordered, idempotent migrations after live schema inspection. Do not run them in their current order on production without that inspection.

## Supabase availability at audit time
Project `snteiiavvaaumgaegazn` reported status `COMING_UP`. A table introspection request failed with a database-not-accessible response. The migration listing returned an empty array. Since the database was not reachable, that empty array cannot be interpreted as proof that no schema or prior SQL changes exist.

The advisor endpoints returned empty lint arrays while the database was still coming up. Treat these as inconclusive; rerun after PostgreSQL is reachable.

## Risks requiring resolution
1. **Admin authorization consistency:** frontend checks, SQL helper implementation, user metadata and the intended first-admin bootstrap must use one database-enforced model. Never trust a browser-only role flag.
2. **Schema drift:** the checked-in scripts assume pre-existing tables and columns. Build a verified live-schema inventory before any DDL.
3. **RPC contract drift:** compare every frontend RPC name, argument and expected return shape with the deployed function signature.
4. **Function security:** inspect every SECURITY DEFINER function for a fixed safe search_path, minimal ownership, input validation and explicit EXECUTE grants; test unauthorized callers.
5. **Institution isolation:** test that one institution cannot read or mutate another institution's learners, certificates, documents or subscription data.
6. **Certificate integrity:** verify numbering concurrency, duplicate prevention, revocation behavior, public disclosure minimization and QR/PDF consistency.
7. **Secrets and client exposure:** inspect all HTML/JS for service-role keys, private credentials and unsafe public configuration.
8. **Release controls:** add automated smoke, authorization and regression tests before changing the production branch.

## Next safe actions
1. Wait until Supabase reports `ACTIVE` and database introspection succeeds.
2. Verify backup/restore capability and capture the current schema before any write.
3. Generate an exact live table/column/constraint/index/function/trigger/view/policy/storage inventory.
4. Produce a frontend-to-database RPC contract matrix with parameter and return types.
5. Fix admin bootstrap and authorization through a reviewed migration in a non-production environment first.
6. Add a repeatable test harness and CI workflow before feature implementation.


## Live database audit — 2026-11-06 (after recovery)
- Supabase now reports `ACTIVE_HEALTHY`; PostgreSQL introspection succeeds.
- The live public schema contains 15 application tables. All 15 currently have RLS enabled.
- Storage bucket `institution-documents` exists and is private.
- 12 recorded migrations are present, dated 2026-10-14 through 2026-10-15.
- Existing tables include profiles, packages, institutions, certificates, activity_log, companies, recruitment_requests, accreditation_requests, institution_documents, institution_users, subscriptions, certificate_sequences, certificate_verifications, platform_admins and graduate_profiles.
- The live database confirms `platform_admins` exists; the earlier source-only concern that the base SQL file did not create it is superseded by later applied migrations.

### Live security findings — remediation pending
- Security advisor reports 6 RLS-enabled tables with no policies: `accreditation_requests`, `activity_log`, `certificate_sequences`, `certificate_verifications`, `platform_admins`, `profiles`.
- Advisor reports 2 SECURITY DEFINER RPCs executable by `anon`: `public_platform_stats()` and `verify_certificate(text)`. These may be intentional public endpoints, but must be reviewed for minimal disclosure and explicit grants.
- Advisor reports 25 SECURITY DEFINER functions executable by `authenticated`. Review function bodies and authorization before changing grants.
- Performance advisor reports duplicate indexes and multiple permissive SELECT policies on institution and certificate tables.
- Health advisor currently reports no lints.
- No database changes were made during this live audit. Findings are queued for targeted, reviewed migrations; blanket grant revocation or broad policy changes could break public verification and institution workflows.
