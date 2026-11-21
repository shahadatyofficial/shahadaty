-- Allow staff with course-management permission to see the sessions
-- attached to the training groups they manage. Branch scoping is preserved.
drop policy if exists institution_course_sessions_select on public.institution_course_sessions;

create policy institution_course_sessions_select
on public.institution_course_sessions
for select
to authenticated
using (
  exists (
    select 1
    from public.institution_course_runs r
    where r.id = institution_course_sessions.course_run_id
      and r.institution_id = institution_course_sessions.institution_id
      and (
        public.institution_has_permission(institution_course_sessions.institution_id, 'courses.view', r.branch_id)
        or public.institution_has_permission(institution_course_sessions.institution_id, 'courses.manage', r.branch_id)
      )
  )
);
