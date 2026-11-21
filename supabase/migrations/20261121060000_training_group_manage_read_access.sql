-- Staff who can manage courses must also be able to read the courses,
-- trainers, and training groups they manage. Keep branch scoping intact.
drop policy if exists institution_course_runs_select on public.institution_course_runs;
create policy institution_course_runs_select on public.institution_course_runs
 for select to authenticated
 using (
  public.institution_has_permission(institution_id,'courses.view',branch_id)
  or public.institution_has_permission(institution_id,'courses.manage',branch_id)
 );

drop policy if exists institution_courses_select_member on public.institution_courses;
create policy institution_courses_select_member on public.institution_courses
 for select to authenticated
 using (
  public.institution_has_permission(institution_id,'courses.view',branch_id)
  or public.institution_has_permission(institution_id,'courses.manage',branch_id)
 );

drop policy if exists institution_trainers_select on public.institution_trainers;
create policy institution_trainers_select on public.institution_trainers
 for select to authenticated
 using (
  public.institution_has_permission(institution_id,'courses.view',branch_id)
  or public.institution_has_permission(institution_id,'courses.manage',branch_id)
 );
