alter table public.certificates add column if not exists acquisition_date date;
update public.certificates set acquisition_date=issue_date where acquisition_date is null;
create or replace function public.issue_certificate(p_payload jsonb)
returns table(cert_id uuid,cert_number text) language plpgsql security definer set search_path=public
as $$
declare v_uid uuid:=auth.uid(); v_inst uuid:=(p_payload->>'institution_id')::uuid; v_inst_row public.institutions%rowtype;
 v_sub public.subscriptions%rowtype; v_id uuid; v_number text;
 v_acquisition_date date:=coalesce(nullif(p_payload->>'acquisition_date','')::date,nullif(p_payload->>'issue_date','')::date);
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select i.* into v_inst_row from public.institutions i join public.institution_users iu on iu.institution_id=i.id
 where i.id=v_inst and iu.auth_user_id=v_uid and iu.status='active' and iu.role in ('owner','manager','staff') for update of i;
 if not found then raise exception 'NOT_ALLOWED'; end if;
 if v_inst_row.status<>'approved' then raise exception 'INSTITUTION_NOT_APPROVED'; end if;
 select * into v_sub from public.subscriptions s where s.institution_id=v_inst and s.status='active'
 and (s.starts_at is null or s.starts_at<=now()) and (s.ends_at is null or s.ends_at>now())
 and (coalesce(s.amount,0)=0 or s.payment_status='paid') order by s.created_at desc limit 1 for update;
 if not found then raise exception 'SUBSCRIPTION_INACTIVE_OR_UNPAID'; end if;
 if v_sub.quota_used>=v_sub.quota_limit or v_inst_row.quota_used>=v_inst_row.quota_total then raise exception 'QUOTA_EXCEEDED'; end if;
 if coalesce(trim(p_payload->>'student_name'),'')='' or coalesce(trim(p_payload->>'course'),'')='' or v_acquisition_date is null then raise exception 'REQUIRED_FIELDS'; end if;
 if nullif(trim(p_payload->>'student_email'),'') is not null and position('@' in trim(p_payload->>'student_email'))=0 then raise exception 'INVALID_STUDENT_EMAIL'; end if;
 v_number:=public.generate_certificate_number();
 insert into public.certificates(institution_id,cert_number,student_name,student_name_en,student_national_id,student_phone,student_email,
 course,specialization,issue_date,acquisition_date,expiry_date,grade,grade_value,duration,governorate,pdf_url,qr_code,
 visible_to_companies,consent_given_at,status,added_by)
 values(v_inst,v_number,trim(p_payload->>'student_name'),nullif(trim(p_payload->>'student_name_en'),''),
 nullif(trim(p_payload->>'student_national_id'),''),nullif(trim(p_payload->>'student_phone'),''),nullif(lower(trim(p_payload->>'student_email')),''),
 trim(p_payload->>'course'),nullif(trim(p_payload->>'specialization'),''),current_date,v_acquisition_date,
 nullif(p_payload->>'expiry_date','')::date,nullif(trim(p_payload->>'grade'),''),nullif(p_payload->>'grade_value','')::numeric,
 nullif(trim(p_payload->>'duration'),''),nullif(trim(p_payload->>'governorate'),''),nullif(trim(p_payload->>'pdf_url'),''),
 nullif(trim(p_payload->>'qr_code'),''),coalesce((p_payload->>'visible_to_companies')::boolean,false),
 case when coalesce((p_payload->>'visible_to_companies')::boolean,false) then now() else null end,'active','institution') returning id into v_id;
 update public.institutions set quota_used=quota_used+1,updated_at=now() where id=v_inst;
 update public.subscriptions set quota_used=quota_used+1,updated_at=now() where id=v_sub.id;
 insert into public.activity_log(actor_id,actor_type,action,target_type,target_id,details)
 values(v_uid,'institution','certificate_issued','certificate',v_id,jsonb_build_object('cert_number',v_number,'institution_id',v_inst)::text);
 return query select v_id,v_number;
end; $$;

create or replace function public.admin_add_certificate_v2(p_source text,p_institution_id uuid,p_record_type text,p_student_name text,
 p_student_name_en text default null,p_course text default null,p_specialization text default null,p_issue_date date default null,
 p_duration text default null,p_grade text default null,p_university text default null,p_faculty text default null,
 p_academic_degree text default null,p_graduation_year integer default null,p_declaration_accepted boolean default false)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_number bigint; v_cert_number text; v_institution_name text; v_cert_id uuid; v_acquisition_date date;
begin
 if auth.uid() is null or not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
 if p_source not in ('admin','institution') then raise exception 'INVALID_SOURCE'; end if;
 if p_record_type not in ('training','academic') then raise exception 'INVALID_RECORD_TYPE'; end if;
 if nullif(trim(p_student_name),'') is null then raise exception 'STUDENT_NAME_REQUIRED'; end if;
 if coalesce(p_declaration_accepted,false) is not true then raise exception 'DECLARATION_REQUIRED'; end if;
 if p_source='institution' then
  if p_institution_id is null then raise exception 'INSTITUTION_REQUIRED'; end if;
  select name into v_institution_name from public.institutions where id=p_institution_id and status='approved';
  if not found then raise exception 'INSTITUTION_NOT_APPROVED'; end if;
 elsif p_institution_id is not null then raise exception 'ADMIN_SOURCE_MUST_NOT_HAVE_INSTITUTION'; end if;
 if p_record_type='academic' then
  if nullif(trim(p_university),'') is null or nullif(trim(p_faculty),'') is null or nullif(trim(p_academic_degree),'') is null then raise exception 'ACADEMIC_FIELDS_REQUIRED'; end if;
  if p_graduation_year is null or p_graduation_year not between 1950 and extract(year from current_date)::integer+1 then raise exception 'INVALID_GRADUATION_YEAR'; end if;
  v_acquisition_date:=make_date(p_graduation_year,6,30);
 else
  if nullif(trim(p_course),'') is null or p_issue_date is null then raise exception 'COURSE_AND_ACQUISITION_DATE_REQUIRED'; end if;
  v_acquisition_date:=p_issue_date;
 end if;
 insert into public.certificate_sequences(sequence_key,last_number) values('global',1)
 on conflict(sequence_key) do update set last_number=public.certificate_sequences.last_number+1,updated_at=now() returning last_number into v_number;
 v_cert_number:='SH-'||extract(year from current_date)::integer||'-'||lpad(v_number::text,6,'0');
 insert into public.certificates(institution_id,cert_number,student_name,student_name_en,course,specialization,issue_date,acquisition_date,
 duration,grade,status,added_by,record_type,source_type,academic_university,academic_faculty,academic_degree,graduation_year,
 declaration_accepted,declaration_accepted_at)
 values(p_institution_id,v_cert_number,trim(p_student_name),nullif(trim(p_student_name_en),''),
 case when p_record_type='academic' then 'مؤهل علمي' else trim(p_course) end,
 case when p_record_type='academic' then trim(p_faculty) else nullif(trim(p_specialization),'') end,
 current_date,v_acquisition_date,nullif(trim(p_duration),''),nullif(trim(p_grade),''),'active','admin',p_record_type,p_source,
 nullif(trim(p_university),''),nullif(trim(p_faculty),''),nullif(trim(p_academic_degree),''),p_graduation_year,true,now())
 returning id into v_cert_id;
 insert into public.activity_log(action,cert_number,details,actor_id,actor_type,target_type,target_id)
 values('admin_add_certificate',v_cert_number,case when p_record_type='academic' then 'تسجيل مؤهل علمي: '||trim(p_academic_degree)||' - '||trim(p_university) else 'تسجيل شهادة تدريبية' end,
 auth.uid(),'admin','certificate',v_cert_id);
 return jsonb_build_object('success',true,'certificate_id',v_cert_id,'cert_number',v_cert_number,'institution_id',p_institution_id,
 'institution_name',coalesce(v_institution_name,'إدارة منصة شهادتي'),'record_type',p_record_type,'source_type',p_source);
end; $$;

drop function if exists public.verify_certificate(text);
create function public.verify_certificate(p_cert_number text)
returns table(cert_number text,student_name text,course text,specialization text,issue_date date,grade text,duration text,status text,
 institution_name text,institution_type text,record_type text,source_type text,academic_university text,academic_faculty text,
 academic_degree text,graduation_year integer,acquisition_date date)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cert public.certificates%rowtype; v_inst public.institutions%rowtype;
begin
 select c.* into v_cert from public.certificates c where upper(trim(c.cert_number))=upper(trim(p_cert_number)) limit 1;
 if not found then raise exception 'CERTIFICATE_NOT_FOUND'; end if;
 if v_cert.institution_id is not null then
  select * into v_inst from public.institutions where id=v_cert.institution_id;
  if not found or v_inst.status<>'approved' then raise exception 'CERTIFICATE_NOT_FOUND'; end if;
 elsif coalesce(v_cert.source_type,'institution')<>'admin' then raise exception 'CERTIFICATE_NOT_FOUND'; end if;
 if to_regclass('public.certificate_verifications') is not null then
  insert into public.certificate_verifications(cert_number,certificate_id,result,checked_at)
  values(v_cert.cert_number,v_cert.id,case when v_cert.status='active' then 'valid' else 'invalid' end,now());
 end if;
 return query select v_cert.cert_number,v_cert.student_name,v_cert.course,v_cert.specialization,v_cert.issue_date,v_cert.grade,
 v_cert.duration,v_cert.status,coalesce(v_inst.name,'إدارة منصة شهادتي'),coalesce(v_inst.institution_type,'إدارة المنصة'),
 coalesce(v_cert.record_type,'training'),coalesce(v_cert.source_type,'institution'),v_cert.academic_university,v_cert.academic_faculty,
 v_cert.academic_degree,v_cert.graduation_year,coalesce(v_cert.acquisition_date,v_cert.issue_date);
end; $$;

drop function if exists public.verify_certificate_details(text);
create function public.verify_certificate_details(p_cert_number text)
returns table(cert_number text,student_name text,student_name_en text,course text,specialization text,issue_date date,grade text,duration text,
 status text,institution_name text,institution_type text,record_type text,source_type text,academic_university text,academic_faculty text,
 academic_degree text,graduation_year integer,declaration_accepted boolean,acquisition_date date)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cert public.certificates%rowtype; v_inst public.institutions%rowtype;
begin
 select c.* into v_cert from public.certificates c where upper(trim(c.cert_number))=upper(trim(p_cert_number)) limit 1;
 if not found then return; end if;
 if v_cert.institution_id is not null then
  select * into v_inst from public.institutions where id=v_cert.institution_id;
  if not found or v_inst.status<>'approved' then return; end if;
 elsif v_cert.source_type<>'admin' then return; end if;
 return query select v_cert.cert_number,v_cert.student_name,v_cert.student_name_en,v_cert.course,v_cert.specialization,v_cert.issue_date,
 v_cert.grade,v_cert.duration,v_cert.status,coalesce(v_inst.name,'إدارة منصة شهادتي'),coalesce(v_inst.institution_type,'إدارة المنصة'),
 v_cert.record_type,v_cert.source_type,v_cert.academic_university,v_cert.academic_faculty,v_cert.academic_degree,v_cert.graduation_year,
 v_cert.declaration_accepted,coalesce(v_cert.acquisition_date,v_cert.issue_date);
end; $$;

drop function if exists public.graduate_my_certificates();
create function public.graduate_my_certificates()
returns table(cert_number text,course text,issue_date date,grade text,acquisition_date date)
language plpgsql stable security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 return query select c.cert_number,c.course,c.issue_date,c.grade,coalesce(c.acquisition_date,c.issue_date)
 from public.graduate_profiles gp join public.certificates c
 on regexp_replace(coalesce(gp.phone,''),'[^0-9]','','g')=regexp_replace(coalesce(c.student_phone,''),'[^0-9]','','g')
 join public.institutions i on i.id=c.institution_id
 where gp.auth_user_id=auth.uid() and nullif(regexp_replace(coalesce(gp.phone,''),'[^0-9]','','g'),'') is not null
 and i.status='approved' and c.status='active' order by coalesce(c.acquisition_date,c.issue_date) desc,c.created_at desc;
end; $$;

create or replace function public.admin_list_certificates(p_search text default null)
returns table(id uuid,cert_number text,student_name text,course text,specialization text,issue_date date,duration text,grade text,status text,
 institution_id uuid,institution_name text,created_at timestamptz)
language plpgsql security definer set search_path=public as $$
begin
 if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
 return query select c.id,c.cert_number,c.student_name,c.course,c.specialization,coalesce(c.acquisition_date,c.issue_date),
 c.duration,c.grade,c.status,c.institution_id,i.name,c.created_at from public.certificates c left join public.institutions i on i.id=c.institution_id
 where coalesce(nullif(trim(p_search),''),'')='' or c.cert_number ilike '%'||trim(p_search)||'%'
 or c.student_name ilike '%'||trim(p_search)||'%' or c.course ilike '%'||trim(p_search)||'%'
 order by c.created_at desc limit 100;
end; $$;

create or replace function public.admin_list_certificates_with_consent(p_search text default null)
returns table(id uuid,cert_number text,student_name text,course text,specialization text,issue_date date,duration text,grade text,status text,
 institution_id uuid,institution_name text,created_at timestamptz,declaration_accepted boolean)
language plpgsql security definer set search_path=public as $$
begin
 if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
 return query select c.id,c.cert_number,c.student_name,c.course,c.specialization,coalesce(c.acquisition_date,c.issue_date),
 c.duration,c.grade,c.status,c.institution_id,i.name,c.created_at,coalesce(c.declaration_accepted,false)
 from public.certificates c left join public.institutions i on i.id=c.institution_id
 where coalesce(nullif(trim(p_search),''),'')='' or c.cert_number ilike '%'||trim(p_search)||'%'
 or c.student_name ilike '%'||trim(p_search)||'%' or c.course ilike '%'||trim(p_search)||'%'
 or c.specialization ilike '%'||trim(p_search)||'%' or c.academic_university ilike '%'||trim(p_search)||'%'
 or c.academic_faculty ilike '%'||trim(p_search)||'%' or c.academic_degree ilike '%'||trim(p_search)||'%'
 order by c.created_at desc limit 300;
end; $$;

create or replace function public.search_public_alumni(p_qualification text,p_university text default null,p_college text default null,
 p_graduation_year integer default null,p_grade text default null)
returns table(full_name text,qualification_name text,institution_name text,faculty_name text,graduation_year integer,grade text)
language sql stable security definer set search_path=public,pg_temp as $function$
with search_input as (
 select regexp_replace(regexp_replace(translate(lower(trim(coalesce(p_qualification,''))),'أإآٱىةـ','اااايه'),
 '^(ليسانس|بكالوريوس|بكالريوس|بكلوريوس|بكالوريس|دبلوم|ماجستير|دكتوراه)[[:space:]]+',''), '^[[:space:]]*ال','') search_key
), candidates as (
 select p.full_name::text full_name,q.qualification_name::text qualification_name,q.institution_name::text institution_name,
 q.faculty_name::text faculty_name,q.graduation_year::integer graduation_year,q.grade::text grade,
 regexp_replace(regexp_replace(translate(lower(trim(coalesce(q.qualification_name,'')||' '||coalesce(p.full_name,''))),'أإآٱىةـ','اااايه'),
 '^(ليسانس|بكالوريوس|بكالريوس|بكلوريوس|بكالوريس|دبلوم|ماجستير|دكتوراه)[[:space:]]+',''), '^[[:space:]]*ال','') searchable_text
 from public.alumni_profiles p join public.alumni_qualifications q on q.alumni_id=p.id
 where p.visibility_status='public' and p.publication_consent is true
 union all
 select c.student_name::text,c.course::text,i.name::text,c.specialization::text,extract(year from coalesce(c.acquisition_date,c.issue_date))::integer,
 c.grade::text,translate(lower(trim(coalesce(c.course,'')||' '||coalesce(c.specialization,'')||' '||coalesce(c.student_name,'')||' '||coalesce(c.student_name_en,''))),'أإآٱىةـ','اااايه')
 from public.certificates c left join public.institutions i on i.id=c.institution_id
 where c.record_type='training' and c.status='active' and c.declaration_accepted is true
)
select c.full_name,c.qualification_name,c.institution_name,c.faculty_name,c.graduation_year,c.grade
from candidates c cross join search_input s where s.search_key<>'' and c.searchable_text ilike '%'||s.search_key||'%'
and (nullif(trim(p_university),'') is null or coalesce(c.institution_name,'') ilike '%'||trim(p_university)||'%')
and (nullif(trim(p_college),'') is null or coalesce(c.faculty_name,'') ilike '%'||trim(p_college)||'%')
and (p_graduation_year is null or c.graduation_year=p_graduation_year)
and (nullif(trim(p_grade),'') is null or coalesce(c.grade,'') ilike '%'||trim(p_grade)||'%')
order by c.full_name,c.graduation_year desc nulls last limit 100;
$function$;

revoke all on function public.verify_certificate(text) from public,anon;
revoke all on function public.verify_certificate_details(text) from public,anon;
grant execute on function public.verify_certificate(text) to anon,authenticated;
grant execute on function public.verify_certificate_details(text) to anon,authenticated;
revoke all on function public.search_public_alumni(text,text,text,integer,text) from public;
grant execute on function public.search_public_alumni(text,text,text,integer,text) to anon,authenticated;

revoke all on function public.admin_list_certificates(text) from public,anon;
revoke all on function public.admin_list_certificates_with_consent(text) from public,anon;
grant execute on function public.admin_list_certificates(text) to authenticated;
grant execute on function public.admin_list_certificates_with_consent(text) to authenticated;
revoke all on function public.admin_add_certificate_v2(text,uuid,text,text,text,text,text,date,text,text,text,text,text,integer,boolean) from public,anon;
grant execute on function public.admin_add_certificate_v2(text,uuid,text,text,text,text,text,date,text,text,text,text,text,integer,boolean) to authenticated;
