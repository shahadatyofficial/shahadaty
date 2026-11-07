-- Shahadaty | Least-privilege hardening candidate
-- Target: isolated Supabase development branch ONLY.
-- DO NOT run against production before workflow regression tests and review.
--
-- Finding addressed:
-- anon/authenticated currently inherit TRUNCATE, TRIGGER and REFERENCES
-- on multiple public tables. TRUNCATE bypasses RLS. Both object-creating
-- roles (postgres and supabase_admin) also default-grant these privileges
-- on future public tables and EXECUTE on future public functions.
--
-- This first pass deliberately preserves existing SELECT/INSERT/UPDATE/DELETE
-- grants. Those require a separate table-by-table review against frontend flows.

BEGIN;

-- Remove non-row-level privileges from existing exposed tables.
REVOKE TRUNCATE, TRIGGER, REFERENCES
ON ALL TABLES IN SCHEMA public
FROM anon, authenticated;

-- Prevent the same dangerous table privileges from returning on new tables.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLES FROM anon, authenticated;

-- New functions must be explicitly granted to the exact application roles.
-- Remove PostgreSQL's default PUBLIC EXECUTE for future functions, plus the
-- explicit anon/authenticated defaults observed in pg_default_acl.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;

-- Verification: every row below should report false for trunc/trig/refs.
SELECT
  c.relname AS table_name,
  r.rolname AS role_name,
  has_table_privilege(r.rolname, c.oid, 'TRUNCATE') AS can_truncate,
  has_table_privilege(r.rolname, c.oid, 'TRIGGER') AS can_create_trigger,
  has_table_privilege(r.rolname, c.oid, 'REFERENCES') AS can_reference
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN (VALUES ('anon'), ('authenticated')) AS r(rolname)
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname, r.rolname;

-- Verify future defaults for both object-creating roles.
SELECT
  owner_role.rolname AS object_owner_role,
  d.defaclobjtype,
  d.defaclacl::text AS default_acl
FROM pg_default_acl d
JOIN pg_roles owner_role ON owner_role.oid = d.defaclrole
JOIN pg_namespace n ON n.oid = d.defaclnamespace
WHERE n.nspname = 'public'
  AND owner_role.rolname IN ('postgres', 'supabase_admin')
ORDER BY owner_role.rolname, d.defaclobjtype;

-- Keep this transaction rollback-only during initial validation.
-- Change to COMMIT only after confirming the isolated branch and reviewing
-- all verification output. Never paste this candidate into production.
ROLLBACK;
