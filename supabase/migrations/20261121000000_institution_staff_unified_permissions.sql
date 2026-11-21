-- Unified institution staff accounts and per-member permission overrides.
-- The institution_staff_profiles table was added by the prior additive migration.
create table if not exists public.institution_user_permission_overrides (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  institution_user_id uuid not null references public.institution_users(id) on delete cascade,
  permission_key text not null,
  is_granted boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint institution_user_permission_overrides_unique unique (institution_user_id, permission_key),
  constraint institution_user_permission_overrides_key_check check (permission_key in ('dashboard.view','branches.view','branches.manage','team.view','team.manage','trainees.view','trainees.manage','courses.view','courses.manage','certificates.view','certificates.issue','certificates.revoke','reports.view'))
);
create index if not exists institution_user_permission_overrides_institution_idx on public.institution_user_permission_overrides(institution_id, institution_user_id);
alter table public.institution_user_permission_overrides enable row level security;
revoke all on public.institution_user_permission_overrides from anon;
grant select, insert, update, delete on public.institution_user_permission_overrides to authenticated;
drop policy if exists institution_user_permission_overrides_select on public.institution_user_permission_overrides;
create policy institution_user_permission_overrides_select on public.institution_user_permission_overrides for select to authenticated using (public.institution_has_permission(institution_id, 'team.view'));
drop policy if exists institution_user_permission_overrides_manage on public.institution_user_permission_overrides;
create policy institution_user_permission_overrides_manage on public.institution_user_permission_overrides for all to authenticated using (public.institution_has_permission(institution_id, 'team.manage')) with check (public.institution_has_permission(institution_id, 'team.manage') and exists (select 1 from public.institution_users iu where iu.id = institution_user_permission_overrides.institution_user_id and iu.institution_id = institution_user_permission_overrides.institution_id and iu.role <> 'owner'));
create or replace function public.institution_has_permission(p_institution_id uuid,p_permission text,p_branch_id uuid default null)
returns boolean language sql stable security definer set search_path = public, pg_temp
as $function$
select exists (
 select 1 from public.institution_users iu
 where iu.institution_id=p_institution_id and iu.auth_user_id=(select auth.uid()) and iu.status='active'
 and (iu.role='owner' or coalesce((select uo.is_granted from public.institution_user_permission_overrides uo where uo.institution_user_id=iu.id and uo.institution_id=iu.institution_id and uo.permission_key=p_permission),exists(select 1 from public.institution_role_permissions rp where rp.role=iu.role and rp.permission_key=p_permission)))
 and ((p_branch_id is null and iu.role in ('owner','manager')) or (p_branch_id is not null and exists (
  select 1 from public.institution_branches b where b.id=p_branch_id and b.institution_id=p_institution_id
  and (b.is_active or (iu.role in ('owner','manager') and p_permission in ('branches.view','branches.manage')))
  and (iu.role in ('owner','manager') or exists(select 1 from public.institution_user_branches iub where iub.institution_user_id=iu.id and iub.branch_id=b.id))
 )))
);
$function$;
