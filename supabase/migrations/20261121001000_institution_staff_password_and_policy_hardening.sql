-- Restrict permission override writes and add a server-verified first-login password completion.
drop policy if exists institution_user_permission_overrides_manage on public.institution_user_permission_overrides;
drop policy if exists institution_user_permission_overrides_insert on public.institution_user_permission_overrides;
drop policy if exists institution_user_permission_overrides_update on public.institution_user_permission_overrides;
drop policy if exists institution_user_permission_overrides_delete on public.institution_user_permission_overrides;
create policy institution_user_permission_overrides_insert on public.institution_user_permission_overrides for insert to authenticated with check (
 public.institution_has_permission(institution_id,'team.manage')
 and exists(select 1 from public.institution_users iu where iu.id=institution_user_permission_overrides.institution_user_id and iu.institution_id=institution_user_permission_overrides.institution_id and iu.role<>'owner')
);
create policy institution_user_permission_overrides_update on public.institution_user_permission_overrides for update to authenticated using (public.institution_has_permission(institution_id,'team.manage')) with check (
 public.institution_has_permission(institution_id,'team.manage')
 and exists(select 1 from public.institution_users iu where iu.id=institution_user_permission_overrides.institution_user_id and iu.institution_id=institution_user_permission_overrides.institution_id and iu.role<>'owner')
);
create policy institution_user_permission_overrides_delete on public.institution_user_permission_overrides for delete to authenticated using (public.institution_has_permission(institution_id,'team.manage'));
create or replace function public.complete_institution_staff_password_change()
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $function$
begin
 if (select auth.uid()) is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;
 if not exists(select 1 from public.institution_users iu join public.institution_staff_profiles sp on sp.institution_user_id=iu.id where iu.auth_user_id=(select auth.uid()) and iu.status='active') then raise exception 'ACTIVE_STAFF_MEMBERSHIP_REQUIRED'; end if;
 update auth.users set raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('must_change_password',false) where id=(select auth.uid());
 return found;
end;
$function$;
revoke all on function public.complete_institution_staff_password_change() from public,anon;
grant execute on function public.complete_institution_staff_password_change() to authenticated;
