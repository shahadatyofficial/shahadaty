-- Admin-only certificate registration for Shahadaty.
-- Apply this SQL to the linked Supabase project after reviewing the pull request.

create or replace function public.admin_add_certificate(
  p_institution_id uuid,
  p_student_name text,
  p_course text,
  p_issue_date date,
  p_student_name_en text default null,
  p_specialization text default null,
  p_duration text default null,
  p_grade text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_institution public.institutions%rowtype;
  v_number bigint;
  v_cert_number text;
  v_certificate_id uuid;
  v_year text := to_char(current_date, 'YYYY');
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;

  if p_institution_id is null then
    raise exception 'INSTITUTION_REQUIRED';
  end if;
  if nullif(trim(coalesce(p_student_name, '')), '') is null then
    raise exception 'STUDENT_NAME_REQUIRED';
  end if;
  if nullif(trim(coalesce(p_course, '')), '') is null then
    raise exception 'COURSE_REQUIRED';
  end if;
  if p_issue_date is null then
    raise exception 'ISSUE_DATE_REQUIRED';
  end if;

  select *
    into v_institution
    from public.institutions
   where id = p_institution_id
     and status = 'approved'
   for share;

  if not found then
    raise exception 'INSTITUTION_NOT_ACTIVE_ON_PLATFORM';
  end if;

  -- Atomic global counter prevents duplicate numbers when admins add certificates concurrently.
  insert into public.certificate_sequences(sequence_key, last_number, updated_at)
  values ('global', 1, now())
  on conflict (sequence_key)
  do update set
    last_number = public.certificate_sequences.last_number + 1,
    updated_at = now()
  returning last_number into v_number;

  v_cert_number := 'SH-' || v_year || '-' || case when v_number < 1000000 then lpad(v_number::text, 6, '0') else v_number::text end;

  insert into public.certificates (
    institution_id,
    cert_number,
    student_name,
    student_name_en,
    course,
    specialization,
    issue_date,
    duration,
    grade,
    status,
    added_by
  ) values (
    v_institution.id,
    v_cert_number,
    trim(p_student_name),
    nullif(trim(coalesce(p_student_name_en, '')), ''),
    trim(p_course),
    nullif(trim(coalesce(p_specialization, '')), ''),
    p_issue_date,
    nullif(trim(coalesce(p_duration, '')), ''),
    nullif(trim(coalesce(p_grade, '')), ''),
    'active',
    'admin'
  )
  returning id into v_certificate_id;

  insert into public.activity_log (
    institution_id,
    action,
    cert_number,
    details,
    actor_id,
    actor_type,
    target_type,
    target_id
  ) values (
    v_institution.id,
    'admin_add_certificate',
    v_cert_number,
    'تم تسجيل الشهادة بواسطة إدارة منصة شهادتي نيابةً عن الجهة صاحبة السجل',
    auth.uid(),
    'admin',
    'certificate',
    v_certificate_id
  );

  return jsonb_build_object(
    'success', true,
    'certificate_id', v_certificate_id,
    'cert_number', v_cert_number,
    'institution_id', v_institution.id,
    'institution_name', v_institution.name
  );
end;
$function$;

revoke all on function public.admin_add_certificate(uuid, text, text, date, text, text, text, text) from public;
revoke all on function public.admin_add_certificate(uuid, text, text, date, text, text, text, text) from anon;
grant execute on function public.admin_add_certificate(uuid, text, text, date, text, text, text, text) to authenticated;
