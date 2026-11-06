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
