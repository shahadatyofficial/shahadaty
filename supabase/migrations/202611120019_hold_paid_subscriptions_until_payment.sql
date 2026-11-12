-- Paid plans must remain pending until payment is explicitly confirmed.
-- The free trial remains active immediately after approval.
create or replace function public.admin_approve_institution(
  p_institution_id uuid,
  p_billing_cycle text default 'monthly',
  p_payment_status text default 'unpaid'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_i public.institutions%rowtype;
  v_p public.packages%rowtype;
  v_sub_id uuid;
  v_amount numeric(12,2);
  v_quota integer;
  v_starts timestamptz;
  v_ends timestamptz;
  v_is_trial boolean;
  v_subscription_status text;
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;

  if p_billing_cycle not in ('monthly','yearly') then
    raise exception 'INVALID_BILLING_CYCLE';
  end if;

  if p_payment_status not in ('unpaid','pending','paid','failed','refunded') then
    raise exception 'INVALID_PAYMENT_STATUS';
  end if;

  select * into v_i
  from public.institutions
  where id=p_institution_id
  for update;

  if not found then
    raise exception 'INSTITUTION_NOT_FOUND';
  end if;

  select * into v_p
  from public.packages
  where id=v_i.package_id;

  if not found then
    raise exception 'PACKAGE_NOT_FOUND';
  end if;

  if coalesce(nullif(trim(v_i.commercial_registration_number),''),nullif(trim(v_i.commercial_reg),'')) is null
     or coalesce(nullif(trim(v_i.tax_card_number),''),nullif(trim(v_i.tax_number),'')) is null then
    raise exception 'REQUIRED_LEGAL_DATA_MISSING';
  end if;

  v_amount := case
    when p_billing_cycle='yearly' then coalesce(v_p.price_yearly,0)
    else coalesce(v_p.price_monthly,0)
  end;
  v_quota := coalesce(v_p.quota_limit,v_i.quota_total,10);
  v_is_trial := lower(coalesce(v_p.name,''))='trial';

  if v_is_trial or p_payment_status='paid' then
    v_subscription_status := 'active';
    v_starts := now();
    v_ends := case
      when v_is_trial then now()+interval '14 days'
      when p_billing_cycle='yearly' then now()+interval '1 year'
      else now()+interval '1 month'
    end;
  else
    v_subscription_status := 'pending';
    v_starts := null;
    v_ends := null;
  end if;

  update public.institutions
  set status='approved',
      approved_at=now(),
      approved_by=auth.uid(),
      rejection_reason=null,
      quota_total=greatest(quota_used,v_quota),
      updated_at=now()
  where id=v_i.id;

  select id into v_sub_id
  from public.subscriptions
  where institution_id=v_i.id
    and status in ('active','pending','suspended')
  order by created_at desc
  limit 1
  for update;

  if v_sub_id is null then
    insert into public.subscriptions(
      institution_id,package_id,billing_cycle,status,starts_at,ends_at,
      quota_limit,quota_used,amount,currency,payment_status
    )
    values(
      v_i.id,v_i.package_id,p_billing_cycle,v_subscription_status,v_starts,v_ends,
      v_quota,0,v_amount,'EGP',p_payment_status
    )
    returning id into v_sub_id;
  else
    update public.subscriptions
    set package_id=v_i.package_id,
        billing_cycle=p_billing_cycle,
        status=v_subscription_status,
        starts_at=v_starts,
        ends_at=v_ends,
        quota_limit=v_quota,
        amount=v_amount,
        payment_status=p_payment_status,
        payment_reference=null,
        updated_at=now()
    where id=v_sub_id;
  end if;

  return jsonb_build_object(
    'success',true,
    'institution_id',v_i.id,
    'subscription_id',v_sub_id,
    'status','approved',
    'subscription_status',v_subscription_status,
    'payment_status',p_payment_status,
    'amount',v_amount,
    'quota_total',greatest(v_i.quota_used,v_quota)
  );
end;
$function$;
