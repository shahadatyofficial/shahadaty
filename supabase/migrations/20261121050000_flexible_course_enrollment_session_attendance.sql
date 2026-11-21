-- Flexible course-level enrollment and session-linked attendance.
-- Existing group enrollments and attendance remain intact.
alter table public.institution_enrollments
  add column if not exists course_id uuid;

update public.institution_enrollments e
set course_id = r.course_id
from public.institution_course_runs r
where r.id = e.course_run_id
  and e.course_id is null;

alter table public.institution_enrollments
  alter column course_run_id drop not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.institution_enrollments'::regclass
      and conname = 'institution_enrollments_course_id_fkey'
  ) then
    alter table public.institution_enrollments
      add constraint institution_enrollments_course_id_fkey
      foreign key (course_id) references public.institution_courses(id) on delete cascade;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.institution_enrollments'::regclass
      and conname = 'institution_enrollments_course_link_check'
  ) then
    alter table public.institution_enrollments
      add constraint institution_enrollments_course_link_check
      check (course_id is not null or course_run_id is not null);
  end if;
end $$;

create index if not exists institution_enrollments_course_id_idx
  on public.institution_enrollments(institution_id, course_id, enrolled_at desc);
create unique index if not exists institution_enrollments_course_level_unique
  on public.institution_enrollments(institution_id, course_id, trainee_id)
  where course_run_id is null;

-- A session number is generated within each training group and never typed by staff.
alter table public.institution_course_sessions
  add column if not exists session_number integer;

with numbered as (
  select id, row_number() over (
    partition by course_run_id order by session_date, starts_at nulls first, created_at, id
  )::integer as generated_number
  from public.institution_course_sessions
)
update public.institution_course_sessions s
set session_number = numbered.generated_number
from numbered
where numbered.id = s.id
  and s.session_number is null;

alter table public.institution_course_sessions
  alter column session_number set not null;

create unique index if not exists institution_course_sessions_run_number_unique
  on public.institution_course_sessions(course_run_id, session_number);

create or replace function public.assign_institution_course_session_number()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare next_number integer;
begin
  perform 1 from public.institution_course_runs
    where id = new.course_run_id and institution_id = new.institution_id
    for update;
  if not found then
    raise exception 'COURSE_RUN_NOT_FOUND' using errcode = '23503';
  end if;
  select coalesce(max(session_number), 0) + 1
    into next_number
  from public.institution_course_sessions
  where course_run_id = new.course_run_id;
  new.session_number := next_number;
  return new;
end;
$$;

drop trigger if exists institution_course_session_number_guard
  on public.institution_course_sessions;
create trigger institution_course_session_number_guard
before insert on public.institution_course_sessions
for each row execute function public.assign_institution_course_session_number();

alter table public.institution_attendance
  add column if not exists session_id uuid references public.institution_course_sessions(id) on delete set null;
alter table public.institution_attendance
  drop constraint if exists institution_attendance_enrollment_id_session_date_key;
alter table public.institution_attendance
  add constraint institution_attendance_enrollment_id_session_id_key
  unique (enrollment_id, session_id);

create index if not exists institution_attendance_session_id_idx
  on public.institution_attendance(session_id) where session_id is not null;

create or replace function public.validate_institution_enrollment_scope()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_course_org uuid;
  v_course_branch uuid;
  v_run_org uuid;
  v_run_branch uuid;
  v_run_course uuid;
  v_trainee_org uuid;
  v_trainee_branch uuid;
begin
  select institution_id, branch_id into v_trainee_org, v_trainee_branch
  from public.institution_trainees where id = new.trainee_id;

  if v_trainee_org is null or v_trainee_org <> new.institution_id then
    raise exception 'TRAINEE_NOT_IN_INSTITUTION' using errcode = '23514';
  end if;

  if new.course_run_id is not null then
    select institution_id, branch_id, course_id
      into v_run_org, v_run_branch, v_run_course
    from public.institution_course_runs where id = new.course_run_id;
    if v_run_org is null or v_run_org <> new.institution_id then
      raise exception 'COURSE_RUN_NOT_IN_INSTITUTION' using errcode = '23514';
    end if;
    if new.course_id is null then
      new.course_id := v_run_course;
    elsif new.course_id <> v_run_course then
      raise exception 'ENROLLMENT_COURSE_RUN_MISMATCH' using errcode = '23514';
    end if;
    if v_run_branch is distinct from v_trainee_branch then
      raise exception 'ENROLLMENT_BRANCH_MISMATCH' using errcode = '23514';
    end if;
  end if;

  select institution_id, branch_id into v_course_org, v_course_branch
  from public.institution_courses where id = new.course_id;
  if v_course_org is null or v_course_org <> new.institution_id then
    raise exception 'COURSE_NOT_IN_INSTITUTION' using errcode = '23514';
  end if;
  if v_course_branch is not null and v_course_branch is distinct from v_trainee_branch then
    raise exception 'ENROLLMENT_BRANCH_MISMATCH' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_institution_course_run_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_run_institution uuid;
  v_run_status text;
  v_capacity integer;
  v_active_count bigint;
begin
  if tg_op = 'UPDATE'
     and new.course_run_id is not distinct from old.course_run_id
     and new.status is not distinct from old.status then
    return new;
  end if;

  if tg_op = 'INSERT' and new.status not in ('enrolled','attending') then
    raise exception 'INVALID_INITIAL_ENROLLMENT_STATUS' using errcode = '23514';
  end if;

  -- A course-level enrollment has no group capacity until it is assigned to a group.
  if new.course_run_id is null then
    return new;
  end if;

  select r.institution_id, r.status, r.capacity
    into v_run_institution, v_run_status, v_capacity
  from public.institution_course_runs r
  where r.id = new.course_run_id
  for update;

  if not found or v_run_institution is distinct from new.institution_id then
    raise exception 'COURSE_RUN_NOT_FOUND' using errcode = '23503';
  end if;

  if new.status in ('enrolled','attending') and v_run_status not in ('open','in_progress') then
    raise exception 'COURSE_RUN_NOT_OPEN' using errcode = '23514';
  end if;

  if new.status in ('enrolled','attending') and v_capacity is not null then
    if tg_op = 'UPDATE' then
      select count(*) into v_active_count
      from public.institution_enrollments e
      where e.course_run_id = new.course_run_id
        and e.status in ('enrolled','attending')
        and e.id <> old.id;
    else
      select count(*) into v_active_count
      from public.institution_enrollments e
      where e.course_run_id = new.course_run_id
        and e.status in ('enrolled','attending');
    end if;
    if v_active_count >= v_capacity then
      raise exception 'COURSE_RUN_CAPACITY_REACHED' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.guard_institution_enrollment_completion()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $
declare
  v_session_count integer;
  v_pending_count integer;
  v_missing_attendance integer;
begin
  if new.status is distinct from 'completed'
     or old.status is not distinct from 'completed' then
    return new;
  end if;
  if new.course_run_id is null then
    if new.completed_at is null then new.completed_at := now(); end if;
    return new;
  end if;

  select count(*) into v_session_count
  from public.institution_course_sessions s
  where s.institution_id = new.institution_id
    and s.course_run_id = new.course_run_id
    and s.status <> 'cancelled';

  if v_session_count > 0 then
    select count(*) into v_pending_count
    from public.institution_course_sessions s
    where s.institution_id = new.institution_id
      and s.course_run_id = new.course_run_id
      and s.status not in ('completed','cancelled');

    if v_pending_count > 0 then
      raise exception 'TRAINING_SESSIONS_INCOMPLETE' using errcode = '23514';
    end if;

    select count(*) into v_missing_attendance
    from public.institution_course_sessions s
    where s.institution_id = new.institution_id
      and s.course_run_id = new.course_run_id
      and s.status <> 'cancelled'
      and not exists (
        select 1
        from public.institution_attendance a
        where a.institution_id = new.institution_id
          and a.enrollment_id = new.id
          and (
            a.session_id = s.id
            or (a.session_id is null and a.session_date = s.session_date)
          )
      );

    if v_missing_attendance > 0 then
      raise exception 'TRAINING_ATTENDANCE_INCOMPLETE' using errcode = '23514';
    end if;
  end if;

  if new.completed_at is null then new.completed_at := now(); end if;
  return new;
end;
$;

drop policy if exists institution_enrollments_insert on public.institution_enrollments;
create policy institution_enrollments_insert on public.institution_enrollments
for insert to authenticated
with check (
  exists (
    select 1
    from public.institution_trainees t
    join public.institution_courses c
      on c.id = institution_enrollments.course_id
     and c.institution_id = institution_enrollments.institution_id
    left join public.institution_course_runs r
      on r.id = institution_enrollments.course_run_id
     and r.institution_id = institution_enrollments.institution_id
    where t.id = institution_enrollments.trainee_id
      and t.institution_id = institution_enrollments.institution_id
      and (institution_enrollments.course_run_id is null or r.id is not null)
      and (r.id is null or r.course_id = c.id)
      and (r.id is null or r.branch_id is not distinct from t.branch_id)
      and (c.branch_id is null or c.branch_id is not distinct from t.branch_id)
      and public.institution_has_permission(
        institution_enrollments.institution_id,
        'trainees.manage',
        coalesce(r.branch_id, t.branch_id)
      )
  )
);

drop policy if exists institution_enrollments_select on public.institution_enrollments;
create policy institution_enrollments_select on public.institution_enrollments
for select to authenticated
using (
  exists (
    select 1
    from public.institution_trainees t
    join public.institution_courses c
      on c.id = institution_enrollments.course_id
     and c.institution_id = institution_enrollments.institution_id
    left join public.institution_course_runs r
      on r.id = institution_enrollments.course_run_id
     and r.institution_id = institution_enrollments.institution_id
    where t.id = institution_enrollments.trainee_id
      and t.institution_id = institution_enrollments.institution_id
      and (institution_enrollments.course_run_id is null or r.id is not null)
      and public.institution_has_permission(
        institution_enrollments.institution_id,
        'trainees.view',
        coalesce(r.branch_id, t.branch_id)
      )
  )
);

drop policy if exists institution_enrollments_update on public.institution_enrollments;
create policy institution_enrollments_update on public.institution_enrollments
for update to authenticated
using (
  exists (
    select 1
    from public.institution_trainees t
    join public.institution_courses c
      on c.id = institution_enrollments.course_id
     and c.institution_id = institution_enrollments.institution_id
    left join public.institution_course_runs r
      on r.id = institution_enrollments.course_run_id
     and r.institution_id = institution_enrollments.institution_id
    where t.id = institution_enrollments.trainee_id
      and t.institution_id = institution_enrollments.institution_id
      and public.institution_has_permission(
        institution_enrollments.institution_id,
        'trainees.manage',
        coalesce(r.branch_id, t.branch_id)
      )
  )
)
with check (
  exists (
    select 1
    from public.institution_trainees t
    join public.institution_courses c
      on c.id = institution_enrollments.course_id
     and c.institution_id = institution_enrollments.institution_id
    left join public.institution_course_runs r
      on r.id = institution_enrollments.course_run_id
     and r.institution_id = institution_enrollments.institution_id
    where t.id = institution_enrollments.trainee_id
      and t.institution_id = institution_enrollments.institution_id
      and (institution_enrollments.course_run_id is null or r.id is not null)
      and (r.id is null or r.course_id = c.id)
      and (r.id is null or r.branch_id is not distinct from t.branch_id)
      and (c.branch_id is null or c.branch_id is not distinct from t.branch_id)
      and public.institution_has_permission(
        institution_enrollments.institution_id,
        'trainees.manage',
        coalesce(r.branch_id, t.branch_id)
      )
  )
);

create or replace function public.validate_institution_attendance_scope()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_run_id uuid;
  v_enrollment_institution uuid;
  v_session_run_id uuid;
  v_session_date date;
  v_session_status text;
  v_session_count integer;
begin
  select e.course_run_id, e.institution_id
    into v_run_id, v_enrollment_institution
  from public.institution_enrollments e
  where e.id = new.enrollment_id
    and e.institution_id = new.institution_id;

  if v_enrollment_institution is null or v_run_id is null then
    raise exception 'ATTENDANCE_REQUIRES_GROUP_ENROLLMENT' using errcode = '23514';
  end if;

  if new.session_id is not null then
    select s.course_run_id, s.session_date, s.status
      into v_session_run_id, v_session_date, v_session_status
    from public.institution_course_sessions s
    where s.id = new.session_id
      and s.institution_id = new.institution_id;
    if v_session_run_id is null
       or v_session_run_id <> v_run_id
       or v_session_date <> new.session_date
       or v_session_status = 'cancelled' then
      raise exception 'ATTENDANCE_SESSION_MISMATCH' using errcode = '23514';
    end if;
    return new;
  end if;

  select count(*) into v_session_count
  from public.institution_course_sessions s
  where s.institution_id = new.institution_id
    and s.course_run_id = v_run_id;

  if v_session_count > 0 and not exists (
    select 1
    from public.institution_course_sessions s
    where s.institution_id = new.institution_id
      and s.course_run_id = v_run_id
      and s.session_date = new.session_date
      and s.status <> 'cancelled'
  ) then
    raise exception 'ATTENDANCE_DATE_NOT_SCHEDULED' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.assign_institution_course_session_number() from public, anon, authenticated;
