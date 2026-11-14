drop policy if exists graduate_profiles_insert_own on public.graduate_profiles;
create policy graduate_profiles_insert_own on public.graduate_profiles
for insert to authenticated
with check (
  auth_user_id = (select auth.uid())
  and exists (
    select 1 from public.graduate_access_requests r
    where r.auth_user_id = (select auth.uid()) and r.status = 'approved'
  )
);