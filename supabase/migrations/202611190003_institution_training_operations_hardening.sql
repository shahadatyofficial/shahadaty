-- Complete institution training operations with database-enforced enrollment,
-- attendance, completion, and certificate linkage. All changes are additive.

alter table public.certificates
  add column if not exists enrollment_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'certificates_enrollment_id_fkey'
      and conrelid = 'public.certificates'::regclass
  ) then
    alter table public.certificates
      add constraint certificates_enrollment_id_fkey
      foreign key (enrollment_id)
      references public.institution_enrollments(id)
      on delete set null;
  end if;
end $$;

create unique index if not exists certificates_enrollment_id_uidx
  on public.certificates(enrollment_id)
  where enrollment_id is not null;

-- A group accepts new active enrollments only while registration is open
-- or the training is already in progress. Capacity is serialized per run.
create or replace function public.enforce_institution_course_run_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
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
$function$;

revoke all on function public.enforce_institution_course_run_capacity() from public, anon, authenticated;
drop trigger if exists institution_course_run_capacity_guard on public.institution_enrollments;
create trigger institution_course_run_capacity_guard
before insert or update of course_run_id, status
on public.institution_enrollments
for each row
execute function public.enforce_institution_course_run_capacity();

-- If a group has scheduled sessions, a trainee can only be marked complete
-- after all sessions are marked completed and attendance is recorded for each
-- scheduled date. Groups without a session schedule retain manual completion.
create or replace function public.guard_institution_enrollment_completion()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_session_count integer;
  v_pending_count integer;
  v_missing_attendance integer;
begin
  if new.status is distinct from 'completed'
     or old.status is not distinct from 'completed' then
    return new;
  end if;

  select count(*) into v_session_count
  from public.institution_course_sessions s
  where s.institution_id = new.institution_id
    and s.course_run_id = new.course_run_id;

  if v_session_count > 0 then
    select count(*) into v_pending_count
    from public.institution_course_sessions s
    where s.institution_id = new.institution_id
      and s.course_run_id = new.course_run_id
      and s.status <> 'completed';

    if v_pending_count > 0 then
      raise exception 'TRAINING_SESSIONS_INCOMPLETE' using errcode = '23514';
    end if;

    select count(*) into v_missing_attendance
    from (
      select distinct s.session_date
      from public.institution_course_sessions s
      where s.institution_id = new.institution_id
        and s.course_run_id = new.course_run_id
    ) scheduled
    where not exists (
      select 1
      from public.institution_attendance a
      where a.institution_id = new.institution_id
        and a.enrollment_id = new.id
        and a.session_date = scheduled.session_date
    );

    if v_missing_attendance > 0 then
      raise exception 'TRAINING_ATTENDANCE_INCOMPLETE' using errcode = '23514';
    end if;
  end if;

  if new.completed_at is null then
    new.completed_at := now();
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_institution_enrollment_completion() from public, anon, authenticated;
drop trigger if exists institution_enrollment_completion_guard on public.institution_enrollments;
create trigger institution_enrollment_completion_guard
before update of status, completed_at
on public.institution_enrollments
for each row
execute function public.guard_institution_enrollment_completion();

-- Attendance dates must correspond to a scheduled, non-cancelled session
-- whenever a group has a session schedule. Legacy groups without sessions
-- continue to use date-based attendance.
create or replace function public.validate_institution_attendance_scope()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_run_id uuid;
  v_session_count integer;
begin
  select e.course_run_id into v_run_id
  from public.institution_enrollments e
  where e.id = new.enrollment_id
    and e.institution_id = new.institution_id;

  if v_run_id is null then
    raise exception 'Attendance enrollment does not belong to this institution' using errcode = '23514';
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
$function$;

revoke all on function public.validate_institution_attendance_scope() from public, anon, authenticated;
drop trigger if exists institution_attendance_scope_guard on public.institution_attendance;
create trigger institution_attendance_scope_guard
before insert or update of institution_id, enrollment_id, session_date
on public.institution_attendance
for each row
execute function public.validate_institution_attendance_scope();

-- Link a training certificate to the exact completed enrollment. The enrollment
-- row lock plus unique index makes retries idempotent and prevents duplicate awards.
create or replace function public.issue_certificate(p_payload jsonb)
returns table(cert_id uuid, cert_number text)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_inst uuid := nullif(p_payload->>'institution_id','')::uuid;
  v_branch uuid := nullif(p_payload->>'branch_id','')::uuid;
  v_course uuid := nullif(p_payload->>'course_id','')::uuid;
  v_trainee uuid := nullif(p_payload->>'trainee_id','')::uuid;
  v_enrollment_id uuid := nullif(p_payload->>'enrollment_id','')::uuid;
  v_enrollment public.institution_enrollments%rowtype;
  v_existing public.certificates%rowtype;
  v_inst_row public.institutions%rowtype;
  v_sub public.subscriptions%rowtype;
  v_id uuid;
  v_number text;
  v_acquisition_date date := coalesce(nullif(p_payload->>'acquisition_date','')::date,nullif(p_payload->>'issue_date','')::date);
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if v_inst is null then raise exception 'INSTITUTION_REQUIRED'; end if;
  if not public.institution_has_permission(v_inst,'certificates.issue',v_branch) then
    raise exception 'NOT_ALLOWED';
  end if;

  select i.* into v_inst_row from public.institutions i
  where i.id=v_inst for update;
  if not found then raise exception 'INSTITUTION_NOT_FOUND'; end if;
  if v_inst_row.status<>'approved' then raise exception 'INSTITUTION_NOT_APPROVED'; end if;

  if v_branch is not null and not exists (
    select 1 from public.institution_branches b
    where b.id=v_branch and b.institution_id=v_inst and b.is_active
  ) then raise exception 'INVALID_BRANCH'; end if;

  if v_course is not null and not exists (
    select 1 from public.institution_courses c
    where c.id=v_course and c.institution_id=v_inst and c.is_active
      and (c.branch_id is null or c.branch_id is not distinct from v_branch)
  ) then raise exception 'INVALID_COURSE'; end if;

  if v_trainee is not null and not exists (
    select 1 from public.institution_trainees t
    where t.id=v_trainee and t.institution_id=v_inst and t.status='active'
      and t.branch_id is not distinct from v_branch
  ) then raise exception 'INVALID_TRAINEE'; end if;

  if v_enrollment_id is not null then
    select e.* into v_enrollment
    from public.institution_enrollments e
    where e.id=v_enrollment_id and e.institution_id=v_inst
    for update;

    if not found or v_enrollment.status<>'completed' then
      raise exception 'TRAINING_NOT_COMPLETED' using errcode='23514';
    end if;

    if v_enrollment.trainee_id is distinct from v_trainee then
      raise exception 'ENROLLMENT_MISMATCH' using errcode='23514';
    end if;

    if not exists (
      select 1
      from public.institution_course_runs r
      where r.id=v_enrollment.course_run_id
        and r.institution_id=v_inst
        and r.branch_id is not distinct from v_branch
        and r.course_id is not distinct from v_course
    ) then
      raise exception 'ENROLLMENT_MISMATCH' using errcode='23514';
    end if;

    select c.* into v_existing
    from public.certificates c
    where c.enrollment_id=v_enrollment_id
    limit 1;

    if found then
      return query select v_existing.id,v_existing.cert_number;
      return;
    end if;
  end if;

  select s.* into v_sub from public.subscriptions s
  left join public.packages p on p.id=s.package_id
  where s.institution_id=v_inst and s.status='active'
    and (s.starts_at is null or s.starts_at<=now())
    and (s.ends_at is null or s.ends_at>now())
    and (s.payment_status='paid' or (coalesce(s.amount,0)=0 and p.name='trial'))
  order by s.created_at desc limit 1 for update of s;
  if not found then raise exception 'SUBSCRIPTION_INACTIVE_OR_UNPAID'; end if;
  if v_sub.quota_used>=v_sub.quota_limit or v_inst_row.quota_used>=v_inst_row.quota_total then
    raise exception 'QUOTA_EXCEEDED';
  end if;
  if coalesce(trim(p_payload->>'student_name'),'')='' or coalesce(trim(p_payload->>'course'),'')='' or v_acquisition_date is null then
    raise exception 'REQUIRED_FIELDS';
  end if;
  if nullif(trim(p_payload->>'student_email'),'') is not null
     and position('@' in trim(p_payload->>'student_email'))=0 then
    raise exception 'INVALID_STUDENT_EMAIL';
  end if;

  v_number:=public.generate_certificate_number();
  insert into public.certificates(
    institution_id,branch_id,trainee_id,course_id,enrollment_id,cert_number,student_name,student_name_en,
    student_national_id,student_phone,student_email,course,specialization,issue_date,
    acquisition_date,expiry_date,grade,grade_value,duration,governorate,center,pdf_url,
    qr_code,visible_to_companies,consent_given_at,status,added_by
  ) values (
    v_inst,v_branch,v_trainee,v_course,v_enrollment_id,v_number,trim(p_payload->>'student_name'),
    nullif(trim(p_payload->>'student_name_en'),''),nullif(trim(p_payload->>'student_national_id'),''),
    nullif(trim(p_payload->>'student_phone'),''),nullif(lower(trim(p_payload->>'student_email')),''),
    trim(p_payload->>'course'),nullif(trim(p_payload->>'specialization'),''),current_date,
    v_acquisition_date,nullif(p_payload->>'expiry_date','')::date,
    nullif(trim(p_payload->>'grade'),''),nullif(p_payload->>'grade_value','')::numeric,
    nullif(trim(p_payload->>'duration'),''),nullif(trim(p_payload->>'governorate'),''), 
    nullif(trim(p_payload->>'center'),''),nullif(trim(p_payload->>'pdf_url'),''),
    nullif(trim(p_payload->>'qr_code'),''),coalesce((p_payload->>'visible_to_companies')::boolean,false),
    case when coalesce((p_payload->>'visible_to_companies')::boolean,false) then now() else null end,
    'active','institution'
  ) returning id into v_id;

  update public.institutions set quota_used=quota_used+1,updated_at=now() where id=v_inst;
  update public.subscriptions set quota_used=quota_used+1,updated_at=now() where id=v_sub.id;
  insert into public.activity_log(actor_id,actor_type,action,target_type,target_id,details)
  values(v_uid,'institution','certificate_issued','certificate',v_id,
    jsonb_build_object('cert_number',v_number,'institution_id',v_inst,'branch_id',v_branch,'enrollment_id',v_enrollment_id)::text);
  return query select v_id,v_number;
end;
$function$;

revoke all on function public.issue_certificate(jsonb) from public, anon;
grant execute on function public.issue_certificate(jsonb) to authenticated;
