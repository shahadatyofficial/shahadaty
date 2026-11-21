drop policy if exists institution_public_profiles_admin_select on public.institution_public_profiles;
create policy institution_public_profiles_admin_select on public.institution_public_profiles for select to authenticated using(public.is_platform_admin());
drop policy if exists institution_public_profiles_admin_update on public.institution_public_profiles;
create policy institution_public_profiles_admin_update on public.institution_public_profiles for update to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());
create or replace function public.guard_institution_public_profile_review_fields()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if not public.is_platform_admin() then
  if new.status not in ('draft','pending') then raise exception 'INSTITUTION_PROFILE_REVIEW_REQUIRED'; end if;
  new.reviewed_at:=case when tg_op='UPDATE' then old.reviewed_at else null end;
  new.reviewed_by:=case when tg_op='UPDATE' then old.reviewed_by else null end;
  if tg_op='INSERT' then new.rejection_reason:=null; end if;
 end if;
 return new;
end;
$$;
