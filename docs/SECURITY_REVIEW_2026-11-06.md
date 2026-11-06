# Security verification — 2026-11-06

Environment: Supabase project `snteiiavvaaumgaegazn`. This review used live read-only catalog queries. No production changes were applied.

## Confirmed account state
- Exactly one row exists in `public.platform_admins`.
- The account matching the intended initial admin email is present with an active admin role.
- The row is already active; no activation or password reset was needed or performed.
- The admin check function `is_platform_admin()` checks `auth.uid()` against `platform_admins.auth_user_id` and requires `status='active'`.

## RPC authorization review
- The frontend institution certificate flow calls `issue_certificate(p_payload jsonb)`; its function verifies a signed-in user and active owner/manager/staff membership in the specified institution, then checks approval and subscription/quota.
- `issue_certificates_bulk(uuid,jsonb)` verifies the caller's active membership and allowed institution role, then delegates each row to the JSONB issuance function.
- The older overload `issue_certificate(uuid,text,...)` has no caller-membership check in its body, but live ACL inspection confirms it is NOT executable by `anon` or `authenticated`; it is granted only to postgres/service_role. The current frontend does not call this overload.
- Administrative RPCs inspected (institution listing/approval/rejection/suspension/quota, certificate listing/revocation, company and recruitment administration, document review, platform stats) check `is_platform_admin()` before accessing or changing protected records.
- `verify_certificate(text)` is intentionally executable by anon and authenticated for public certificate validation. It only returns the public verification fields for certificates belonging to approved institutions and records the verification.
- `public_platform_stats()` is intentionally executable by anon and returns aggregate counts only.

## Remaining findings
- Six RLS-enabled tables have no policies: `accreditation_requests`, `activity_log`, `certificate_sequences`, `certificate_verifications`, `platform_admins`, and `profiles`. Direct client access is consequently restricted; review whether any application flow needs policies before changing anything.
- Security Advisor reports leaked-password protection disabled. Enable after checking the project's Auth settings and user impact.
- Several tables have duplicate permissive policies; consolidation is a maintenance item, not an emergency authorization change.
- Additional function bodies and frontend workflows still need a full pass before a comprehensive security sign-off.

## Production change status
No production SQL migrations, grants, policies, user records, or passwords were changed. The intended initial admin was already active, so no modification was required.


## Follow-up review (2026-11-06)

### Current project state
- Supabase project reports `ACTIVE_HEALTHY` on PostgreSQL 17.6.1.
- Security advisor still reports 6 RLS-enabled tables without policies: `accreditation_requests`, `activity_log`, `certificate_sequences`, `certificate_verifications`, `platform_admins`, and `profiles`. Treat this as intentional deny-by-default until each table's access model and RPC dependencies are verified; do not add blanket policies.
- Advisor reports 25 `SECURITY DEFINER` functions executable by `authenticated`, plus `public_platform_stats()` and `verify_certificate(text)` executable by `anon`. These require body-level authorization and output-scope review; advisor exposure alone does not prove exploitability.
- Leaked-password protection is disabled in Auth and should be enabled after checking the user-facing password policy impact.
- Performance advisor reports 3 unindexed foreign keys, 7 RLS initplan notices, 5 multiple-permissive-policy notices, and duplicate indexes. Defer index/policy cleanup until query and policy semantics are verified.

### Source review notes
- `supabase_admin_hardening.sql` uses explicit `is_platform_admin()` checks in the inspected admin RPC bodies and sets `search_path=public`.
- `fix_missing_rpcs.sql` defines `graduate_my_certificates()` with an explicit `auth.uid() IS NOT NULL` guard and joins graduate profiles by the authenticated user ID.
- The current registration UI calls `register_institution` after sign-up and uploads required documents to the `institution-documents` bucket. End-to-end RLS/storage tests remain necessary, especially for cross-institution access and partial-upload retry behavior.

### Verification limitation
- The direct SQL execution tool was blocked by its safety checks during this follow-up, so no live policy catalog query or adversarial RPC test was completed in this pass.
- No production schema, grants, policies, Auth settings, users, or passwords were changed.
- Do not treat this report as a completed penetration test or production security sign-off.
