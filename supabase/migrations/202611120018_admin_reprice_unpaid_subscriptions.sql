-- Allow a platform administrator to reprice an unpaid subscription explicitly.
-- This does not mark the subscription paid or activate certificate issuance.
create or replace function public.admin_reprice_subscription(p_subscription_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_sub public.subscriptions%rowtype;
  v_package public.packages%rowtype;
  v_expected_amount numeric(12,2);
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;

  select * into v_sub
  from public.subscriptions
  where id=p_subscription_id
  for update;

  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND';
  end if;

  if v_sub.payment_status='paid' then
    raise exception 'PAID_SUBSCRIPTION_CANNOT_BE_REPRICED';
  end if;

  if v_sub.status in ('cancelled','expired') then
    raise exception 'CLOSED_SUBSCRIPTION_CANNOT_BE_REPRICED';
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

  update public.subscriptions
  set amount=v_expected_amount,
      payment_status='unpaid',
      updated_at=now()
  where id=p_subscription_id;

  return jsonb_build_object(
    'success',true,
    'subscription_id',p_subscription_id,
    'amount',v_expected_amount,
    'billing_cycle',v_sub.billing_cycle,
    'payment_status','unpaid'
  );
end;
$function$;

revoke all on function public.admin_reprice_subscription(uuid) from public, anon;
grant execute on function public.admin_reprice_subscription(uuid) to authenticated;
