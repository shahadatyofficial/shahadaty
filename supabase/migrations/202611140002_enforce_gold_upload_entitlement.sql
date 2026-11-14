drop policy if exists graduate_gold_files_select_own_or_admin on storage.objects;
create policy graduate_gold_files_select_own_or_admin on storage.objects
for select to authenticated
using (
  bucket_id = 'graduate-gold-private'
  and (
    public.is_platform_admin()
    or (
      (storage.foldername(name))[1] = (select auth.uid())::text
      and exists (
        select 1 from public.graduate_membership_requests m
        where m.auth_user_id = (select auth.uid())
          and m.status = 'approved' and m.ends_at > now()
      )
    )
  )
);

drop policy if exists graduate_gold_files_insert_own on storage.objects;
create policy graduate_gold_files_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'graduate-gold-private'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.graduate_membership_requests m
    where m.auth_user_id = (select auth.uid())
      and m.status = 'approved' and m.ends_at > now()
  )
);

drop policy if exists graduate_gold_files_update_own on storage.objects;
create policy graduate_gold_files_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'graduate-gold-private'
  and (
    public.is_platform_admin()
    or (
      (storage.foldername(name))[1] = (select auth.uid())::text
      and exists (
        select 1 from public.graduate_membership_requests m
        where m.auth_user_id = (select auth.uid())
          and m.status = 'approved' and m.ends_at > now()
      )
    )
  )
)
with check (
  bucket_id = 'graduate-gold-private'
  and (
    public.is_platform_admin()
    or (
      (storage.foldername(name))[1] = (select auth.uid())::text
      and exists (
        select 1 from public.graduate_membership_requests m
        where m.auth_user_id = (select auth.uid())
          and m.status = 'approved' and m.ends_at > now()
      )
    )
  )
);

drop policy if exists graduate_gold_files_delete_own_or_admin on storage.objects;
create policy graduate_gold_files_delete_own_or_admin on storage.objects
for delete to authenticated
using (
  bucket_id = 'graduate-gold-private'
  and (
    public.is_platform_admin()
    or (
      (storage.foldername(name))[1] = (select auth.uid())::text
      and exists (
        select 1 from public.graduate_membership_requests m
        where m.auth_user_id = (select auth.uid())
          and m.status = 'approved' and m.ends_at > now()
      )
    )
  )
);
