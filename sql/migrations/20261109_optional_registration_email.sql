-- Allow institutions to register with a verified phone account and no email.
-- Email-based accounts continue storing their Auth email as contact_email.
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

  select nullif(lower(trim(email)), '') into v_email
  from auth.users where id=v_uid;

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
    v_email,trim(p_contact_phone),trim(p_commercial_registration_number),
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
