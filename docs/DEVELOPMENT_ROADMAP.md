# Shahadaty Scientific Platform — Development Roadmap

## Working agreement
- Preserve the existing application and all production data.
- Keep the current stack: GitHub, HTML/CSS/JavaScript, and Supabase.
- Work in feature branches; do not push experimental changes directly to `main`.
- No destructive database operations, production credential changes, or changes to authentication/authorization without a verified backup and a reviewed migration.
- Distinguish verified implementation from planned or unverified functionality.

## Baseline — 2026-11-06
- Repository: `shahadatyofficial/shahadaty`
- Default branch: `main`
- Working branch: `development/phase-0-audit`
- Supabase project: `snteiiavvaaumgaegazn`
- Supabase project status at last check: `COMING_UP`.
- Database introspection failed with "Database is possibly not accessible at the moment".
- Migration listing returned an empty list. This is not proof that the database has no schema; it may be unavailable or migrations may have been applied outside the migration tracker.
- Security/performance/health advisor calls returned no lints, but these results are not a substitute for database inspection while PostgreSQL is unavailable.
- The current repository is a legacy multi-page HTML/JavaScript application. A full runtime and dependency audit remains pending.

## Target modules
1. Marketing website and CMS.
2. Super Admin command center, institution lifecycle, approvals, audit trail, alerts, tasks.
3. Institutions: staff, learners, trainers, courses, cohorts, attendance, documents, settings.
4. Certificates: templates, issuance, serials, QR, PDF, bulk import/export, archive, verification.
5. Plans, subscriptions, renewals, upgrades/downgrades, add-ons, invoices, payments, discounts, wallets.
6. Graduate portal and employer verification/workflows.
7. Finance, analytics, reporting, notifications, support, marketing and referrals.
8. Integrations: API, webhooks, Google/Microsoft/Zoom/Moodle where credentials and supported APIs are available.
9. File management, localization, currencies, tax configuration, monitoring, backups and security.
10. AI-assisted analytics and fraud signals, with human review and explainable outputs.

## Delivery sequence and exit gates

### Phase 0 — Safe baseline and recovery
- Confirm the correct Supabase project and wait for PostgreSQL readiness.
- Capture repository tree, current commit, branch protection/deployment configuration, and existing assets.
- Inventory database schemas, tables, columns, constraints, indexes, triggers, views, functions, RLS policies, storage buckets/policies, auth configuration, and migration history.
- Export a verified backup before any schema mutation.
- Produce a route/page inventory and map every frontend RPC call to a real database function.
- Identify secrets and ensure no service-role key or private credential is exposed in browser code.

**Exit gate:** database reachable; backup verified; schema and frontend-to-RPC maps complete; no production writes performed.

### Phase 1 — Architecture and security foundation
- Define canonical institution, user, role, permission, subscription, course, learner, certificate, payment and audit models.
- Resolve admin authorization consistently using database-enforced roles and least privilege.
- Review RLS policies and grants for every exposed table, view and RPC.
- Review SECURITY DEFINER functions, search_path, ownership, EXECUTE grants and input validation.
- Add idempotent, ordered migrations and rollback/restore procedures.
- Define shared frontend auth/session handling and error handling.

**Exit gate:** threat model and permission matrix approved; security tests pass in a non-production environment.

### Phase 2 — Core institution and certificate workflows
- Institution registration, document submission, review, approval, suspension and audit history.
- Institution users, roles and scoped access.
- Learners, trainers, programs/courses and cohorts.
- Certificate template management, issuance, numbering, QR, PDF, revocation and archive.
- Public verification with minimal disclosure and tamper-resistant verification records.

**Exit gate:** complete end-to-end workflow tested for each authorized role.

### Phase 3 — Commercial operations
- Plans, quotas, add-ons and feature entitlements.
- Subscription lifecycle, renewals, upgrades/downgrades and trial handling.
- Payment provider integration only after provider, legal entity, settlement country and webhook requirements are confirmed.
- Invoices, refunds, discounts, wallets and financial reconciliation.

**Exit gate:** billing state transitions and webhook idempotency verified in provider sandbox.

### Phase 4 — Super Admin and institution experience
- Admin dashboard, institution management, approval queue, staff, plans, finance, analytics, support and audit logs.
- Institution dashboard, learner/course operations, certificates, reports, subscription and settings.
- Responsive Arabic-first UX with English localization and RTL/LTR verification.

**Exit gate:** all screens map to implemented permissions and tested backend operations.

### Phase 5 — Graduate, employer and international capabilities
- Graduate profile and certificate wallet.
- Employer verification workflows with consent and access controls.
- Country-aware configuration for Egypt, Saudi Arabia and UAE.
- DataFlow-related document preparation/status tracking only; never claim DataFlow or regulator approval unless independently verified.
- International recognition/accreditation claims only where documentary evidence and issuing authority are confirmed.
- API, webhooks and third-party integrations with documented scopes and credential handling.

**Exit gate:** country-specific legal/product review and external integration tests.

### Phase 6 — Operations, analytics and AI
- Monitoring, backups, restore drills, incident logs and service health.
- Analytics for institution growth, revenue, issuance and verification.
- AI predictions and anomaly signals with confidence, auditability and human review.
- Support, marketing automation and content management.

**Exit gate:** operational runbooks, restore drill and privacy/security review complete.

### Phase 7 — Unified acceptance test and release
- Role-based end-to-end test matrix.
- Registration, approval, login, subscription, payment, issuance, QR, PDF, verification, revocation and reporting tests.
- RLS/authorization negative tests and cross-institution isolation tests.
- Browser/device, RTL/LTR, accessibility, performance and load checks.
- Backup restore rehearsal, release checklist and rollback plan.

**Release rule:** do not release until all critical tests pass and no unresolved critical/high security issue remains.

## Historical baseline note
The database unavailability recorded in the 2026-11-06 baseline was temporary. PostgreSQL has since been reached and production schema changes have been applied and verified. Use current database introspection and verified migrations for ongoing work.


## Verified delivery update — 2026-11-12

The live project is now reachable and has moved beyond the original Phase 0 baseline. The earlier note that PostgreSQL was unavailable is historical and must not be treated as the current blocker.

### Verified production work
- Institution registration, legal data/document review, rejection feedback, and rejected-application resubmission are implemented.
- Certificate issuance, verification, mobile certificate presentation, bulk import, trainee search/profile, and admin certificate editing are implemented.
- Annual/monthly package pricing, paid-subscription gating, payment-reference submission, and admin payment confirmation are implemented.
- Graduate publication consent is explicit; public visibility is not inferred from employer visibility.
- Institution support chat and mobile dashboard refinements are implemented.
- The existing institution's annual Diamond subscription was recorded as paid for EGP 15,000 with the payment reference supplied by the owner; subscription term: 2026-11-12 through 2027-11-12.
- Latest production deployment for PR #70 completed successfully; inline JavaScript validation also passed.

### Remaining acceptance work (not yet claimed complete)
1. Execute real browser/device end-to-end tests for institution registration, login, approval, payment, certificate issue, mobile viewing, QR verification, revocation, and employer lookup.
2. Exercise pending/rejected/suspended institution states with safe test accounts, not fabricated production rows.
3. Validate the support inbox end-to-end across visitor, institution, and admin roles.
4. Test bilingual navigation and all RTL/LTR pages on current mobile browsers.
5. Verify backup/restore procedure and document operational recovery steps.
6. Review payment reconciliation and ensure the displayed paid amount, billing cycle, and dates remain consistent in all admin/institution views.
7. Complete remaining permission-isolation tests for every institution-scoped RPC and storage path.

### Current release posture
Core production workflows are implemented and the latest changes are deployed. Full acceptance testing is still pending; do not describe the platform as fully certified or all device/browser scenarios as tested until the checks above pass.
