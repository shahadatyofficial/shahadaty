-- Multi-branch institution workspace foundation.
-- Safe additive migration: preserves all existing institutions, memberships, courses,
-- certificates and subscriptions. Apply only to a non-production Supabase branch first.

begin;

create table if not exists public.institution_branches (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  branch_code text,
  name text not null,
  governorate text,
  address text,
  phone text,
  manager_user_id uuid references auth.users(id) on delete set null,
  is_main boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint institution_branches_name_nonempty check (length(btrim(name)) between 2 and 160),
  constraint institution_branches_code_nonempty check (branch_code is null or length(btrim(branch_code)) between 1 and 40)
);

create unique index if not exists institution_branches_institution_code_uidx
  on public.institution_branches(institution_id, lower(branch_code))
  where branch_code is not null;
create unique index if not exists institution_branches_one_main_uidx
  on public.institution_branches(institution_id) where is_main;
create index if not exists institution_branches_institution_active_idx
  on public.institution_branches(institution_id, is_active);

create table if not exists public.institution_role_permissions (
  role text not null,
  permission_key text not null,
  created_at timestamptz not null default now(),
  primary key (role, permission_key),
  constraint institution_role_permissions_role_check
    check (role in ('owner','manager','training_manager','registrar','certificate_issuer','branch_manager','viewer'))
);

insert into public.institution_role_permissions(role, permission_key) values
 ('manager','dashboard.view'),
 ('manager','branches.view'),('manager','branches.manage'),
 ('manager','team.view'),('manager','team.manage'),
 ('manager','trainees.view'),('manager','trainees.manage'),
 ('manager','courses.view'),('manager','courses.manage'),
 ('manager','certificates.view'),('manager','certificates.issue'),('manager','certificates.revoke'),
 ('manager','reports.view'),
 ('training_manager','dashboard.view'),('training_manager','branches.view'),
 ('training_manager','trainees.view'),('training_manager','trainees.manage'),
 ('training_manager','courses.view'),('training_manager','courses.manage'),
 ('training_manager','certificates.view'),('training_manager','reports.view'),
 ('registrar','dashboard.view'),('registrar','trainees.view'),('registrar','trainees.manage'),
 ('registrar','courses.view'),('registrar','certificates.view'),
 ('certificate_issuer','dashboard.view'),('certificate_issuer','trainees.view'),
 ('certificate_issuer','courses.view'),('certificate_issuer','certificates.view'),
 ('certificate_issuer','certificates.issue'),
 ('branch_manager','dashboard.view'),('branch_manager','branches.view'),
 ('branch_manager','trainees.view'),('branch_manager','trainees.manage'),
 ('branch_manager','courses.view'),('branch_manager','courses.manage'),
 ('branch_manager','certificates.view'),('branch_manager','certificates.issue'),
 ('branch_manager','reports.view'),
 ('viewer','dashboard.view'),('viewer','branches.view'),('viewer','trainees.view'),
 ('viewer','courses.view'),('viewer','certificates.view'),('viewer','reports.view')
on conflict do nothing;

create table if not exists public.institution_user_branches (
  id uuid primary key default gen_random_uuid(),
  institution_user_id uuid not null references public.institution_users(id) on delete cascade,
  branch_id uuid not null references public.institution_branches(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(institution_user_id, branch_id)
);
create index if not exists institution_user_branches_branch_idx
  on public.institution_user_branches(branch_id, institution_user_id);

create table if not exists public.institution_trainees (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  branch_id uuid references public.institution_branches(id) on delete set null,
  full_name text not null,
  full_name_en text,
  phone text,
  email text,
  national_id text,
  external_reference text,
  governorate text,
  notes text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(full_name)) between 2 and 200)
);
create unique index if not exists institution_trainees_national_id_uidx
  on public.institution_trainees(institution_id, national_id)
  where national_id is not null and btrim(national_id) <> '';
create index if not exists institution_trainees_org_branch_idx
  on public.institution_trainees(institution_id, branch_id, status);
create index if not exists institution_trainees_phone_idx
  on public.institution_trainees(institution_id, phone);

create table if not exists public.institution_course_runs (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  branch_id uuid references public.institution_branches(id) on delete set null,
  course_id uuid not null references public.institution_courses(id) on delete restrict,
  run_name text,
  instructor_name text,
  start_date date,
  end_date date,
  capacity integer check (capacity is null or capacity > 0),
  status text not null default 'planned'
    check (status in ('planned','open','in_progress','completed','cancelled')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date >= start_date)
);
create index if not exists institution_course_runs_org_branch_idx
  on public.institution_course_runs(institution_id, branch_id, status);

create table if not exists public.institution_enrollments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  course_run_id uuid not null references public.institution_course_runs(id) on delete cascade,
  trainee_id uuid not null references public.institution_trainees(id) on delete cascade,
  status text not null default 'enrolled'
    check (status in ('enrolled','attending','completed','withdrawn','failed')),
  enrolled_at timestamptz not null default now(),
  completed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  unique(course_run_id, trainee_id)
);
create index if not exists institution_enrollments_org_run_idx
  on public.institution_enrollments(institution_id, course_run_id, status);
create index if not exists institution_enrollments_trainee_idx
  on public.institution_enrollments(trainee_id, enrolled_at desc);

create table if not exists public.institution_attendance (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  enrollment_id uuid not null references public.institution_enrollments(id) on delete cascade,
  session_date date not null,
  attendance_status text not null check (attendance_status in ('present','absent','late','excused')),
  notes text,
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(enrollment_id, session_date)
);
create index if not exists institution_attendance_org_date_idx
  on public.institution_attendance(institution_id, session_date);

alter table public.institution_courses
  add column if not exists branch_id uuid references public.institution_branches(id) on delete set null;
alter table public.certificates
  add column if not exists branch_id uuid references public.institution_branches(id) on delete set null,
  add column if not exists trainee_id uuid references public.institution_trainees(id) on delete set null,
  add column if not exists course_id uuid references public.institution_courses(id) on delete set null;

create index if not exists institution_courses_branch_idx
  on public.institution_courses(institution_id, branch_id);
create index if not exists certificates_institution_branch_idx
  on public.certificates(institution_id, branch_id, created_at desc);

create or replace function public.institution_has_permission(
  p_institution_id uuid,
  p_permission text,
  p_branch_id uuid default null
) returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.institution_users iu
    where iu.institution_id = p_institution_id
      and iu.auth_user_id = (select auth.uid())
      and iu.status = 'active'
      and (
        iu.role = 'owner'
        or (
          iu.role = 'manager'
          and p_permission not in ('billing.manage')
        )
        or exists (
          select 1
          from public.institution_role_permissions rp
          where rp.role = iu.role and rp.permission_key = p_permission
        )
      )
      and (
        p_branch_id is null
        or iu.role = 'owner'
        or (
          iu.role = 'manager'
          and exists (
            select 1 from public.institution_branches b
            where b.id = p_branch_id and b.institution_id = p_institution_id
          )
        )
        or exists (
          select 1
          from public.institution_user_branches iub
          join public.institution_branches b on b.id = iub.branch_id
          where iub.institution_user_id = iu.id
            and iub.branch_id = p_branch_id
            and b.institution_id = p_institution_id
            and b.is_active
        )
      )
  );
$$;

revoke all on function public.institution_has_permission(uuid,text,uuid) from public, anon;
grant execute on function public.institution_has_permission(uuid,text,uuid) to authenticated;

alter table public.institution_branches enable row level security;
alter table public.institution_role_permissions enable row level security;
alter table public.institution_user_branches enable row level security;
alter table public.institution_trainees enable row level security;
alter table public.institution_course_runs enable row level security;
alter table public.institution_enrollments enable row level security;
alter table public.institution_attendance enable row level security;

drop policy if exists institution_branches_select on public.institution_branches;
create policy institution_branches_select on public.institution_branches
 for select to authenticated
 using (public.institution_has_permission(institution_id,'branches.view',id));

drop policy if exists institution_branches_insert on public.institution_branches;
create policy institution_branches_insert on public.institution_branches
 for insert to authenticated
 with check (public.institution_has_permission(institution_id,'branches.manage'));

drop policy if exists institution_branches_update on public.institution_branches;
create policy institution_branches_update on public.institution_branches
 for update to authenticated
 using (public.institution_has_permission(institution_id,'branches.manage',id))
 with check (public.institution_has_permission(institution_id,'branches.manage',id));

drop policy if exists institution_branches_delete on public.institution_branches;
create policy institution_branches_delete on public.institution_branches
 for delete to authenticated
 using (public.institution_has_permission(institution_id,'branches.manage',id));

drop policy if exists institution_role_permissions_select on public.institution_role_permissions;
create policy institution_role_permissions_select on public.institution_role_permissions
 for select to authenticated
 using (exists (
   select 1 from public.institution_users iu
   where iu.auth_user_id=(select auth.uid()) and iu.status='active'
 ));

drop policy if exists institution_user_branches_select on public.institution_user_branches;
create policy institution_user_branches_select on public.institution_user_branches
 for select to authenticated
 using (exists (
   select 1 from public.institution_users iu
   join public.institution_branches b on b.institution_id=iu.institution_id
   where iu.id=institution_user_id and iu.auth_user_id=(select auth.uid()) and iu.status='active'
   union all
   select 1 from public.institution_user_branches mine
   join public.institution_users iu on iu.id=mine.institution_user_id
   where mine.branch_id=institution_user_branches.branch_id
     and iu.auth_user_id=(select auth.uid()) and iu.status='active'
 ));

drop policy if exists institution_user_branches_manage on public.institution_user_branches;
create policy institution_user_branches_manage on public.institution_user_branches
 for all to authenticated
 using (exists (
   select 1 from public.institution_users target
   where target.id=institution_user_id
     and public.institution_has_permission(target.institution_id,'team.manage')
 ))
 with check (exists (
   select 1 from public.institution_users target
   join public.institution_branches b on b.id=branch_id and b.institution_id=target.institution_id
   where target.id=institution_user_id
     and public.institution_has_permission(target.institution_id,'team.manage')
 ));

drop policy if exists institution_trainees_select on public.institution_trainees;
create policy institution_trainees_select on public.institution_trainees
 for select to authenticated
 using (public.institution_has_permission(institution_id,'trainees.view',branch_id));
drop policy if exists institution_trainees_insert on public.institution_trainees;
create policy institution_trainees_insert on public.institution_trainees
 for insert to authenticated
 with check (public.institution_has_permission(institution_id,'trainees.manage',branch_id));
drop policy if exists institution_trainees_update on public.institution_trainees;
create policy institution_trainees_update on public.institution_trainees
 for update to authenticated
 using (public.institution_has_permission(institution_id,'trainees.manage',branch_id))
 with check (public.institution_has_permission(institution_id,'trainees.manage',branch_id));
drop policy if exists institution_trainees_delete on public.institution_trainees;
create policy institution_trainees_delete on public.institution_trainees
 for delete to authenticated
 using (public.institution_has_permission(institution_id,'trainees.manage',branch_id));

drop policy if exists institution_course_runs_select on public.institution_course_runs;
create policy institution_course_runs_select on public.institution_course_runs
 for select to authenticated
 using (public.institution_has_permission(institution_id,'courses.view',branch_id));
drop policy if exists institution_course_runs_insert on public.institution_course_runs;
create policy institution_course_runs_insert on public.institution_course_runs
 for insert to authenticated
 with check (public.institution_has_permission(institution_id,'courses.manage',branch_id));
drop policy if exists institution_course_runs_update on public.institution_course_runs;
create policy institution_course_runs_update on public.institution_course_runs
 for update to authenticated
 using (public.institution_has_permission(institution_id,'courses.manage',branch_id))
 with check (public.institution_has_permission(institution_id,'courses.manage',branch_id));
drop policy if exists institution_course_runs_delete on public.institution_course_runs;
create policy institution_course_runs_delete on public.institution_course_runs
 for delete to authenticated
 using (public.institution_has_permission(institution_id,'courses.manage',branch_id));

drop policy if exists institution_enrollments_select on public.institution_enrollments;
create policy institution_enrollments_select on public.institution_enrollments
 for select to authenticated
 using (public.institution_has_permission(institution_id,'trainees.view'));
drop policy if exists institution_enrollments_insert on public.institution_enrollments;
create policy institution_enrollments_insert on public.institution_enrollments
 for insert to authenticated
 with check (
   public.institution_has_permission(institution_id,'trainees.manage')
   and exists (
     select 1 from public.institution_course_runs r
     join public.institution_trainees t on t.id=trainee_id
     where r.id=course_run_id and r.institution_id=institution_id
       and t.institution_id=institution_id
       and r.branch_id is not distinct from t.branch_id
   )
 );
drop policy if exists institution_enrollments_update on public.institution_enrollments;
create policy institution_enrollments_update on public.institution_enrollments
 for update to authenticated
 using (public.institution_has_permission(institution_id,'trainees.manage'))
 with check (public.institution_has_permission(institution_id,'trainees.manage'));
drop policy if exists institution_enrollments_delete on public.institution_enrollments;
create policy institution_enrollments_delete on public.institution_enrollments
 for delete to authenticated
 using (public.institution_has_permission(institution_id,'trainees.manage'));

drop policy if exists institution_attendance_select on public.institution_attendance;
create policy institution_attendance_select on public.institution_attendance
 for select to authenticated
 using (public.institution_has_permission(institution_id,'trainees.view'));
drop policy if exists institution_attendance_write on public.institution_attendance;
create policy institution_attendance_write on public.institution_attendance
 for all to authenticated
 using (public.institution_has_permission(institution_id,'trainees.manage'))
 with check (public.institution_has_permission(institution_id,'trainees.manage'));

-- Extend the existing role helper only additively: existing owners/managers retain access.
commit;
