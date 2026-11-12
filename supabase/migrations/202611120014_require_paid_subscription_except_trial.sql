-- A zero-value subscription is free only for the explicitly free trial package.
-- Paid plans require a confirmed payment before certificate issuance.
create or replace function public.issue_certificate(p_payload jsonb)
returns table(cert_id uuid, cert_number text)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid:=auth.uid();
  v_inst uuid:=(p_payload->>'institution_id')::uuid;
  v_inst_row public.institutions%rowtype;
  v_sub public.subscriptions%rowtype;
  v_id uuid;
  v_number text;
  v_acquisition_date date:=coalesce(
    nullif(p_payload->>'acquisition_date','')::date,
    nullif(p_payload->>'issue_date','')::date
  );
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select i.* into v_inst_row
  from public.institutions i
  join public.institution_users iu on iu.institution_id=i.id
  where i.id=v_inst
    and iu.auth_user_id=v_uid
    and iu.status='active'
    and iu.role in ('owner','manager','staff')
  for update of i;

  if not found then
    raise exception 'NOT_ALLOWED';
  end if;

  if v_inst_row.status<>'approved' then
    raise exception 'INSTITUTION_NOT_APPROVED';
  end if;

  select s.* into v_sub
  from public.subscriptions s
  left join public.packages p on p.id=s.package_id
  where s.institution_id=v_inst
    and s.status='active'
    and (s.starts_at is null or s.starts_at<=now())
    and (s.ends_at is null or s.ends_at>now())
    and (
      s.payment_status='paid'
      or (coalesce(s.amount,0)=0 and p.name='trial')
    )
  order by s.created_at desc
  limit 1
  for update of s;

  if not found then
    raise exception 'SUBSCRIPTION_INACTIVE_OR_UNPAID';
  end if;

  if v_sub.quota_used>=v_sub.quota_limit or v_inst_row.quota_used>=v_inst_row.quota_total then
    raise exception 'QUOTA_EXCEEDED';
  end if;

  if coalesce(trim(p_payload->>'student_name'),'')=''
    or coalesce(trim(p_payload->>'course'),'')=''
    or v_acquisition_date is null then
    raise exception 'REQUIRED_FIELDS';
  end if;

  if nullif(trim(p_payload->>'student_email'),'') is not null
    and position('@' in trim(p_payload->>'student_email'))=0 then
    raise exception 'INVALID_STUDENT_EMAIL';
  end if;

  v_number:=public.generate_certificate_number();

  insert into public.certificates(
    institution_id,cert_number,student_name,student_name_en,student_national_id,
    student_phone,student_email,course,specialization,issue_date,acquisition_date,
    expiry_date,grade,grade_value,duration,governorate,pdf_url,qr_code,
    visible_to_companies,consent_given_at,status,added_by
  )
  values(
    v_inst,v_number,trim(p_payload->>'student_name'),
    nullif(trim(p_payload->>'student_name_en'),''),
    nullif(trim(p_payload->>'student_national_id'),''),
    nullif(trim(p_payload->>'student_phone'),''),
    nullif(lower(trim(p_payload->>'student_email')),''),
    trim(p_payload->>'course'),
    nullif(trim(p_payload->>'specialization'),''),
    current_date,v_acquisition_date,
    nullif(p_payload->>'expiry_date','')::date,
    nullif(trim(p_payload->>'grade'),''),
    nullif(p_payload->>'grade_value','')::numeric,
    nullif(trim(p_payload->>'duration'),''),
    nullif(trim(p_payload->>'governorate'),''),
    nullif(trim(p_payload->>'pdf_url'),''),
    nullif(trim(p_payload->>'qr_code'),''),
    coalesce((p_payload->>'visible_to_companies')::boolean,false),
    case when coalesce((p_payload->>'visible_to_companies')::boolean,false) then now() else null end,
    'active','institution'
  )
  returning id into v_id;

  update public.institutions
  set quota_used=quota_used+1,updated_at=now()
  where id=v_inst;

  update public.subscriptions
  set quota_used=quota_used+1,updated_at=now()
  where id=v_sub.id;

  insert into public.activity_log(actor_id,actor_type,action,target_type,target_id,details)
  values(
    v_uid,'institution','certificate_issued','certificate',v_id,
    jsonb_build_object('cert_number',v_number,'institution_id',v_inst)::text
  );

  return query select v_id,v_number;
end;
$function$;

revoke all on function public.issue_certificate(jsonb) from public, anon;
grant execute on function public.issue_certificate(jsonb) to authenticated;
