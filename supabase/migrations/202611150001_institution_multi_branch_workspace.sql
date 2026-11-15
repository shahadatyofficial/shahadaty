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
        or exists (
          select 1
          from public.institution_role_permissions rp
          where rp.role = iu.role and rp.permission_key = p_permission
        )
      )
      and (
        (p_branch_id is null and iu.role in ('owner','manager'))
        or iu.role = 'owner'
        or (
          iu.role = 'manager'
          and exists (
            select 1 from public.institution_branches b
            where b.id = p_branch_id and b.institution_id = p_institution_id
          )
        )
        or (
          p_branch_id is not null
          and exists (
            select 1
            from public.institution_user_branches iub
            join public.institution_branches b on b.id = iub.branch_id
            where iub.institution_user_id = iu.id
              and iub.branch_id = p_branch_id
              and b.institution_id = p_institution_id
              and b.is_active
          )
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
 using (
   exists (
     select 1 from public.institution_users self
     where self.id=institution_user_id
       and self.auth_user_id=(select auth.uid()) and self.status='active'
   )
   or public.institution_has_permission(
     (select b.institution_id from public.institution_branches b where b.id=branch_id),
     'team.view',
     branch_id
   )
 );

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
 using (exists (
   select 1 from public.institution_course_runs r
   where r.id=institution_enrollments.course_run_id
     and r.institution_id=institution_enrollments.institution_id
     and public.institution_has_permission(institution_enrollments.institution_id,'trainees.view',r.branch_id)
 ));
drop policy if exists institution_enrollments_insert on public.institution_enrollments;
create policy institution_enrollments_insert on public.institution_enrollments
 for insert to authenticated
 with check (exists (
   select 1 from public.institution_course_runs r
   join public.institution_trainees t on t.id=institution_enrollments.trainee_id
   where r.id=institution_enrollments.course_run_id
     and r.institution_id=institution_enrollments.institution_id
     and t.institution_id=institution_enrollments.institution_id
     and r.branch_id is not distinct from t.branch_id
     and public.institution_has_permission(institution_enrollments.institution_id,'trainees.manage',r.branch_id)
 ));
drop policy if exists institution_enrollments_update on public.institution_enrollments;
create policy institution_enrollments_update on public.institution_enrollments
 for update to authenticated
 using (exists (
   select 1 from public.institution_course_runs r
   where r.id=institution_enrollments.course_run_id
     and r.institution_id=institution_enrollments.institution_id
     and public.institution_has_permission(institution_enrollments.institution_id,'trainees.manage',r.branch_id)
 ))
 with check (exists (
   select 1 from public.institution_course_runs r
   join public.institution_trainees t on t.id=institution_enrollments.trainee_id
   where r.id=institution_enrollments.course_run_id
     and r.institution_id=institution_enrollments.institution_id
     and t.institution_id=institution_enrollments.institution_id
     and r.branch_id is not distinct from t.branch_id
     and public.institution_has_permission(institution_enrollments.institution_id,'trainees.manage',r.branch_id)
 ));
drop policy if exists institution_enrollments_delete on public.institution_enrollments;
create policy institution_enrollments_delete on public.institution_enrollments
 for delete to authenticated
 using (exists (
   select 1 from public.institution_course_runs r
   where r.id=institution_enrollments.course_run_id
     and r.institution_id=institution_enrollments.institution_id
     and public.institution_has_permission(institution_enrollments.institution_id,'trainees.manage',r.branch_id)
 ));

drop policy if exists institution_attendance_select on public.institution_attendance;
create policy institution_attendance_select on public.institution_attendance
 for select to authenticated
 using (exists (
   select 1 from public.institution_enrollments e
   join public.institution_course_runs r on r.id=e.course_run_id
   where e.id=institution_attendance.enrollment_id
     and e.institution_id=institution_attendance.institution_id
     and public.institution_has_permission(institution_attendance.institution_id,'trainees.view',r.branch_id)
 ));
drop policy if exists institution_attendance_write on public.institution_attendance;
create policy institution_attendance_write on public.institution_attendance
 for all to authenticated
 using (exists (
   select 1 from public.institution_enrollments e
   join public.institution_course_runs r on r.id=e.course_run_id
   where e.id=institution_attendance.enrollment_id
     and e.institution_id=institution_attendance.institution_id
     and public.institution_has_permission(institution_attendance.institution_id,'trainees.manage',r.branch_id)
 ))
 with check (exists (
   select 1 from public.institution_enrollments e
   join public.institution_course_runs r on r.id=e.course_run_id
   where e.id=institution_attendance.enrollment_id
     and e.institution_id=institution_attendance.institution_id
     and public.institution_has_permission(institution_attendance.institution_id,'trainees.manage',r.branch_id)
 ));

-- Replace broad legacy course/certificate reads with branch-aware permission checks.
drop policy if exists institution_courses_select_member on public.institution_courses;
create policy institution_courses_select_member on public.institution_courses
 for select to authenticated
 using (public.institution_has_permission(institution_id,'courses.view',branch_id));

drop policy if exists institution_courses_insert_manager on public.institution_courses;
create policy institution_courses_insert_manager on public.institution_courses
 for insert to authenticated
 with check (public.institution_has_permission(institution_id,'courses.manage',branch_id));

drop policy if exists institution_courses_update_manager on public.institution_courses;
create policy institution_courses_update_manager on public.institution_courses
 for update to authenticated
 using (public.institution_has_permission(institution_id,'courses.manage',branch_id))
 with check (public.institution_has_permission(institution_id,'courses.manage',branch_id));

drop policy if exists institution_courses_delete_manager on public.institution_courses;
create policy institution_courses_delete_manager on public.institution_courses
 for delete to authenticated
 using (public.institution_has_permission(institution_id,'courses.manage',branch_id));

drop policy if exists certificates_select_member on public.certificates;
drop policy if exists certificates_select_own on public.certificates;
create policy certificates_select_member on public.certificates
 for select to authenticated
 using (public.institution_has_permission(institution_id,'certificates.view',branch_id));

-- Team records remain visible to their own member and to authorized team managers.
drop policy if exists institution_users_manage_by_admin on public.institution_users;
create policy institution_users_manage_by_admin on public.institution_users
 for all to authenticated
 using (public.institution_has_permission(institution_id,'team.manage'))
 with check (public.institution_has_permission(institution_id,'team.manage'));


-- Enforce cross-tenant consistency for branch/course/enrollment relationships.
create or replace function public.validate_institution_course_run_scope()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare course_org uuid; course_branch uuid;
begin
  select institution_id, branch_id into course_org, course_branch
  from public.institution_courses where id = new.course_id;
  if course_org is null or course_org <> new.institution_id then
    raise exception 'Course does not belong to this institution' using errcode='23514';
  end if;
  if new.branch_id is not null and not exists (
    select 1 from public.institution_branches b
    where b.id=new.branch_id and b.institution_id=new.institution_id
  ) then
    raise exception 'Branch does not belong to this institution' using errcode='23514';
  end if;
  if course_branch is not null and new.branch_id is distinct from course_branch then
    raise exception 'Course is assigned to a different branch' using errcode='23514';
  end if;
  return new;
end $fn$;

drop trigger if exists institution_course_run_scope_guard on public.institution_course_runs;
create trigger institution_course_run_scope_guard
before insert or update of institution_id, branch_id, course_id
on public.institution_course_runs
for each row execute function public.validate_institution_course_run_scope();

create or replace function public.validate_institution_enrollment_scope()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare run_org uuid; run_branch uuid; trainee_org uuid; trainee_branch uuid;
begin
  select institution_id, branch_id into run_org, run_branch
  from public.institution_course_runs where id=new.course_run_id;
  select institution_id, branch_id into trainee_org, trainee_branch
  from public.institution_trainees where id=new.trainee_id;
  if run_org is null or trainee_org is null
     or run_org <> new.institution_id or trainee_org <> new.institution_id
     or run_branch is distinct from trainee_branch then
    raise exception 'Enrollment must connect a trainee and course group in the same institution and branch' using errcode='23514';
  end if;
  return new;
end $fn$;

drop trigger if exists institution_enrollment_scope_guard on public.institution_enrollments;
create trigger institution_enrollment_scope_guard
before insert or update of institution_id, course_run_id, trainee_id
on public.institution_enrollments
for each row execute function public.validate_institution_enrollment_scope();

create or replace function public.validate_institution_attendance_scope()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $
begin
  if not exists (
    select 1 from public.institution_enrollments e
    where e.id=new.enrollment_id and e.institution_id=new.institution_id
  ) then
    raise exception 'Attendance enrollment does not belong to this institution' using errcode='23514';
  end if;
  return new;
end $fn$;

drop trigger if exists institution_attendance_scope_guard on public.institution_attendance;
create trigger institution_attendance_scope_guard
before insert or update of institution_id, enrollment_id
on public.institution_attendance
for each row execute function public.validate_institution_attendance_scope();

-- Only an owner may grant/revoke owner status; preserve at least one owner per institution.
create or replace function public.guard_institution_owner_role_changes()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare actor_role text; owner_count integer;
begin
  if new.role is not distinct from old.role then return new; end if;
  if (select auth.uid()) is null then return new; end if;
  select role into actor_role from public.institution_users
  where institution_id=old.institution_id and auth_user_id=(select auth.uid()) and status='active'
  limit 1;
  if (old.role='owner' or new.role='owner') and actor_role is distinct from 'owner' then
    raise exception 'Only an institution owner can change owner privileges' using errcode='42501';
  end if;
  if old.role='owner' and new.role<>'owner' then
    select count(*) into owner_count from public.institution_users
    where institution_id=old.institution_id and role='owner' and status='active';
    if owner_count <= 1 then
      raise exception 'An institution must retain at least one active owner' using errcode='23514';
    end if;
  end if;
  return new;
end $fn$;

drop trigger if exists institution_owner_role_guard on public.institution_users;
create trigger institution_owner_role_guard
before update of role on public.institution_users
for each row execute function public.guard_institution_owner_role_changes();

create table if not exists public.institution_invitations (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  invited_email text not null,
  invited_user_id uuid references auth.users(id) on delete set null,
  role text not null check (role in ('manager','training_manager','registrar','certificate_issuer','branch_manager','viewer')),
  status text not null default 'pending' check (status in ('pending','sent','accepted','revoked','expired')),
  invited_by uuid not null references auth.users(id) on delete restrict,
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (invited_email = lower(btrim(invited_email)))
);
create unique index if not exists institution_invitations_pending_email_uidx
  on public.institution_invitations(institution_id, invited_email)
  where status in ('pending','sent');
create index if not exists institution_invitations_org_status_idx
  on public.institution_invitations(institution_id, status, created_at desc);
alter table public.institution_invitations enable row level security;
drop policy if exists institution_invitations_select_manager on public.institution_invitations;
create policy institution_invitations_select_manager on public.institution_invitations
 for select to authenticated
 using (public.institution_has_permission(institution_id,'team.view'));
drop policy if exists institution_invitations_revoke_manager on public.institution_invitations;
create policy institution_invitations_revoke_manager on public.institution_invitations
 for update to authenticated
 using (public.institution_has_permission(institution_id,'team.manage'))
 with check (public.institution_has_permission(institution_id,'team.manage'));

-- Explicit Data API privileges; row access remains constrained by the RLS policies above.
grant select, insert, update, delete on public.institution_branches to authenticated;
grant select on public.institution_role_permissions to authenticated;
grant select, insert, update, delete on public.institution_user_branches to authenticated;
grant select, insert, update, delete on public.institution_trainees to authenticated;
grant select, insert, update, delete on public.institution_course_runs to authenticated;
grant select, insert, update, delete on public.institution_enrollments to authenticated;
grant select, insert, update, delete on public.institution_attendance to authenticated;
grant select, update on public.institution_invitations to authenticated;
grant update on public.institution_users to authenticated;
grant select, insert, update, delete on public.institution_courses to authenticated;

commit;
