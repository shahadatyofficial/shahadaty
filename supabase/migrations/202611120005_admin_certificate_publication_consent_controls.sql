create or replace function public.admin_list_certificates_with_consent(p_search text default null)
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
  created_at timestamptz,
  declaration_accepted boolean
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
  select c.id, c.cert_number, c.student_name, c.course, c.specialization,
         c.issue_date, c.duration, c.grade, c.status, c.institution_id,
         i.name, c.created_at, coalesce(c.declaration_accepted, false)
  from public.certificates c
  left join public.institutions i on i.id = c.institution_id
  where coalesce(nullif(trim(p_search), ''), '') = ''
     or c.cert_number ilike '%' || trim(p_search) || '%'
     or c.student_name ilike '%' || trim(p_search) || '%'
     or c.course ilike '%' || trim(p_search) || '%'
     or c.specialization ilike '%' || trim(p_search) || '%'
     or c.academic_university ilike '%' || trim(p_search) || '%'
     or c.academic_faculty ilike '%' || trim(p_search) || '%'
     or c.academic_degree ilike '%' || trim(p_search) || '%'
  order by c.created_at desc
  limit 300;
end;
$$;

create or replace function public.admin_update_certificate_publication_consent(
  p_certificate_id uuid,
  p_consent boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;

  update public.certificates
  set declaration_accepted = coalesce(p_consent, false),
      declaration_accepted_at = case
        when coalesce(p_consent, false) then coalesce(declaration_accepted_at, now())
        else null
      end
  where id = p_certificate_id;

  if not found then
    raise exception 'CERTIFICATE_NOT_FOUND';
  end if;

  return true;
end;
$$;

revoke all on function public.admin_list_certificates_with_consent(text) from public, anon;
revoke all on function public.admin_update_certificate_publication_consent(uuid, boolean) from public, anon;
grant execute on function public.admin_list_certificates_with_consent(text) to authenticated;
grant execute on function public.admin_update_certificate_publication_consent(uuid, boolean) to authenticated;
