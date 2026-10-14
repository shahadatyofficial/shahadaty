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
