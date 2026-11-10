-- Align the admin qualification form RPC and provide searchable reference lists.
create table if not exists public.academic_universities (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.academic_faculties (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.academic_universities enable row level security;
alter table public.academic_faculties enable row level security;
drop policy if exists academic_universities_admin_read on public.academic_universities;
create policy academic_universities_admin_read on public.academic_universities
  for select to authenticated using (public.is_platform_admin());
drop policy if exists academic_faculties_admin_read on public.academic_faculties;
create policy academic_faculties_admin_read on public.academic_faculties
  for select to authenticated using (public.is_platform_admin());
grant select on public.academic_universities, public.academic_faculties to authenticated;

insert into public.academic_universities(name) values
 ('جامعة القاهرة'),('جامعة عين شمس'),('جامعة الإسكندرية'),('جامعة المنصورة'),
 ('جامعة أسيوط'),('جامعة طنطا'),('جامعة الزقازيق'),('جامعة المنوفية'),
 ('جامعة بنها'),('جامعة حلوان'),('جامعة قناة السويس'),('جامعة كفر الشيخ'),
 ('جامعة الفيوم'),('جامعة بني سويف'),('جامعة سوهاج'),('جامعة جنوب الوادي'),
 ('جامعة المنيا'),('جامعة بورسعيد'),('جامعة دمياط'),('جامعة العريش'),
 ('جامعة مطروح'),('جامعة الوادي الجديد'),('جامعة الأقصر'),('جامعة أسوان'),
 ('جامعة الأزهر'),('الجامعة الأمريكية بالقاهرة'),('الجامعة الألمانية بالقاهرة'),
 ('جامعة مصر للعلوم والتكنولوجيا'),('جامعة 6 أكتوبر'),('جامعة المستقبل')
on conflict (name) do nothing;

insert into public.academic_faculties(name) values
 ('كلية الطب'),('كلية طب الأسنان'),('كلية الصيدلة'),('كلية العلاج الطبيعي'),
 ('كلية التمريض'),('كلية الهندسة'),('كلية الحاسبات والمعلومات'),('كلية العلوم'),
 ('كلية التجارة'),('كلية الحقوق'),('كلية الآداب'),('كلية التربية'),
 ('كلية الزراعة'),('كلية الطب البيطري'),('كلية الإعلام'),('كلية الألسن'),
 ('كلية التربية النوعية'),('كلية الخدمة الاجتماعية'),('كلية دار العلوم'),
 ('كلية الاقتصاد والعلوم السياسية'),('كلية الفنون الجميلة'),('كلية التربية الرياضية')
on conflict (name) do nothing;

create or replace function public.admin_add_certificate_v2(
  p_source text,
  p_institution_id uuid,
  p_record_type text,
  p_student_name text,
  p_student_name_en text,
  p_course text,
  p_specialization text,
  p_issue_date date,
  p_duration text,
  p_grade text,
  p_university text,
  p_faculty text,
  p_academic_degree text,
  p_graduation_year integer,
  p_declaration_accepted boolean
) returns jsonb
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
  if auth.uid() is null or not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_source not in ('admin','institution') then raise exception 'INVALID_SOURCE'; end if;
  if p_record_type not in ('training','academic') then raise exception 'INVALID_RECORD_TYPE'; end if;
  if nullif(trim(coalesce(p_student_name,'')),'') is null then raise exception 'STUDENT_NAME_REQUIRED'; end if;
  if p_declaration_accepted is distinct from true then raise exception 'DATA_DECLARATION_REQUIRED'; end if;

  if p_source='institution' then
    if p_institution_id is null then raise exception 'INSTITUTION_REQUIRED'; end if;
    select * into v_institution from public.institutions
      where id=p_institution_id and status='approved' for share;
    if not found then raise exception 'INSTITUTION_NOT_ACTIVE_ON_PLATFORM'; end if;
  elsif p_institution_id is not null then
    raise exception 'ADMIN_SOURCE_MUST_NOT_HAVE_INSTITUTION';
  end if;

  if p_record_type='academic' then
    if nullif(trim(coalesce(p_university,'')),'') is null
      or nullif(trim(coalesce(p_faculty,'')),'') is null
      or nullif(trim(coalesce(p_academic_degree,'')),'') is null
      or p_graduation_year is null or p_graduation_year < 1950 or p_graduation_year > 2100 then
      raise exception 'ACADEMIC_FIELDS_REQUIRED';
    end if;
  elsif nullif(trim(coalesce(p_course,'')),'') is null or p_issue_date is null then
    raise exception 'TRAINING_FIELDS_REQUIRED';
  end if;

  insert into public.certificate_sequences(sequence_key,last_number,updated_at)
  values ('global',1,now())
  on conflict (sequence_key) do update
    set last_number=public.certificate_sequences.last_number+1,updated_at=now()
  returning last_number into v_number;
  v_cert_number := 'SH-' || v_year || '-' ||
    case when v_number < 1000000 then lpad(v_number::text,6,'0') else v_number::text end;

  insert into public.certificates(
    institution_id,cert_number,student_name,student_name_en,course,specialization,
    issue_date,duration,grade,status,added_by,record_type,record_source,
    university,college,academic_degree,graduation_year,data_declaration
  ) values (
    p_institution_id,v_cert_number,trim(p_student_name),
    nullif(trim(coalesce(p_student_name_en,'')),''),
    case when p_record_type='academic' then 'مؤهل علمي' else trim(p_course) end,
    case when p_record_type='academic' then null else nullif(trim(coalesce(p_specialization,'')),'') end,
    case when p_record_type='academic' then make_date(p_graduation_year,6,30) else p_issue_date end,
    case when p_record_type='academic' then null else nullif(trim(coalesce(p_duration,'')),'') end,
    nullif(trim(coalesce(p_grade,'')),''),
    'active','admin',p_record_type,p_source,
    case when p_record_type='academic' then trim(p_university) else null end,
    case when p_record_type='academic' then trim(p_faculty) else null end,
    case when p_record_type='academic' then trim(p_academic_degree) else null end,
    case when p_record_type='academic' then p_graduation_year else null end,
    true
  ) returning id into v_certificate_id;

  insert into public.activity_log(
    institution_id,action,cert_number,details,actor_id,actor_type,target_type,target_id
  ) values (
    p_institution_id,'admin_add_certificate',v_cert_number,
    case when p_record_type='academic'
      then 'تسجيل مؤهل علمي بواسطة '||p_source||'؛ أقر صاحب البيانات بمسؤوليته'
      else 'تسجيل شهادة تدريبية بواسطة '||p_source||'؛ أقر صاحب البيانات بمسؤوليته' end,
    auth.uid(),'admin','certificate',v_certificate_id
  );

  return jsonb_build_object(
    'success',true,'certificate_id',v_certificate_id,'cert_number',v_cert_number,
    'institution_id',p_institution_id,
    'institution_name',case when p_institution_id is null then 'إدارة منصة شهادتي' else v_institution.name end,
    'record_type',p_record_type,'record_source',p_source
  );
end;
$function$;
revoke all on function public.admin_add_certificate_v2(text,uuid,text,text,text,text,text,date,text,text,text,text,text,integer,boolean) from public, anon;
grant execute on function public.admin_add_certificate_v2(text,uuid,text,text,text,text,text,date,text,text,text,text,text,integer,boolean) to authenticated;

notify pgrst, 'reload schema';
