-- Ensure the employee profile table exists before adding its visibility policies.
create table if not exists public.institution_staff_profiles (
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 institution_user_id uuid not null unique references public.institution_users(id) on delete cascade,
 auth_user_id uuid not null unique references auth.users(id) on delete cascade,
 username text not null,
 full_name text not null,
 phone text,
 contact_email text,
 job_title text,
 employment_start_date date,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint institution_staff_username_format check (username = lower(username) and username ~ '^[a-z0-9][a-z0-9._-]{2,29}
);
create unique index if not exists institution_staff_profiles_username_lower_uidx on public.institution_staff_profiles(lower(username));
create index if not exists institution_staff_profiles_institution_idx on public.institution_staff_profiles(institution_id);
alter table public.institution_staff_profiles enable row level security;
revoke all on public.institution_staff_profiles from anon;
grant select,update on public.institution_staff_profiles to authenticated;
drop policy if exists institution_staff_profiles_select on public.institution_staff_profiles;
create policy institution_staff_profiles_select on public.institution_staff_profiles for select to authenticated using (
 public.institution_has_permission(institution_id,'team.view') or public.institution_has_permission(institution_id,'team.manage')
);
drop policy if exists institution_staff_profiles_update on public.institution_staff_profiles;
create policy institution_staff_profiles_update on public.institution_staff_profiles for update to authenticated using (
 public.institution_has_permission(institution_id,'team.manage')
) with check (public.institution_has_permission(institution_id,'team.manage'));
drop policy if exists institution_user_permission_overrides_select on public.institution_user_permission_overrides;
create policy institution_user_permission_overrides_select on public.institution_user_permission_overrides for select to authenticated using (
 public.institution_has_permission(institution_id,'team.view') or public.institution_has_permission(institution_id,'team.manage')
);
drop policy if exists institution_staff_profiles_select on public.institution_staff_profiles;
create policy institution_staff_profiles_select on public.institution_staff_profiles for select to authenticated using (
 public.institution_has_permission(institution_id,'team.view') or public.institution_has_permission(institution_id,'team.manage')
);
),
 constraint institution_staff_full_name_length check (char_length(trim(full_name)) between 2 and 160)
);
create unique index if not exists institution_staff_profiles_username_lower_uidx on public.institution_staff_profiles(lower(username));
create index if not exists institution_staff_profiles_institution_idx on public.institution_staff_profiles(institution_id);
alter table public.institution_staff_profiles enable row level security;
revoke all on public.institution_staff_profiles from anon;
grant select,update on public.institution_staff_profiles to authenticated;
drop policy if exists institution_staff_profiles_select on public.institution_staff_profiles;
create policy institution_staff_profiles_select on public.institution_staff_profiles for select to authenticated using (
 public.institution_has_permission(institution_id,'team.view') or public.institution_has_permission(institution_id,'team.manage')
);
drop policy if exists institution_staff_profiles_update on public.institution_staff_profiles;
create policy institution_staff_profiles_update on public.institution_staff_profiles for update to authenticated using (
 public.institution_has_permission(institution_id,'team.manage')
) with check (public.institution_has_permission(institution_id,'team.manage'));
drop policy if exists institution_user_permission_overrides_select on public.institution_user_permission_overrides;
create policy institution_user_permission_overrides_select on public.institution_user_permission_overrides for select to authenticated using (
 public.institution_has_permission(institution_id,'team.view') or public.institution_has_permission(institution_id,'team.manage')
);
drop policy if exists institution_staff_profiles_select on public.institution_staff_profiles;
create policy institution_staff_profiles_select on public.institution_staff_profiles for select to authenticated using (
 public.institution_has_permission(institution_id,'team.view') or public.institution_has_permission(institution_id,'team.manage')
);
