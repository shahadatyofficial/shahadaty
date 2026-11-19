-- Enforce course-run capacity and closed-state rules at the database boundary.
-- Additive only: existing enrollments and attendance records are not modified.

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

  if v_run_status in ('completed','cancelled')
     and new.status in ('enrolled','attending') then
    raise exception 'COURSE_RUN_CLOSED' using errcode = '23514';
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
