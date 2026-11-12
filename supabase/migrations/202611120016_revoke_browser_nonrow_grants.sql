-- Least-privilege hardening for objects owned by postgres.
-- Preserve ordinary row-level CRUD grants; remove only privileges that bypass RLS
-- or are not required by browser clients.
revoke truncate, trigger, references
on all tables in schema public
from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke truncate, trigger, references on tables from anon, authenticated;

-- New postgres-owned public functions must receive explicit EXECUTE grants.
alter default privileges for role postgres
  revoke execute on functions from public;

alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated;
