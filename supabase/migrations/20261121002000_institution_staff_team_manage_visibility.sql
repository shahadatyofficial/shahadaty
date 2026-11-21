drop policy if exists institution_user_permission_overrides_select on public.institution_user_permission_overrides;
create policy institution_user_permission_overrides_select on public.institution_user_permission_overrides for select to authenticated using (
 public.institution_has_permission(institution_id,'team.view') or public.institution_has_permission(institution_id,'team.manage')
);
drop policy if exists institution_staff_profiles_select on public.institution_staff_profiles;
create policy institution_staff_profiles_select on public.institution_staff_profiles for select to authenticated using (
 public.institution_has_permission(institution_id,'team.view') or public.institution_has_permission(institution_id,'team.manage')
);
