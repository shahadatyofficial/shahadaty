-- شهادتي | Admin hardening
-- Run once in Supabase SQL Editor.
create or replace function public.admin_update_institution_quota(
  p_institution_id uuid,
  p_quota_total integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.institutions%rowtype;
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;
  if p_quota_total is null or p_quota_total < 0 then
    raise exception 'INVALID_QUOTA';
  end if;

  update public.institutions
     set quota_total = p_quota_total,
         updated_at = now()
   where id = p_institution_id
   returning * into v_row;

  if not found then
    raise exception 'INSTITUTION_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'success', true,
    'institution_id', v_row.id,
    'quota_total', v_row.quota_total,
    'quota_used', v_row.quota_used
  );
end;
$$;

create or replace function public.admin_list_certificates(
  p_search text default null
)
returns table(
  id uuid,
  cert_number text,
  student_name text,
  course text,
  specialization text,
  issue_date date,
  duration text,
  grade text,
  status text,
  institution_id uuid,
  institution_name text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;

  return query
  select
    c.id,
    c.cert_number,
    c.student_name,
    c.course,
    c.specialization,
    c.issue_date,
    c.duration,
    c.grade,
    c.status,
    c.institution_id,
    i.name,
    c.created_at
  from public.certificates c
  left join public.institutions i on i.id = c.institution_id
  where coalesce(nullif(trim(p_search), ''), '') = ''
     or c.cert_number ilike '%' || trim(p_search) || '%'
     or c.student_name ilike '%' || trim(p_search) || '%'
     or c.course ilike '%' || trim(p_search) || '%'
  order by c.created_at desc
  limit 100;
end;
$$;

create or replace function public.admin_revoke_certificate(
  p_certificate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cert public.certificates%rowtype;
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;

  update public.certificates
     set status = 'revoked'
   where id = p_certificate_id
     and status = 'active'
   returning * into v_cert;

  if not found then
    raise exception 'CERTIFICATE_NOT_FOUND_OR_ALREADY_REVOKED';
  end if;

  return jsonb_build_object(
    'success', true,
    'certificate_id', v_cert.id,
    'cert_number', v_cert.cert_number,
    'status', v_cert.status
  );
end;
$$;

create or replace function public.admin_platform_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_approved integer;
  v_pending integer;
  v_certs integer;
  v_active_certs integer;
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;

  select count(*)::integer into v_approved
    from public.institutions where status = 'approved';

  select count(*)::integer into v_pending
    from public.institutions where status = 'pending';

  select count(*)::integer into v_certs
    from public.certificates;

  select count(*)::integer into v_active_certs
    from public.certificates where status = 'active';

  return jsonb_build_object(
    'approved_institutions', v_approved,
    'pending_institutions', v_pending,
    'certificates', v_certs,
    'active_certificates', v_active_certs
  );
end;
$$;

grant execute on function public.admin_update_institution_quota(uuid, integer) to authenticated;
grant execute on function public.admin_list_certificates(text) to authenticated;
grant execute on function public.admin_revoke_certificate(uuid) to authenticated;
grant execute on function public.admin_platform_stats() to authenticated;


create or replace function public.admin_list_institution_documents(
  p_institution_id uuid
)
returns table(
  id uuid,
  institution_id uuid,
  document_type text,
  file_name text,
  file_path text,
  status text,
  rejection_reason text,
  uploaded_at timestamptz,
  reviewed_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;

  return query
  select d.id,d.institution_id,d.document_type,d.file_name,d.file_path,
         d.status,d.rejection_reason,d.uploaded_at,d.reviewed_at
  from public.institution_documents d
  where d.institution_id = p_institution_id
  order by d.uploaded_at desc;
end;
$$;

create or replace function public.review_document(
  p_document_id uuid,
  p_status text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc public.institution_documents%rowtype;
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;

  if p_status not in ('pending','approved','rejected') then
    raise exception 'INVALID_DOCUMENT_STATUS';
  end if;

  if p_status = 'rejected' and coalesce(trim(p_reason),'') = '' then
    raise exception 'REJECTION_REASON_REQUIRED';
  end if;

  update public.institution_documents
     set status = p_status,
         rejection_reason = case when p_status='rejected' then trim(p_reason) else null end,
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         updated_at = now()
   where id = p_document_id
   returning * into v_doc;

  if not found then
    raise exception 'DOCUMENT_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'success', true,
    'document_id', v_doc.id,
    'status', v_doc.status
  );
end;
$$;

grant execute on function public.admin_list_institution_documents(uuid) to authenticated;
grant execute on function public.review_document(uuid,text,text) to authenticated;

-- ============================================================
-- STORAGE SECURITY FIX
-- ============================================================
DROP POLICY IF EXISTS institution_docs_storage_read ON storage.objects;
CREATE POLICY institution_docs_storage_read ON storage.objects
FOR SELECT USING (
  bucket_id = 'institution-documents'
  AND (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.institution_users iu
      WHERE iu.institution_id::text = (storage.foldername(name))[1]
        AND iu.auth_user_id = auth.uid()
        AND iu.status = 'active'
    )
  )
);

DROP POLICY IF EXISTS institution_docs_storage_insert ON storage.objects;
CREATE POLICY institution_docs_storage_insert ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'institution-documents'
  AND EXISTS (
    SELECT 1 FROM public.institution_users iu
    WHERE iu.institution_id::text = (storage.foldername(name))[1]
      AND iu.auth_user_id = auth.uid()
      AND iu.status = 'active'
      AND iu.role IN ('owner','manager','staff')
  )
);

DROP POLICY IF EXISTS institution_docs_storage_update ON storage.objects;
CREATE POLICY institution_docs_storage_update ON storage.objects
FOR UPDATE USING (
  bucket_id = 'institution-documents'
  AND (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.institution_users iu
      WHERE iu.institution_id::text = (storage.foldername(name))[1]
        AND iu.auth_user_id = auth.uid()
        AND iu.status = 'active'
        AND iu.role IN ('owner','manager','staff')
    )
  )
) WITH CHECK (bucket_id = 'institution-documents');

DROP POLICY IF EXISTS institution_docs_storage_delete ON storage.objects;
CREATE POLICY institution_docs_storage_delete ON storage.objects
FOR DELETE USING (
  bucket_id = 'institution-documents'
  AND (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.institution_users iu
      WHERE iu.institution_id::text = (storage.foldername(name))[1]
        AND iu.auth_user_id = auth.uid()
        AND iu.status = 'active'
        AND iu.role IN ('owner','manager','staff')
    )
  )
);

-- ============================================================
-- ADMIN COMPANY / RECRUITMENT WORKFLOW
-- ============================================================
create or replace function public.admin_list_recruitment_requests(p_status text default null)
returns setof public.recruitment_requests
language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  return query
    select r.* from public.recruitment_requests r
    where coalesce(nullif(trim(p_status),''),'')=''
       or r.status=trim(p_status)
    order by r.created_at desc
    limit 500;
end;
$$;

create or replace function public.admin_update_recruitment_status(p_request_id uuid,p_status text)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare v_row public.recruitment_requests%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_status not in ('new','processing','fulfilled','closed') then raise exception 'INVALID_STATUS'; end if;
  update public.recruitment_requests set status=p_status
  where id=p_request_id returning * into v_row;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'id',v_row.id,'status',v_row.status);
end;
$$;

create or replace function public.admin_list_companies()
returns setof public.companies
language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  return query select c.* from public.companies c order by c.created_at desc limit 500;
end;
$$;

create or replace function public.admin_update_company(
  p_company_id uuid,
  p_status text default null,
  p_search_credits integer default null
)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare v_row public.companies%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_status is not null and p_status not in ('pending','approved','suspended') then raise exception 'INVALID_STATUS'; end if;
  if p_search_credits is not null and p_search_credits < 0 then raise exception 'INVALID_CREDITS'; end if;
  update public.companies
     set status=coalesce(p_status,status),
         search_credits=coalesce(p_search_credits,search_credits)
   where id=p_company_id returning * into v_row;
  if not found then raise exception 'COMPANY_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'id',v_row.id,'status',v_row.status,'search_credits',v_row.search_credits);
end;
$$;

grant execute on function public.admin_list_recruitment_requests(text) to authenticated;
grant execute on function public.admin_update_recruitment_status(uuid,text) to authenticated;
grant execute on function public.admin_list_companies() to authenticated;
grant execute on function public.admin_update_company(uuid,text,integer) to authenticated;
