-- Fix storage policy column resolution: qualify storage.objects.name so
-- foldername() receives the uploaded object path, not institutions.name.
drop policy if exists institution_logos_member_upload on storage.objects;
create policy institution_logos_member_upload on storage.objects
for insert to authenticated
with check (
 bucket_id='institution-logos'
 and exists (
  select 1 from public.institutions i
  where i.id::text=(storage.foldername(storage.objects.name))[1]
   and (i.auth_user_id=(select auth.uid()) or exists (
    select 1 from public.institution_users iu
    where iu.institution_id=i.id and iu.auth_user_id=(select auth.uid())
      and iu.status='active' and iu.role in ('owner','manager')
   ))
 )
);
drop policy if exists institution_logos_member_update on storage.objects;
create policy institution_logos_member_update on storage.objects
for update to authenticated
using (
 bucket_id='institution-logos'
 and exists (
  select 1 from public.institutions i
  where i.id::text=(storage.foldername(storage.objects.name))[1]
   and (i.auth_user_id=(select auth.uid()) or exists (
    select 1 from public.institution_users iu
    where iu.institution_id=i.id and iu.auth_user_id=(select auth.uid())
      and iu.status='active' and iu.role in ('owner','manager')
   ))
 )
)
with check (
 bucket_id='institution-logos'
 and exists (
  select 1 from public.institutions i
  where i.id::text=(storage.foldername(storage.objects.name))[1]
   and (i.auth_user_id=(select auth.uid()) or exists (
    select 1 from public.institution_users iu
    where iu.institution_id=i.id and iu.auth_user_id=(select auth.uid())
      and iu.status='active' and iu.role in ('owner','manager')
   ))
 )
);
drop policy if exists institution_logos_member_delete on storage.objects;
create policy institution_logos_member_delete on storage.objects
for delete to authenticated
using (
 bucket_id='institution-logos'
 and exists (
  select 1 from public.institutions i
  where i.id::text=(storage.foldername(storage.objects.name))[1]
   and (i.auth_user_id=(select auth.uid()) or exists (
    select 1 from public.institution_users iu
    where iu.institution_id=i.id and iu.auth_user_id=(select auth.uid())
      and iu.status='active' and iu.role in ('owner','manager')
   ))
 );
