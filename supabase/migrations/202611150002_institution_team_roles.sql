-- Align institution membership roles with the permission matrix and invitation flow.
-- Preserve the legacy 'staff' role for existing memberships.
alter table public.institution_users
  drop constraint if exists institution_users_role_check;

alter table public.institution_users
  add constraint institution_users_role_check
  check (role in (
    'owner',
    'manager',
    'staff',
    'training_manager',
    'registrar',
    'certificate_issuer',
    'branch_manager',
    'viewer'
  ));

-- Keep at least one active owner even if a client attempts a direct role update.
create or replace function public.guard_institution_owner_role_changes()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare actor_role text; active_owner_count integer;
begin
  if (select auth.uid()) is null then return new; end if;
  if new.institution_id is distinct from old.institution_id or new.auth_user_id is distinct from old.auth_user_id then
    raise exception 'Institution membership identity is immutable' using errcode='42501';
  end if;
  if new.role is not distinct from old.role and new.status is not distinct from old.status then return new; end if;
  select role into actor_role from public.institution_users where institution_id=old.institution_id and auth_user_id=(select auth.uid()) and status='active' limit 1;
  if (old.role='owner' or new.role='owner') and actor_role is distinct from 'owner' then
    raise exception 'Only an institution owner can change owner privileges' using errcode='42501';
  end if;
  if old.role='owner' and (new.role<>'owner' or new.status<>'active') then
    select count(*) into active_owner_count from public.institution_users where institution_id=old.institution_id and role='owner' and status='active' and id<>old.id;
    if active_owner_count < 1 then raise exception 'An institution must retain at least one active owner' using errcode='23514'; end if;
  end if;
  return new;
end $fn$;

-- The existing trigger continues to call this replaced function.
