create or replace function public.guard_institution_public_profile_review_fields()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
 if not exists (
  select 1 from public.platform_admins pa
  where pa.auth_user_id = (select auth.uid()) and pa.status = 'active'
 ) then
  if new.status not in ('draft','pending') then
   raise exception 'INSTITUTION_PROFILE_REVIEW_REQUIRED';
  end if;
  new.reviewed_at := case when tg_op = 'UPDATE' then old.reviewed_at else null end;
  new.reviewed_by := case when tg_op = 'UPDATE' then old.reviewed_by else null end;
  if tg_op = 'INSERT' then new.rejection_reason := null; end if;
 end if;
 return new;
end;
$$;
create trigger institution_public_profile_review_guard
before insert or update on public.institution_public_profiles
for each row execute function public.guard_institution_public_profile_review_fields();
