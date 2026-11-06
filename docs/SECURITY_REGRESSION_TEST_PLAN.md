# Shahadaty — Security Regression Test Plan

**Status:** Test plan only. No tests in this document are claimed as executed.
**Target:** Isolated Supabase development branch, never production.
**Production project:** `snteiiavvaaumgaegazn`
**Related candidate:** `sql/security_least_privilege_candidate.sql`

## Entry criteria

- [ ] A Supabase development branch exists and reports healthy/ready.
- [ ] Its schema and migrations match the intended production baseline.
- [ ] A disposable test identity exists for each role below.
- [ ] No production credentials or service-role key are used in browser tests.
- [ ] Baseline grants, default ACLs, RLS policies, function ACLs, and advisor output are captured.

## Database privilege tests

Run as catalog-only assertions before and after applying a candidate migration in the isolated branch.

- [ ] `anon` cannot `TRUNCATE`, create triggers on, or add foreign-key references to exposed application tables.
- [ ] `authenticated` cannot `TRUNCATE`, create triggers on, or add foreign-key references to exposed application tables.
- [ ] Check effective privileges inherited through `PUBLIC`, role membership, and direct grants; do not rely only on `relacl`.
- [ ] Check all exposed tables and partitioned tables, not only the nine previously observed tables.
- [ ] Check sequence privileges separately (`USAGE`, `SELECT`, `UPDATE`) and map each sequence to its owning table/workflow.
- [ ] Check default privileges for both object owners `postgres` and `supabase_admin`, including tables, sequences, and functions.
- [ ] Create disposable future table/sequence/function objects inside a rolled-back test transaction and verify their effective ACLs.
- [ ] Confirm required frontend operations still have only the minimum grants they need.

## RLS and tenant-isolation tests

- [ ] Anonymous requests cannot read institution, learner, staff, subscription, or private document data.
- [ ] Institution A cannot read, update, delete, or enumerate Institution B records.
- [ ] A user without an active institution membership cannot access institution workflows.
- [ ] Owner, manager, and staff permissions match the documented role matrix.
- [ ] UPDATE policies include ownership-preserving `WITH CHECK` predicates.
- [ ] The six RLS-enabled tables without policies remain inaccessible through direct browser-role table access unless a reviewed RPC explicitly mediates access.
- [ ] No blanket policies are added merely to silence the advisor.

## SECURITY DEFINER and RPC tests

- [ ] Enumerate every exposed SECURITY DEFINER function and its effective EXECUTE grants, including inherited PUBLIC access.
- [ ] Every administrative RPC rejects anon and ordinary authenticated users.
- [ ] Admin RPCs accept only an active platform admin identity.
- [ ] Institution RPCs reject cross-institution identifiers and forged ownership fields.
- [ ] Certificate issuance checks active membership, allowed role, institution approval, subscription state, and quota.
- [ ] Bulk issuance enforces the same authorization for every row.
- [ ] Public certificate verification returns only approved public fields and never private contact/legal/document data.
- [ ] Public platform statistics return aggregate counts only.
- [ ] Every SECURITY DEFINER function uses a fixed safe search_path and validates inputs.

## Storage and application workflow tests

- [ ] Institution registration creates an institution bound to the signed-in user.
- [ ] Duplicate registration is rejected safely.
- [ ] Required legal documents upload to the private `institution-documents` bucket.
- [ ] Institution A cannot list, read, overwrite, or delete Institution B's files.
- [ ] Admin document review works only for active platform admins.
- [ ] Graduate profile reads and writes are scoped to the signed-in graduate.
- [ ] Company and recruitment submissions follow their intended anonymous/authenticated access model.
- [ ] Certificate issue, bulk issue, verify, and revoke workflows work for their intended roles.
- [ ] Subscription and quota transitions cannot be triggered by an institution user or public visitor.

## Negative tests (must fail closed)

- [ ] Anonymous call to every admin RPC.
- [ ] Authenticated non-admin call to every admin RPC.
- [ ] Institution A attempts to use Institution B's UUID in every institution-scoped RPC.
- [ ] Client submits forged `auth_user_id`, `institution_id`, role, approval, payment, quota, or status fields.
- [ ] Browser role attempts direct TRUNCATE and sequence mutation.
- [ ] Public verification probes unknown, revoked, and unapproved certificates.
- [ ] Storage path traversal and cross-tenant object-key substitution attempts.

## Performance and security exit gates

- [ ] Re-run Security Advisor and explain every remaining warning.
- [ ] Re-run Performance Advisor; resolve only after behavior-preserving query/policy review.
- [ ] Confirm no new exposed SECURITY DEFINER functions inherit unintended EXECUTE.
- [ ] Confirm all privilege assertions pass after creating future objects.
- [ ] Capture test evidence, environment ID, migration SHA, and timestamp.
- [ ] Obtain code review before changing the candidate from rollback-only to a migration.
- [ ] Keep production unchanged until the complete regression suite and rollback rehearsal pass.

## Current blockers

1. No isolated Supabase development branch was available at the last check.
2. Branch creation requires explicit cost approval; no branch has been created.
3. GitHub Actions had no workflow run for the current security branch head at the last check.
4. No application end-to-end or negative authorization tests have been executed.

**Release rule:** This plan is not a security sign-off. Do not merge or deploy while high-severity effective grants remain or any critical test is unexecuted.
