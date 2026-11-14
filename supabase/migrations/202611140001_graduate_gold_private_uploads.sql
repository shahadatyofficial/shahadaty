alter table public.graduate_profiles
  add column if not exists premium_cv_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'graduate-gold-private',
  'graduate-gold-private',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists graduate_gold_files_select_own_or_admin on storage.objects;
create policy graduate_gold_files_select_own_or_admin
on storage.objects for select to authenticated
using (
  bucket_id = 'graduate-gold-private'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_platform_admin()
  )
);

drop policy if exists graduate_gold_files_insert_own on storage.objects;
create policy graduate_gold_files_insert_own
on storage.objects for insert to authenticated
with check (
  bucket_id = 'graduate-gold-private'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists graduate_gold_files_update_own on storage.objects;
create policy graduate_gold_files_update_own
on storage.objects for update to authenticated
using (
  bucket_id = 'graduate-gold-private'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_platform_admin()
  )
)
with check (
  bucket_id = 'graduate-gold-private'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_platform_admin()
  )
);

drop policy if exists graduate_gold_files_delete_own_or_admin on storage.objects;
create policy graduate_gold_files_delete_own_or_admin
on storage.objects for delete to authenticated
using (
  bucket_id = 'graduate-gold-private'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_platform_admin()
  )
);
