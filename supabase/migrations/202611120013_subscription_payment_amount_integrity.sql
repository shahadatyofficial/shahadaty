-- Prevent administrators from confirming payment against a stale or incorrect subscription amount.
-- Existing subscription amounts are intentionally not rewritten; the admin UI flags mismatches for review.
create or replace function public.admin_confirm_subscription_payment(
  p_subscription_id uuid,
  p_payment_reference text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_sub public.subscriptions%rowtype;
  v_package public.packages%rowtype;
  v_expected_amount numeric(12,2);
  v_end timestamptz;
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;

  if coalesce(trim(p_payment_reference),'')='' then
    raise exception 'PAYMENT_REFERENCE_REQUIRED';
  end if;

  select * into v_sub
  from public.subscriptions
  where id=p_subscription_id
  for update;

  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND';
  end if;

  if v_sub.status not in ('pending','suspended','active') then
    raise exception 'SUBSCRIPTION_NOT_PENDING';
  end if;

  if not exists(
    select 1 from public.institutions
    where id=v_sub.institution_id and status='approved'
  ) then
    raise exception 'INSTITUTION_NOT_APPROVED';
  end if;

  select * into v_package
  from public.packages
  where id=v_sub.package_id;

  if not found then
    raise exception 'PACKAGE_NOT_FOUND';
  end if;

  if v_sub.billing_cycle not in ('monthly','yearly') then
    raise exception 'INVALID_BILLING_CYCLE';
  end if;

  v_expected_amount:=case
    when v_sub.billing_cycle='yearly' then coalesce(v_package.price_yearly,0)
    else coalesce(v_package.price_monthly,0)
  end;

  if abs(coalesce(v_sub.amount,0)-v_expected_amount)>0.009 then
    raise exception 'SUBSCRIPTION_AMOUNT_MISMATCH';
  end if;

  v_end:=case
    when v_sub.billing_cycle='yearly' then now()+interval '1 year'
    else now()+interval '1 month'
  end;

  update public.subscriptions
  set payment_status='paid',
      payment_reference=trim(p_payment_reference),
      status='active',
      starts_at=coalesce(starts_at,now()),
      ends_at=v_end,
      updated_at=now()
  where id=p_subscription_id;

  return jsonb_build_object(
    'success',true,
    'subscription_id',p_subscription_id,
    'status','active',
    'ends_at',v_end
  );
end;
$function$;

revoke all on function public.admin_confirm_subscription_payment(uuid,text) from public, anon;
grant execute on function public.admin_confirm_subscription_payment(uuid,text) to authenticated;
