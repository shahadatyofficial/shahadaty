-- Admin certificate directory, safe detail editing and audit trail.
create or replace function public.admin_search_certificates_v2(
  p_search text default null,
  p_status text default null,
  p_record_type text default null
)
returns table(
  id uuid, cert_number text, student_name text, student_name_en text,
  course text, specialization text, acquisition_date date, issue_date date,
  duration text, grade text, status text, institution_id uuid,
  institution_name text, created_at timestamptz, record_type text,
  source_type text, student_email text, student_phone text,
  student_national_id text, governorate text, academic_university text,
  academic_faculty text, academic_degree text, graduation_year integer,
  declaration_accepted boolean, visible_to_companies boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare v_search text := nullif(trim(coalesce(p_search,'')),'');
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;
  return query
  select c.id,c.cert_number,c.student_name,c.student_name_en,c.course,c.specialization,
         coalesce(c.acquisition_date,c.issue_date),c.issue_date,c.duration,c.grade,c.status,
         c.institution_id,i.name,c.created_at,c.record_type,c.source_type,c.student_email,
         c.student_phone,c.student_national_id,c.governorate,c.academic_university,
         c.academic_faculty,c.academic_degree,c.graduation_year,
         c.declaration_accepted,c.visible_to_companies
  from public.certificates c
  left join public.institutions i on i.id=c.institution_id
  where (p_status is null or p_status='' or c.status=p_status)
    and (p_record_type is null or p_record_type='' or c.record_type=p_record_type)
    and (
      v_search is null
      or c.cert_number ilike '%'||v_search||'%'
      or c.student_name ilike '%'||v_search||'%'
      or coalesce(c.student_name_en,'') ilike '%'||v_search||'%'
      or c.course ilike '%'||v_search||'%'
      or coalesce(c.specialization,'') ilike '%'||v_search||'%'
      or coalesce(c.student_email,'') ilike '%'||v_search||'%'
      or coalesce(c.student_phone,'') ilike '%'||v_search||'%'
      or coalesce(c.student_national_id,'') ilike '%'||v_search||'%'
      or coalesce(c.governorate,'') ilike '%'||v_search||'%'
      or coalesce(c.academic_university,'') ilike '%'||v_search||'%'
      or coalesce(c.academic_faculty,'') ilike '%'||v_search||'%'
      or coalesce(c.academic_degree,'') ilike '%'||v_search||'%'
      or coalesce(i.name,'') ilike '%'||v_search||'%'
    )
  order by c.created_at desc nulls last
  limit 300;
end;
$function$;

create or replace function public.admin_update_certificate_details(
  p_certificate_id uuid,
  p_student_name text,
  p_student_name_en text,
  p_course text,
  p_specialization text,
  p_acquisition_date date,
  p_duration text,
  p_grade text,
  p_student_email text,
  p_student_phone text,
  p_student_national_id text,
  p_governorate text,
  p_academic_university text,
  p_academic_faculty text,
  p_academic_degree text,
  p_graduation_year integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_before public.certificates%rowtype;
  v_after public.certificates%rowtype;
  v_changes jsonb;
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;
  if p_certificate_id is null then raise exception 'CERTIFICATE_ID_REQUIRED'; end if;
  if nullif(trim(coalesce(p_student_name,'')),'') is null then raise exception 'STUDENT_NAME_REQUIRED'; end if;
  if nullif(trim(coalesce(p_course,'')),'') is null then raise exception 'COURSE_REQUIRED'; end if;
  if p_acquisition_date is null then raise exception 'ACQUISITION_DATE_REQUIRED'; end if;
  if p_graduation_year is not null and p_graduation_year not between 1950 and extract(year from current_date)::integer + 1 then
    raise exception 'INVALID_GRADUATION_YEAR';
  end if;

  select * into v_before from public.certificates where id=p_certificate_id for update;
  if not found then raise exception 'CERTIFICATE_NOT_FOUND'; end if;

  update public.certificates set
    student_name=trim(p_student_name),
    student_name_en=nullif(trim(coalesce(p_student_name_en,'')),''),
    course=trim(p_course),
    specialization=nullif(trim(coalesce(p_specialization,'')),''),
    acquisition_date=p_acquisition_date,
    duration=nullif(trim(coalesce(p_duration,'')),''),
    grade=nullif(trim(coalesce(p_grade,'')),''),
    student_email=nullif(trim(coalesce(p_student_email,'')),''),
    student_phone=nullif(trim(coalesce(p_student_phone,'')),''),
    student_national_id=nullif(trim(coalesce(p_student_national_id,'')),''),
    governorate=nullif(trim(coalesce(p_governorate,'')),''),
    academic_university=nullif(trim(coalesce(p_academic_university,'')),''),
    academic_faculty=nullif(trim(coalesce(p_academic_faculty,'')),''),
    academic_degree=nullif(trim(coalesce(p_academic_degree,'')),''),
    graduation_year=p_graduation_year
  where id=p_certificate_id
  returning * into v_after;

  v_changes := jsonb_build_object(
    'before', jsonb_build_object('student_name',v_before.student_name,'student_name_en',v_before.student_name_en,'course',v_before.course,'specialization',v_before.specialization,'acquisition_date',v_before.acquisition_date,'duration',v_before.duration,'grade',v_before.grade,'student_email',v_before.student_email,'student_phone',v_before.student_phone,'student_national_id',v_before.student_national_id,'governorate',v_before.governorate,'academic_university',v_before.academic_university,'academic_faculty',v_before.academic_faculty,'academic_degree',v_before.academic_degree,'graduation_year',v_before.graduation_year),
    'after', jsonb_build_object('student_name',v_after.student_name,'student_name_en',v_after.student_name_en,'course',v_after.course,'specialization',v_after.specialization,'acquisition_date',v_after.acquisition_date,'duration',v_after.duration,'grade',v_after.grade,'student_email',v_after.student_email,'student_phone',v_after.student_phone,'student_national_id',v_after.student_national_id,'governorate',v_after.governorate,'academic_university',v_after.academic_university,'academic_faculty',v_after.academic_faculty,'academic_degree',v_after.academic_degree,'graduation_year',v_after.graduation_year)
  );
  insert into public.activity_log(institution_id,action,cert_number,details,actor_id,actor_type,target_type,target_id)
  values(v_after.institution_id,'admin_update_certificate_details',v_after.cert_number,
    'تعديل بيانات الشهادة بواسطة الإدارة: '||v_changes::text,auth.uid(),'admin','certificate',v_after.id);

  return jsonb_build_object('success',true,'certificate_id',v_after.id,'cert_number',v_after.cert_number);
end;
$function$;

revoke all on function public.admin_search_certificates_v2(text,text,text) from public, anon;
grant execute on function public.admin_search_certificates_v2(text,text,text) to authenticated;
revoke all on function public.admin_update_certificate_details(uuid,text,text,text,text,date,text,text,text,text,text,text,text,text,text,integer) from public, anon;
grant execute on function public.admin_update_certificate_details(uuid,text,text,text,text,date,text,text,text,text,text,text,text,text,text,integer) to authenticated;
