-- Applied to the connected Supabase project on 2026-10-14.
-- Security alignment for direct RPC access and overly permissive table policies.
-- Safe to re-run; intentionally does not delete business data.

begin;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;

grant execute on function public.verify_certificate(text) to anon, authenticated;
grant execute on function public.public_platform_stats() to anon, authenticated;

revoke execute on function public.get_next_certificate_number() from public, anon, authenticated;
revoke execute on function public.generate_certificate_number() from public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

drop policy if exists companies_all on public.companies;
drop policy if exists companies_public_insert on public.companies;
create policy companies_public_insert on public.companies
for insert to anon, authenticated
with check (
  coalesce(trim(company_name),'') <> ''
  and status = 'pending'
  and coalesce(search_credits,0) = 0
);

drop policy if exists recruitment_all on public.recruitment_requests;
drop policy if exists recruitment_requests_public_insert on public.recruitment_requests;
create policy recruitment_requests_public_insert on public.recruitment_requests
for insert to anon, authenticated
with check (
  coalesce(trim(company_name),'') <> ''
  and coalesce(trim(contact_name),'') <> ''
  and coalesce(trim(contact_email),'') <> ''
  and coalesce(trim(qualification),'') <> ''
  and coalesce(positions_needed,0) >= 1
  and status = 'new'
);

drop policy if exists institutions_insert_own on public.institutions;
drop policy if exists institutions_insert_self on public.institutions;
drop policy if exists institutions_own on public.institutions;
drop policy if exists institutions_update_own on public.institutions;
drop policy if exists institutions_update_manager on public.institutions;

drop policy if exists institution_documents_insert_own on public.institution_documents;
drop policy if exists institution_documents_insert_staff on public.institution_documents;
drop policy if exists institution_documents_update_manager on public.institution_documents;
drop policy if exists institution_documents_update_own on public.institution_documents;
create policy institution_documents_insert_staff on public.institution_documents
for insert to authenticated
with check (
  public.has_institution_role(institution_id, array['owner','manager','staff'])
  and status='pending' and reviewed_by is null
);

drop policy if exists institution_users_insert_manager on public.institution_users;
drop policy if exists institution_users_update_manager on public.institution_users;

drop policy if exists certificates_update_manager on public.certificates;
drop policy if exists certificates_update on public.certificates;
drop policy if exists certificates_insert on public.certificates;
drop policy if exists certificates_own on public.certificates;

commit;
notify pgrst, 'reload schema';


-- Eliminate older storage rules that allowed broad object updates.
drop policy if exists institution_docs_storage_read on storage.objects;
drop policy if exists institution_docs_storage_insert on storage.objects;
drop policy if exists institution_docs_storage_update on storage.objects;
drop policy if exists institution_docs_storage_delete on storage.objects;
drop policy if exists institution_documents_storage_select on storage.objects;
drop policy if exists institution_documents_storage_insert on storage.objects;
drop policy if exists institution_documents_storage_update on storage.objects;
drop policy if exists institution_documents_storage_delete on storage.objects;

insert into storage.buckets(id,name,public)
values('institution-documents','institution-documents',false)
on conflict(id) do update set public=false;

create policy institution_docs_storage_read on storage.objects
for select to authenticated
using (
  bucket_id='institution-documents'
  and (
    public.is_platform_admin()
    or exists (
      select 1 from public.institution_users iu
      where iu.institution_id::text=(storage.foldername(name))[1]
        and iu.auth_user_id=auth.uid() and iu.status='active'
    )
  )
);
create policy institution_docs_storage_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='institution-documents'
  and exists (
    select 1 from public.institution_users iu
    where iu.institution_id::text=(storage.foldername(name))[1]
      and iu.auth_user_id=auth.uid() and iu.status='active'
      and iu.role in ('owner','manager','staff')
  )
);
create policy institution_docs_storage_update on storage.objects
for update to authenticated
using (bucket_id='institution-documents' and public.is_platform_admin())
with check (bucket_id='institution-documents' and public.is_platform_admin());
create policy institution_docs_storage_delete on storage.objects
for delete to authenticated
using (
  bucket_id='institution-documents'
  and (
    public.is_platform_admin()
    or exists (
      select 1 from public.institution_users iu
      where iu.institution_id::text=(storage.foldername(name))[1]
        and iu.auth_user_id=auth.uid() and iu.status='active'
        and iu.role in ('owner','manager','staff')
        and not exists (
          select 1 from public.institution_documents d
          where d.file_path=storage.objects.name
        )
    )
  )
);

drop policy if exists accreditation_all on public.accreditation_requests;
revoke all on table public.accreditation_requests from anon, authenticated;
drop policy if exists activity_own on public.activity_log;
revoke all on table public.activity_log from anon, authenticated;
