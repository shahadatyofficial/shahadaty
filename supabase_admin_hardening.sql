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
