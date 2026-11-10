-- Admin registration of training certificates and university qualifications.
-- Names and RPC signatures align with the production schema and admin.html.

alter table public.certificates
  add column if not exists record_type text not null default 'training',
  add column if not exists source_type text not null default 'institution',
  add column if not exists academic_university text,
  add column if not exists academic_faculty text,
  add column if not exists academic_degree text,
  add column if not exists graduation_year integer,
  add column if not exists declaration_accepted boolean not null default false,
  add column if not exists declaration_accepted_at timestamptz;

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

create index if not exists certificates_academic_lookup_idx
  on public.certificates (record_type, academic_university, academic_faculty, graduation_year);

create or replace function public.admin_add_certificate_v2(
  p_source text,
  p_institution_id uuid,
  p_record_type text,
  p_student_name text,
  p_student_name_en text default null,
  p_course text default null,
  p_specialization text default null,
  p_issue_date date default null,
  p_duration text default null,
  p_grade text default null,
  p_university text default null,
  p_faculty text default null,
  p_academic_degree text default null,
  p_graduation_year integer default null,
  p_declaration_accepted boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_number bigint;
  v_cert_number text;
  v_institution_name text;
  v_cert_id uuid;
  v_issue_date date;
begin
  if auth.uid() is null or not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_source not in ('admin','institution') then raise exception 'INVALID_SOURCE'; end if;
  if p_record_type not in ('training','academic') then raise exception 'INVALID_RECORD_TYPE'; end if;
  if nullif(trim(p_student_name),'') is null then raise exception 'STUDENT_NAME_REQUIRED'; end if;
  if coalesce(p_declaration_accepted,false) is not true then raise exception 'DECLARATION_REQUIRED'; end if;

  if p_source='institution' then
    if p_institution_id is null then raise exception 'INSTITUTION_REQUIRED'; end if;
    select name into v_institution_name from public.institutions
      where id=p_institution_id and status='approved';
    if not found then raise exception 'INSTITUTION_NOT_APPROVED'; end if;
  elsif p_institution_id is not null then
    raise exception 'ADMIN_SOURCE_MUST_NOT_HAVE_INSTITUTION';
  end if;

  if p_record_type='academic' then
    if nullif(trim(p_university),'') is null or nullif(trim(p_faculty),'') is null
       or nullif(trim(p_academic_degree),'') is null then raise exception 'ACADEMIC_FIELDS_REQUIRED'; end if;
    if p_graduation_year is null or p_graduation_year not between 1950 and extract(year from current_date)::integer+1 then
      raise exception 'INVALID_GRADUATION_YEAR';
    end if;
    v_issue_date := make_date(p_graduation_year,6,30);
  else
    if nullif(trim(p_course),'') is null or p_issue_date is null then raise exception 'COURSE_AND_ISSUE_DATE_REQUIRED'; end if;
    v_issue_date := p_issue_date;
  end if;

  insert into public.certificate_sequences(sequence_key,last_number)
  values('global',1)
  on conflict(sequence_key) do update set last_number=public.certificate_sequences.last_number+1,updated_at=now()
  returning last_number into v_number;

  v_cert_number := 'SH-'||extract(year from current_date)::integer||'-'||lpad(v_number::text,6,'0');
  insert into public.certificates(
    institution_id,cert_number,student_name,student_name_en,course,specialization,issue_date,
    duration,grade,status,added_by,record_type,source_type,academic_university,academic_faculty,
    academic_degree,graduation_year,declaration_accepted,declaration_accepted_at
  ) values (
    p_institution_id,v_cert_number,trim(p_student_name),nullif(trim(p_student_name_en),''),
    case when p_record_type='academic' then 'مؤهل علمي' else trim(p_course) end,
    case when p_record_type='academic' then trim(p_faculty) else nullif(trim(p_specialization),'') end,
    v_issue_date,nullif(trim(p_duration),''),nullif(trim(p_grade),''),'active',
    'admin',p_record_type,p_source,nullif(trim(p_university),''),nullif(trim(p_faculty),''),
    nullif(trim(p_academic_degree),''),p_graduation_year,true,now()
  ) returning id into v_cert_id;

  insert into public.activity_log(action,cert_number,details,actor_id,actor_type,target_type,target_id)
  values('admin_add_certificate',v_cert_number,
    case when p_record_type='academic' then 'تسجيل مؤهل علمي: '||trim(p_academic_degree)||' - '||trim(p_university)
         else 'تسجيل شهادة تدريبية' end,
    auth.uid(),'admin','certificate',v_cert_id);

  return jsonb_build_object('success',true,'certificate_id',v_cert_id,'cert_number',v_cert_number,
    'institution_id',p_institution_id,'institution_name',coalesce(v_institution_name,'إدارة منصة شهادتي'),
    'record_type',p_record_type,'source_type',p_source);
end;
$function$;
revoke all on function public.admin_add_certificate_v2(text,uuid,text,text,text,text,text,date,text,text,text,text,text,integer,boolean) from public, anon;
grant execute on function public.admin_add_certificate_v2(text,uuid,text,text,text,text,text,date,text,text,text,text,text,integer,boolean) to authenticated;

drop function if exists public.verify_certificate(text);
create function public.verify_certificate(p_cert_number text)
returns table(
  cert_number text, student_name text, course text, specialization text,
  issue_date date, grade text, duration text, status text,
  institution_name text, institution_type text,
  record_type text, source_type text, academic_university text,
  academic_faculty text, academic_degree text, graduation_year integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_cert public.certificates%rowtype;
  v_inst public.institutions%rowtype;
begin
  select c.* into v_cert from public.certificates c
  where upper(trim(c.cert_number))=upper(trim(p_cert_number)) limit 1;
  if not found then raise exception 'CERTIFICATE_NOT_FOUND'; end if;

  if v_cert.institution_id is not null then
    select * into v_inst from public.institutions where id=v_cert.institution_id;
    if not found or v_inst.status<>'approved' then raise exception 'CERTIFICATE_NOT_FOUND'; end if;
  elsif coalesce(v_cert.source_type,'institution')<>'admin' then
    raise exception 'CERTIFICATE_NOT_FOUND';
  end if;

  if to_regclass('public.certificate_verifications') is not null then
    insert into public.certificate_verifications(cert_number,certificate_id,result,checked_at)
    values(v_cert.cert_number,v_cert.id,case when v_cert.status='active' then 'valid' else 'invalid' end,now());
  end if;

  return query select v_cert.cert_number,v_cert.student_name,v_cert.course,v_cert.specialization,
    v_cert.issue_date,v_cert.grade,v_cert.duration,v_cert.status,
    coalesce(v_inst.name,'إدارة منصة شهادتي'),coalesce(v_inst.institution_type,'إدارة المنصة'),
    coalesce(v_cert.record_type,'training'),coalesce(v_cert.source_type,'institution'),
    v_cert.academic_university,v_cert.academic_faculty,v_cert.academic_degree,v_cert.graduation_year;
end;
$function$;
grant execute on function public.verify_certificate(text) to anon, authenticated;

notify pgrst, 'reload schema';
