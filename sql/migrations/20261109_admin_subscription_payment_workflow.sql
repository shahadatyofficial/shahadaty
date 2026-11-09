-- Admin subscription payment workflow.
-- Applied to Supabase production on 2026-11-09 after explicit deployment authorization.
create or replace function public.admin_list_subscriptions(p_status text default null)
returns table(
  id uuid,institution_id uuid,institution_name text,package_name text,
  billing_cycle text,amount integer,currency text,payment_status text,
  status text,payment_reference text,created_at timestamptz,ends_at timestamptz
)
language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  return query
  select s.id,s.institution_id,i.name,p.name_ar,s.billing_cycle,s.amount,s.currency,
         s.payment_status,s.status,s.payment_reference,s.created_at,s.ends_at
  from public.subscriptions s
  join public.institutions i on i.id=s.institution_id
  left join public.packages p on p.id=s.package_id
  where coalesce(nullif(trim(p_status),''),'')='' or s.status=trim(p_status)
  order by s.created_at desc limit 500;
end;
$$;

create or replace function public.admin_confirm_subscription_payment(
  p_subscription_id uuid,p_payment_reference text
)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_sub public.subscriptions%rowtype; v_end timestamptz;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if coalesce(trim(p_payment_reference),'')='' then raise exception 'PAYMENT_REFERENCE_REQUIRED'; end if;
  select * into v_sub from public.subscriptions where id=p_subscription_id for update;
  if not found then raise exception 'SUBSCRIPTION_NOT_FOUND'; end if;
  if v_sub.status not in ('pending','suspended','active') then raise exception 'SUBSCRIPTION_NOT_PENDING'; end if;
  if not exists(select 1 from public.institutions where id=v_sub.institution_id and status='approved') then
    raise exception 'INSTITUTION_NOT_APPROVED';
  end if;
  v_end:=case when v_sub.billing_cycle='yearly' then now()+interval '1 year' else now()+interval '1 month' end;
  update public.subscriptions set payment_status='paid',payment_reference=trim(p_payment_reference),
    status='active',starts_at=coalesce(starts_at,now()),ends_at=v_end,updated_at=now()
  where id=p_subscription_id;
  return jsonb_build_object('success',true,'subscription_id',p_subscription_id,'status','active','ends_at',v_end);
end;
$$;

revoke all on function public.admin_list_subscriptions(text) from public,anon;
revoke all on function public.admin_confirm_subscription_payment(uuid,text) from public,anon;
grant execute on function public.admin_list_subscriptions(text) to authenticated;
grant execute on function public.admin_confirm_subscription_payment(uuid,text) to authenticated;
