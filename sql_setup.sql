-- ============================================================
-- شهادتي | FINAL DATABASE ALIGNMENT
-- هذه هي النسخة النهائية المتوافقة مع قاعدة البيانات الحالية.
-- آمنة لإعادة التشغيل: لا تعيد إنشاء هياكل V1 القديمة ولا تعيد
-- تفعيل accreditation_requests أو is_active أو end_at.
-- ============================================================

create extension if not exists "uuid-ossp";

-- ------------------------------------------------------------
-- 1) Current schema alignment
-- ------------------------------------------------------------
alter table public.packages add column if not exists quota_limit integer not null default 10;
alter table public.packages add column if not exists sort_order integer not null default 0;
alter table public.packages add column if not exists created_at timestamptz not null default now();
update public.packages set quota_limit=10 where quota_limit is null;

alter table public.institutions add column if not exists institution_type text;
alter table public.institutions add column if not exists address text;
alter table public.institutions add column if not exists commercial_registration_number text;
alter table public.institutions add column if not exists tax_card_number text;
alter table public.institutions add column if not exists owner_name text;
alter table public.institutions add column if not exists manager_name text;
alter table public.institutions add column if not exists rejection_reason text;
alter table public.institutions add column if not exists approved_at timestamptz;
alter table public.institutions add column if not exists approved_by uuid references auth.users(id) on delete set null;
alter table public.institutions add column if not exists request_number text;
alter table public.institutions add column if not exists quota_used integer not null default 0;
alter table public.institutions add column if not exists quota_total integer not null default 10;
alter table public.institutions add column if not exists updated_at timestamptz not null default now();

update public.institutions
set status='pending'
where status is null or trim(status)='';

alter table public.institution_users add column if not exists role text not null default 'owner';
alter table public.institution_users add column if not exists status text not null default 'active';
update public.institution_users set status='active' where status is null;
alter table public.institution_users drop constraint if exists institution_users_role_check;
alter table public.institution_users add constraint institution_users_role_check
  check (role in ('owner','manager','staff','viewer'));
alter table public.institution_users drop constraint if exists institution_users_status_check;
alter table public.institution_users add constraint institution_users_status_check
  check (status in ('active','inactive','suspended'));

alter table public.institution_documents add column if not exists file_path text;
alter table public.institution_documents add column if not exists file_url text;
alter table public.institution_documents add column if not exists uploaded_by uuid references auth.users(id) on delete set null;
alter table public.institution_documents add column if not exists uploaded_at timestamptz not null default now();
alter table public.institution_documents add column if not exists updated_at timestamptz not null default now();

alter table public.subscriptions add column if not exists starts_at timestamptz;
alter table public.subscriptions add column if not exists ends_at timestamptz;
alter table public.subscriptions add column if not exists quota_limit integer not null default 0;
alter table public.subscriptions add column if not exists quota_used integer not null default 0;
alter table public.subscriptions add column if not exists currency text not null default 'EGP';
alter table public.subscriptions add column if not exists payment_status text not null default 'unpaid';
alter table public.subscriptions add column if not exists payment_reference text;
update public.subscriptions set starts_at=coalesce(starts_at,now()) where starts_at is null;
update public.subscriptions set quota_limit=coalesce(quota_limit,0) where quota_limit is null;
alter table public.subscriptions drop constraint if exists subscriptions_billing_cycle_check;
alter table public.subscriptions add constraint subscriptions_billing_cycle_check
  check (billing_cycle in ('monthly','yearly'));
alter table public.subscriptions drop constraint if exists subscriptions_payment_status_check;
alter table public.subscriptions add constraint subscriptions_payment_status_check
  check (payment_status in ('unpaid','pending','paid','failed','refunded'));

alter table public.certificates add column if not exists visible_to_companies boolean not null default false;
alter table public.certificates add column if not exists consent_given_at timestamptz;
alter table public.certificates add column if not exists student_phone text;
update public.certificates set visible_to_companies=false where visible_to_companies is null;

-- ------------------------------------------------------------
-- 2) Indexes / numbering
-- ------------------------------------------------------------
create unique index if not exists packages_name_unique_idx on public.packages(name);
create unique index if not exists institutions_auth_user_id_unique_idx
  on public.institutions(auth_user_id) where auth_user_id is not null;
create unique index if not exists certificates_cert_number_unique_idx on public.certificates(cert_number);
create index if not exists certificates_institution_idx on public.certificates(institution_id);
create index if not exists certificates_status_idx on public.certificates(status);
create index if not exists institutions_status_idx on public.institutions(status);
create index if not exists institution_users_auth_user_idx on public.institution_users(auth_user_id);
create index if not exists institution_users_institution_idx on public.institution_users(institution_id);
create index if not exists institution_documents_institution_idx on public.institution_documents(institution_id);

create table if not exists public.certificate_sequences (
  sequence_key text primary key,
  last_number bigint not null default 0,
  updated_at timestamptz not null default now()
);
insert into public.certificate_sequences(sequence_key,last_number)
values('global',0)
on conflict(sequence_key) do nothing;

create or replace function public.get_next_certificate_number()
returns bigint
language plpgsql
security definer
set search_path=public
as $$
declare v_number bigint;
begin
  update public.certificate_sequences
  set last_number=last_number+1,updated_at=now()
  where sequence_key='global'
  returning last_number into v_number;
  if v_number is null then
    insert into public.certificate_sequences(sequence_key,last_number)
    values('global',1)
    returning last_number into v_number;
  end if;
  return v_number;
end;
$$;

create or replace function public.generate_certificate_number()
returns text
language plpgsql
security definer
set search_path=public
as $$
begin
  return 'SH-' || to_char(current_date,'YYYY') || '-' ||
         lpad(public.get_next_certificate_number()::text,6,'0');
end;
$$;

grant execute on function public.get_next_certificate_number() to authenticated;
grant execute on function public.generate_certificate_number() to authenticated;

-- ------------------------------------------------------------
-- 3) Security helpers
-- ------------------------------------------------------------
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.platform_admins
    where auth_user_id=auth.uid() and status='active'
  );
$$;

create or replace function public.is_institution_member(p_institution_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.institution_users
    where institution_id=p_institution_id
      and auth_user_id=auth.uid()
      and status='active'
  );
$$;

create or replace function public.has_institution_role(p_institution_id uuid,p_roles text[])
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.institution_users
    where institution_id=p_institution_id
      and auth_user_id=auth.uid()
      and status='active'
      and role=any(p_roles)
  );
$$;

revoke all on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to authenticated;
revoke all on function public.is_institution_member(uuid) from public;
grant execute on function public.is_institution_member(uuid) to authenticated;
revoke all on function public.has_institution_role(uuid,text[]) from public;
grant execute on function public.has_institution_role(uuid,text[]) to authenticated;

-- ------------------------------------------------------------
-- 4) Secure registration RPC
-- ------------------------------------------------------------
create or replace function public.register_institution(
  p_name text,
  p_institution_type text,
  p_governorate text,
  p_address text,
  p_commercial_registration_number text,
  p_tax_card_number text,
  p_owner_name text,
  p_manager_name text,
  p_contact_phone text,
  p_package_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_email text;
  v_inst uuid;
  v_req text;
  v_quota integer;
  v_pkg record;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select email into v_email from auth.users where id=v_uid;
  if coalesce(trim(v_email),'')='' then raise exception 'EMAIL_REQUIRED'; end if;

  if coalesce(trim(p_name),'')='' or coalesce(trim(p_institution_type),'')='' or
     coalesce(trim(p_governorate),'')='' or coalesce(trim(p_address),'')='' or
     coalesce(trim(p_commercial_registration_number),'')='' or
     coalesce(trim(p_tax_card_number),'')='' or coalesce(trim(p_owner_name),'')='' or
     coalesce(trim(p_manager_name),'')='' or coalesce(trim(p_contact_phone),'')='' then
    raise exception 'REQUIRED_FIELDS';
  end if;

  if exists(select 1 from public.institutions where auth_user_id=v_uid) then
    raise exception 'INSTITUTION_ALREADY_EXISTS';
  end if;

  select * into v_pkg from public.packages where id=p_package_id limit 1;
  if not found then raise exception 'PACKAGE_NOT_FOUND'; end if;
  v_quota:=coalesce(v_pkg.quota_limit,10);

  v_req:='REQ-'||to_char(current_date,'YYYYMMDD')||'-'||
         upper(substr(replace(v_uid::text,'-',''),1,8));

  insert into public.institutions(
    auth_user_id,name,institution_type,governorate,address,
    contact_email,contact_phone,commercial_registration_number,
    tax_card_number,owner_name,manager_name,package_id,status,
    quota_used,quota_total,request_number,created_at,updated_at
  ) values(
    v_uid,trim(p_name),trim(p_institution_type),trim(p_governorate),trim(p_address),
    lower(trim(v_email)),trim(p_contact_phone),trim(p_commercial_registration_number),
    trim(p_tax_card_number),trim(p_owner_name),trim(p_manager_name),p_package_id,'pending',
    0,v_quota,v_req,now(),now()
  ) returning id into v_inst;

  insert into public.institution_users(institution_id,auth_user_id,role,status)
  values(v_inst,v_uid,'owner','active')
  on conflict(institution_id,auth_user_id) do update
  set role='owner',status='active';

  return jsonb_build_object(
    'success',true,
    'institution_id',v_inst,
    'request_number',v_req,
    'status','pending',
    'package_id',p_package_id,
    'quota_total',v_quota
  );
end;
$$;

revoke all on function public.register_institution(text,text,text,text,text,text,text,text,text,uuid) from public;
grant execute on function public.register_institution(text,text,text,text,text,text,text,text,text,uuid) to authenticated;

-- ------------------------------------------------------------
-- 5) Secure certificate issuance
-- ------------------------------------------------------------
create or replace function public.issue_certificate(p_payload jsonb)
returns table(cert_id uuid,cert_number text)
language plpgsql
security definer
set search_path=public
as $
declare
  v_uid uuid:=auth.uid();
  v_inst uuid:=(p_payload->>'institution_id')::uuid;
  v_inst_row public.institutions%rowtype;
  v_id uuid;
  v_number text;
  v_day date:=coalesce(nullif(p_payload->>'issue_date','')::date,current_date);
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select i.* into v_inst_row
  from public.institutions i
  join public.institution_users iu on iu.institution_id=i.id
  where i.id=v_inst and iu.auth_user_id=v_uid and iu.status='active'
    and iu.role in ('owner','manager','staff')
  for update of i;

  if not found then raise exception 'NOT_ALLOWED'; end if;
  if v_inst_row.status<>'approved' then raise exception 'INSTITUTION_NOT_APPROVED'; end if;
  if v_inst_row.quota_used>=v_inst_row.quota_total then raise exception 'QUOTA_EXCEEDED'; end if;
  if coalesce(trim(p_payload->>'student_name'),'')='' or coalesce(trim(p_payload->>'course'),'')='' then
    raise exception 'REQUIRED_FIELDS';
  end if;

  v_number:=public.generate_certificate_number();

  insert into public.certificates(
    institution_id,cert_number,student_name,student_name_en,student_national_id,
    student_phone,course,specialization,issue_date,expiry_date,grade,grade_value,
    duration,governorate,pdf_url,qr_code,visible_to_companies,consent_given_at,status,added_by
  ) values(
    v_inst,v_number,trim(p_payload->>'student_name'),nullif(trim(p_payload->>'student_name_en'),''),
    nullif(trim(p_payload->>'student_national_id'),''),nullif(trim(p_payload->>'student_phone'),''),
    trim(p_payload->>'course'),nullif(trim(p_payload->>'specialization'),''),v_day,
    nullif(p_payload->>'expiry_date','')::date,nullif(trim(p_payload->>'grade'),''),
    nullif(p_payload->>'grade_value','')::numeric,nullif(trim(p_payload->>'duration'),''),
    nullif(trim(p_payload->>'governorate'),''),nullif(trim(p_payload->>'pdf_url'),''),
    nullif(trim(p_payload->>'qr_code'),''),coalesce((p_payload->>'visible_to_companies')::boolean,false),
    case when coalesce((p_payload->>'visible_to_companies')::boolean,false) then now() else null end,
    'active','institution'
  ) returning id into v_id;

  update public.institutions set quota_used=quota_used+1,updated_at=now() where id=v_inst;

  if to_regclass('public.activity_log') is not null then
    insert into public.activity_log(actor_id,actor_type,action,target_type,target_id,details)
    values(v_uid,'institution','certificate_issued','certificate',v_id,
           jsonb_build_object('cert_number',v_number,'institution_id',v_inst));
  end if;

  return query select v_id,v_number;
end;
$;

grant execute on function public.issue_certificate(jsonb) to authenticated;

-- ------------------------------------------------------------
-- 5) Platform admin RPCs
-- ------------------------------------------------------------
create or replace function public.admin_update_institution_quota(p_institution_id uuid,p_quota_total integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_row public.institutions%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_quota_total is null or p_quota_total<0 then raise exception 'INVALID_QUOTA'; end if;
  update public.institutions set quota_total=p_quota_total,updated_at=now()
  where id=p_institution_id returning * into v_row;
  if not found then raise exception 'INSTITUTION_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'institution_id',v_row.id,'quota_total',v_row.quota_total,'quota_used',v_row.quota_used);
end; $$;

create or replace function public.admin_list_certificates(p_search text default null)
returns table(id uuid,cert_number text,student_name text,course text,specialization text,
 issue_date date,duration text,grade text,status text,institution_id uuid,institution_name text,created_at timestamptz)
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  return query
  select c.id,c.cert_number,c.student_name,c.course,c.specialization,c.issue_date,c.duration,c.grade,
         c.status,c.institution_id,i.name,c.created_at
  from public.certificates c left join public.institutions i on i.id=c.institution_id
  where coalesce(nullif(trim(p_search),''),'')=''
     or c.cert_number ilike '%'||trim(p_search)||'%'
     or c.student_name ilike '%'||trim(p_search)||'%'
     or c.course ilike '%'||trim(p_search)||'%'
  order by c.created_at desc limit 100;
end; $$;

create or replace function public.admin_revoke_certificate(p_certificate_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_cert public.certificates%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  update public.certificates set status='revoked',updated_at=now()
  where id=p_certificate_id and status='active' returning * into v_cert;
  if not found then raise exception 'CERTIFICATE_NOT_FOUND_OR_ALREADY_REVOKED'; end if;
  return jsonb_build_object('success',true,'certificate_id',v_cert.id,'cert_number',v_cert.cert_number,'status',v_cert.status);
end; $$;

create or replace function public.admin_platform_stats()
returns jsonb language plpgsql security definer set search_path=public as $$
declare a integer;p integer;c integer;ac integer;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  select count(*)::int into a from public.institutions where status='approved';
  select count(*)::int into p from public.institutions where status='pending';
  select count(*)::int into c from public.certificates;
  select count(*)::int into ac from public.certificates where status='active';
  return jsonb_build_object('approved_institutions',a,'pending_institutions',p,'certificates',c,'active_certificates',ac);
end; $$;

create or replace function public.admin_list_institution_documents(p_institution_id uuid)
returns table(id uuid,institution_id uuid,document_type text,file_name text,file_path text,status text,
 rejection_reason text,uploaded_at timestamptz,reviewed_at timestamptz)
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  return query select d.id,d.institution_id,d.document_type,d.file_name,d.file_path,d.status,
    d.rejection_reason,d.uploaded_at,d.reviewed_at
  from public.institution_documents d where d.institution_id=p_institution_id order by d.uploaded_at desc;
end; $$;

create or replace function public.review_document(p_document_id uuid,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d public.institution_documents%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_status not in ('pending','approved','rejected') then raise exception 'INVALID_DOCUMENT_STATUS'; end if;
  if p_status='rejected' and coalesce(trim(p_reason),'')='' then raise exception 'REJECTION_REASON_REQUIRED'; end if;
  update public.institution_documents set status=p_status,
    rejection_reason=case when p_status='rejected' then trim(p_reason) else null end,
    reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now()
  where id=p_document_id returning * into d;
  if not found then raise exception 'DOCUMENT_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'document_id',d.id,'status',d.status);
end; $$;

create or replace function public.admin_list_recruitment_requests(p_status text default null)
returns setof public.recruitment_requests
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  return query select r.* from public.recruitment_requests r
  where coalesce(nullif(trim(p_status),''),'')='' or r.status=trim(p_status)
  order by r.created_at desc limit 500;
end; $$;

create or replace function public.admin_update_recruitment_status(p_request_id uuid,p_status text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.recruitment_requests%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_status not in ('new','processing','fulfilled','closed') then raise exception 'INVALID_STATUS'; end if;
  update public.recruitment_requests set status=p_status where id=p_request_id returning * into r;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'id',r.id,'status',r.status);
end; $$;

create or replace function public.admin_list_companies()
returns setof public.companies
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  return query select c.* from public.companies c order by c.created_at desc limit 500;
end; $$;

create or replace function public.admin_update_company(p_company_id uuid,p_status text default null,p_search_credits integer default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.companies%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_status is not null and p_status not in ('pending','approved','suspended') then raise exception 'INVALID_STATUS'; end if;
  if p_search_credits is not null and p_search_credits<0 then raise exception 'INVALID_CREDITS'; end if;
  update public.companies set status=coalesce(p_status,status),search_credits=coalesce(p_search_credits,search_credits)
  where id=p_company_id returning * into c;
  if not found then raise exception 'COMPANY_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'id',c.id,'status',c.status,'search_credits',c.search_credits);
end; $$;

grant execute on function public.admin_update_institution_quota(uuid,integer) to authenticated;
grant execute on function public.admin_list_certificates(text) to authenticated;
grant execute on function public.admin_revoke_certificate(uuid) to authenticated;
grant execute on function public.admin_platform_stats() to authenticated;
grant execute on function public.admin_list_institution_documents(uuid) to authenticated;
grant execute on function public.review_document(uuid,text,text) to authenticated;
grant execute on function public.admin_list_recruitment_requests(text) to authenticated;
grant execute on function public.admin_update_recruitment_status(uuid,text) to authenticated;
grant execute on function public.admin_list_companies() to authenticated;
grant execute on function public.admin_update_company(uuid,text,integer) to authenticated;

-- ------------------------------------------------------------
-- 6) RLS helper policies for current model
-- ------------------------------------------------------------
alter table public.institutions enable row level security;
alter table public.institution_users enable row level security;
alter table public.institution_documents enable row level security;
alter table public.subscriptions enable row level security;
alter table public.certificates enable row level security;
alter table public.certificate_verifications enable row level security;

drop policy if exists institutions_select_member on public.institutions;
create policy institutions_select_member on public.institutions for select to authenticated
using (auth_user_id=auth.uid() or public.is_institution_member(id));

drop policy if exists institutions_insert_self on public.institutions;
create policy institutions_insert_self on public.institutions for insert to authenticated
with check (auth_user_id=auth.uid());

drop policy if exists institutions_update_manager on public.institutions;
create policy institutions_update_manager on public.institutions for update to authenticated
using (public.has_institution_role(id,array['owner','manager']))
with check (public.has_institution_role(id,array['owner','manager']));

drop policy if exists institution_users_select_member on public.institution_users;
create policy institution_users_select_member on public.institution_users for select to authenticated
using (auth_user_id=auth.uid() or public.has_institution_role(institution_id,array['owner','manager']));

drop policy if exists institution_documents_select_member on public.institution_documents;
create policy institution_documents_select_member on public.institution_documents for select to authenticated
using (public.is_institution_member(institution_id));

drop policy if exists institution_documents_insert_staff on public.institution_documents;
create policy institution_documents_insert_staff on public.institution_documents for insert to authenticated
with check (public.has_institution_role(institution_id,array['owner','manager','staff']));

drop policy if exists institution_documents_update_manager on public.institution_documents;
create policy institution_documents_update_manager on public.institution_documents for update to authenticated
using (public.has_institution_role(institution_id,array['owner','manager']))
with check (public.has_institution_role(institution_id,array['owner','manager']));

drop policy if exists subscriptions_select_member on public.subscriptions;
create policy subscriptions_select_member on public.subscriptions for select to authenticated
using (public.is_institution_member(institution_id));

drop policy if exists certificates_select_member on public.certificates;
create policy certificates_select_member on public.certificates for select to authenticated
using (public.is_institution_member(institution_id));

drop policy if exists certificates_update_manager on public.certificates;
create policy certificates_update_manager on public.certificates for update to authenticated
using (public.has_institution_role(institution_id,array['owner','manager']))
with check (public.has_institution_role(institution_id,array['owner','manager']));

-- Public verification must use verify_certificate(), not direct table access.
drop policy if exists certs_public_verify on public.certificates;
drop policy if exists certs_own on public.certificates;

-- ------------------------------------------------------------
-- 7) Private document storage
-- ------------------------------------------------------------
insert into storage.buckets(id,name,public)
values('institution-documents','institution-documents',false)
on conflict(id) do update set public=false;

drop policy if exists institution_docs_storage_read on storage.objects;
create policy institution_docs_storage_read on storage.objects for select
using (
  bucket_id='institution-documents' and
  (public.is_platform_admin() or exists(
    select 1 from public.institution_users iu
    where iu.institution_id::text=(storage.foldername(name))[1]
      and iu.auth_user_id=auth.uid() and iu.status='active'
  ))
);

drop policy if exists institution_docs_storage_insert on storage.objects;
create policy institution_docs_storage_insert on storage.objects for insert
with check (
  bucket_id='institution-documents' and exists(
    select 1 from public.institution_users iu
    where iu.institution_id::text=(storage.foldername(name))[1]
      and iu.auth_user_id=auth.uid() and iu.status='active'
      and iu.role in ('owner','manager','staff')
  )
);

drop policy if exists institution_docs_storage_update on storage.objects;
create policy institution_docs_storage_update on storage.objects for update
using (
  bucket_id='institution-documents' and
  (public.is_platform_admin() or exists(
    select 1 from public.institution_users iu
    where iu.institution_id::text=(storage.foldername(name))[1]
      and iu.auth_user_id=auth.uid() and iu.status='active'
      and iu.role in ('owner','manager','staff')
  ))
) with check(bucket_id='institution-documents');

drop policy if exists institution_docs_storage_delete on storage.objects;
create policy institution_docs_storage_delete on storage.objects for delete
using (
  bucket_id='institution-documents' and
  (public.is_platform_admin() or exists(
    select 1 from public.institution_users iu
    where iu.institution_id::text=(storage.foldername(name))[1]
      and iu.auth_user_id=auth.uid() and iu.status='active'
      and iu.role in ('owner','manager','staff')
  ))
);

-- ------------------------------------------------------------
-- 8) Remove stale V1 functions that could reintroduce old model.
-- We intentionally keep legacy tables untouched to avoid data loss.
-- ------------------------------------------------------------
drop function if exists public.create_institution_from_registration() cascade;
drop function if exists public.review_institution(uuid,text,text);
drop function if exists public.revoke_my_certificate(uuid);
drop function if exists public.is_admin();

-- End of final alignment.
