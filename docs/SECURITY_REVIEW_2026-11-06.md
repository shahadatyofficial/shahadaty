# Security verification — 2026-11-06

Environment: Supabase project `snteiiavvaaumgaegazn`. This review used live read-only catalog queries. No production changes were applied.

## Confirmed account state
- Exactly one row exists in `public.platform_admins`.
- The intended initial admin account is present with an active admin role.
- The row is already active; no activation or password reset was needed or performed.
- `is_platform_admin()` checks `auth.uid()` against `platform_admins.auth_user_id` and requires `status='active'`.

## RPC authorization review
- The frontend institution certificate flow calls `issue_certificate(p_payload jsonb)`; it verifies a signed-in user and active owner/manager/staff membership in the specified institution, then checks approval and subscription/quota.
- `issue_certificates_bulk(uuid,jsonb)` verifies the caller's active membership and allowed institution role, then delegates each row to the JSONB issuance function.
- The older overload `issue_certificate(uuid,text,...)` has no caller-membership check in its body, but its live ACL is restricted to postgres/service_role; it is not executable by `anon` or `authenticated`. The current frontend does not call this overload.
- Inspected administrative RPCs check `is_platform_admin()` before protected access or changes.
- `verify_certificate(text)` is intentionally executable by anon/authenticated for public certificate validation. It returns public verification fields for certificates belonging to approved institutions and records the verification.
- `public_platform_stats()` is intentionally executable by anon and returns aggregate counts only.
- `register_institution` requires `auth.uid()`, validates required fields, prevents duplicate institution registration by the same auth user, and binds the new institution to that user.
- `graduate_my_certificates()` requires an authenticated user and scopes results through the graduate profile linked to `auth.uid()`.
- `has_institution_role`, `is_institution_member`, and `is_platform_admin` use `auth.uid()` in their predicates.
- Certificate sequence helper functions are executable only by postgres/service_role, not browser roles.

## Confirmed high-severity table privilege finding
Live `has_table_privilege` checks confirm that browser roles have effective privileges beyond the intended row-level application operations:
- `anon` has effective `TRUNCATE` on `companies` and `recruitment_requests`.
- `authenticated` has effective `TRUNCATE` on `certificates`, `companies`, `graduate_profiles`, `institution_documents`, `institution_users`, `institutions`, `packages`, `recruitment_requests`, and `subscriptions`.
- Both browser roles also have unnecessary `TRIGGER` and `REFERENCES` privileges on several exposed tables.
- `TRUNCATE` is not governed by RLS. Therefore the above effective privileges represent a real destructive capability even where RLS has no policies or blocks row-level DELETE. This is not merely an advisor warning.
- `anon` and `authenticated` do not have CREATE on the public schema, but that does not neutralize TRUNCATE.
- The live table ACLs show broad grants such as `arwdDxtm` on tables where the browser should have a much narrower privilege set.

### Required remediation (not yet applied)
1. Revoke `TRUNCATE`, `TRIGGER`, and `REFERENCES` from `anon` and `authenticated` on all tables in the exposed `public` schema.
2. Audit remaining DML grants table-by-table and reduce to the exact operations required by current frontend flows; preserve required SELECT/INSERT and RLS behavior.
3. Inspect and correct default privileges so newly created public tables do not inherit broad browser-role grants.
4. Re-run effective privilege checks and advisors after remediation.
5. Test all registration, certificate issuance, graduate profile, company lead, recruitment, and admin workflows with real anon/authenticated sessions after the grant changes.

A candidate narrow revocation to review in a development branch is:

```sql
REVOKE TRUNCATE, TRIGGER, REFERENCES
ON ALL TABLES IN SCHEMA public
FROM anon, authenticated;
```

This statement alone does not correct excessive INSERT/UPDATE/DELETE grants, nor does it adjust default privileges. Do not apply it to production until a branch test and full frontend regression pass are complete.

## RLS and storage findings
- All 15 public application tables have RLS enabled.
- Six RLS-enabled tables have no policies: `accreditation_requests`, `activity_log`, `certificate_sequences`, `certificate_verifications`, `platform_admins`, and `profiles`. Treat these as deny-by-default until each access model and RPC dependency is verified; do not add blanket policies.
- Duplicate permissive SELECT policies exist on certificates, institution_documents, institution_users, institutions, and subscriptions. They appear semantically identical in the current catalog; consolidate only after checking dependencies and regression tests.
- The `institution-documents` bucket is private. Storage policies scope insert/read/delete to active institution membership and reserve updates for platform admins. Cross-institution and upload-retry tests remain necessary.

## Advisor findings
- 25 SECURITY DEFINER functions are executable by `authenticated`; inspected business/admin functions have explicit authorization checks. Continue checking every function body and exact EXECUTE ACL rather than revoking all functions in bulk.
- `public_platform_stats()` and `verify_certificate(text)` are intentionally callable by anon; review their minimal disclosure periodically.
- Leaked-password protection is disabled in Auth and should be enabled after checking the user-facing password policy impact.
- Performance advisor reports 3 unindexed foreign keys, 7 RLS initplan notices, 5 multiple-permissive-policy notices, and duplicate indexes. Defer performance cleanup until query and policy semantics are verified.

## Production change status
No production SQL migrations, grants, policies, Auth settings, users, or passwords were changed. The intended initial admin was already active. This is not a completed penetration test or production security sign-off.


## Additional confirmed finding: unsafe default privileges
The live `pg_default_acl` catalog shows schema-level defaults for both `supabase_admin` and `postgres` in `public`:
- New tables are default-granted `arwdDxtm` to `anon` and `authenticated` (broad DML plus TRUNCATE, REFERENCES, TRIGGER).
- New functions are default-granted EXECUTE (`X`) to `anon` and `authenticated`.
- New sequences are default-granted `rwU` to `anon` and `authenticated`.

This explains why broad privileges recur and creates a continuing exposure for future objects, including newly created SECURITY DEFINER functions. Remediation must correct default privileges for each relevant object-creating role (`supabase_admin` and `postgres`), then audit current object ACLs separately. Do not assume a one-time REVOKE fixes future objects. The exact default-privilege changes must be tested against required Supabase migrations and app workflows in an isolated development database first.
