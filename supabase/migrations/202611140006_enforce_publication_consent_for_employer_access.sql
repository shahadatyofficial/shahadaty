create or replace function public.company_can_access_alumni_document(p_storage_path text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select exists (
    select 1
    from public.alumni_documents d
    join public.alumni_profiles p on p.id = d.alumni_id
    join public.alumni_access_requests r on r.alumni_id = d.alumni_id
    where d.storage_path = p_storage_path
      and p.visibility_status = 'public'
      and p.publication_consent is true
      and r.company_id = public.current_approved_company_id()
      and r.status = 'approved'
      and r.alumni_consent_at is not null
      and (r.expires_at is null or r.expires_at > now())
      and (
        (d.document_type = 'cv' and r.request_cv = true)
        or (d.document_type <> 'cv' and r.request_documents = true)
      )
  );
$function$;

create or replace function public.company_get_approved_alumni_contact(p_alumni_id uuid)
returns table(full_name text, phone text, email text, governorate text, professional_summary text)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select p.full_name, p.phone, p.email, p.governorate, p.professional_summary
  from public.alumni_profiles p
  where p.id = p_alumni_id
    and p.visibility_status = 'public'
    and p.publication_consent is true
    and exists (
      select 1 from public.alumni_access_requests r
      where r.alumni_id = p.id
        and r.company_id = public.current_approved_company_id()
        and r.status = 'approved'
        and r.alumni_consent_at is not null
        and (r.expires_at is null or r.expires_at > now())
        and r.request_contact = true
    );
$function$;