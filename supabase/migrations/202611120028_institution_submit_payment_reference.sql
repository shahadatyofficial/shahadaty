-- Allow an institution owner/manager to submit a payment reference for admin review.
create or replace function public.institution_submit_subscription_payment_reference(
  p_subscription_id uuid,
  p_payment_reference text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_sub public.subscriptions%rowtype;
  v_reference text;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  v_reference := nullif(trim(p_payment_reference), '');
  if v_reference is null then
    raise exception 'PAYMENT_REFERENCE_REQUIRED';
  end if;
  if length(v_reference) > 200 then
    raise exception 'PAYMENT_REFERENCE_TOO_LONG';
  end if;

  select s.* into v_sub
  from public.subscriptions s
  where s.id = p_subscription_id
  for update;

  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from public.institutions i
    where i.id = v_sub.institution_id
      and i.status = 'approved'
      and (
        i.auth_user_id = v_uid
        or exists (
          select 1
          from public.institution_users iu
          where iu.institution_id = i.id
            and iu.auth_user_id = v_uid
            and iu.status = 'active'
            and iu.role in ('owner', 'manager')
        )
      )
  ) then
    raise exception 'NOT_ALLOWED';
  end if;

  if v_sub.status not in ('pending', 'suspended', 'active') then
    raise exception 'SUBSCRIPTION_NOT_SUBMITTABLE';
  end if;
  if v_sub.payment_status = 'paid' then
    raise exception 'PAYMENT_ALREADY_CONFIRMED';
  end if;
  if v_sub.payment_status not in ('unpaid', 'pending', 'failed') then
    raise exception 'PAYMENT_STATUS_NOT_SUBMITTABLE';
  end if;
  if coalesce(v_sub.amount, 0) <= 0 then
    raise exception 'PAYMENT_NOT_REQUIRED';
  end if;

  if exists (
    select 1
    from public.subscriptions other_sub
    where other_sub.id <> p_subscription_id
      and lower(trim(coalesce(other_sub.payment_reference, ''))) = lower(v_reference)
  ) then
    raise exception 'PAYMENT_REFERENCE_ALREADY_USED';
  end if;

  update public.subscriptions
  set payment_reference = v_reference,
      payment_status = 'pending',
      updated_at = now()
  where id = p_subscription_id;

  insert into public.activity_log (
    institution_id, action, details, actor_id, actor_type, target_type, target_id
  ) values (
    v_sub.institution_id,
    'subscription_payment_reference_submitted',
    'تم إرسال مرجع الدفع للمراجعة الإدارية',
    v_uid,
    'institution',
    'subscription',
    p_subscription_id
  );

  return jsonb_build_object(
    'success', true,
    'subscription_id', p_subscription_id,
    'payment_status', 'pending'
  );
end;
$function$;

revoke all on function public.institution_submit_subscription_payment_reference(uuid, text) from public;
revoke all on function public.institution_submit_subscription_payment_reference(uuid, text) from anon;
grant execute on function public.institution_submit_subscription_payment_reference(uuid, text) to authenticated;
