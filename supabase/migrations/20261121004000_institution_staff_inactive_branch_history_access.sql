-- Allow institution owners/managers to review historical records in inactive branches.
create or replace function public.institution_has_permission(p_institution_id uuid,p_permission text,p_branch_id uuid default null)
returns boolean language sql stable security definer set search_path=public,pg_temp
as $function$
select exists (
 select 1 from public.institution_users iu
 where iu.institution_id=p_institution_id and iu.auth_user_id=(select auth.uid()) and iu.status='active'
 and (iu.role='owner' or coalesce(
  (select uo.is_granted from public.institution_user_permission_overrides uo where uo.institution_user_id=iu.id and uo.institution_id=iu.institution_id and uo.permission_key=p_permission),
  exists(select 1 from public.institution_role_permissions rp where rp.role=iu.role and rp.permission_key=p_permission)
 ))
 and (
  (p_branch_id is null and iu.role in ('owner','manager'))
  or (p_branch_id is not null and exists(
   select 1 from public.institution_branches b
   where b.id=p_branch_id and b.institution_id=p_institution_id
    and (b.is_active or iu.role in ('owner','manager'))
    and (iu.role in ('owner','manager') or exists(
     select 1 from public.institution_user_branches iub where iub.institution_user_id=iu.id and iub.branch_id=b.id
    ))
  ))
 )
);
$function$;
