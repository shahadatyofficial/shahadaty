-- Keep package list prices and discounted annual prices distinct.
alter table public.packages
  alter column price_monthly type numeric(12,2) using price_monthly::numeric,
  alter column price_yearly type numeric(12,2) using price_yearly::numeric,
  add column if not exists price_yearly_regular numeric(12,2) not null default 0;

alter table public.subscriptions
  alter column amount type numeric(12,2) using amount::numeric;

update public.packages
set price_yearly_regular=case name
      when 'basic' then 3000
      when 'bronze' then 5000
      when 'silver' then 8000
      when 'gold' then 12000
      when 'enterprise' then 20000
      else coalesce(price_yearly,0)
    end,
    price_yearly=case name
      when 'basic' then 2000
      when 'bronze' then 4000
      when 'silver' then 6000
      when 'gold' then 9000
      when 'enterprise' then 15000
      else coalesce(price_yearly,0)
    end,
    price_monthly=case name
      when 'basic' then 250.00
      when 'bronze' then 416.67
      when 'silver' then 666.67
      when 'gold' then 1000.00
      when 'enterprise' then 1666.67
      else 0
    end,
    name_ar=case when name='enterprise' then 'ماسية' else name_ar end;

drop function if exists public.admin_save_package(uuid,text,text,integer,integer,integer,integer);
create function public.admin_save_package(
  p_package_id uuid,
  p_name text,
  p_name_ar text,
  p_price_yearly_regular numeric,
  p_price_yearly numeric,
  p_quota_limit integer,
  p_sort_order integer default 0
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_package public.packages%rowtype;
  v_monthly numeric(12,2);
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_name_ar),'')='' then
    raise exception 'PACKAGE_NAME_REQUIRED';
  end if;
  if p_price_yearly_regular is null or p_price_yearly is null
     or p_quota_limit is null or p_sort_order is null
     or p_price_yearly_regular<0 or p_price_yearly<0
     or p_price_yearly>p_price_yearly_regular
     or p_quota_limit<0 or p_sort_order<0 then
    raise exception 'INVALID_PACKAGE_VALUES';
  end if;
  v_monthly:=round(p_price_yearly_regular/12,2);
  if p_package_id is null then
    insert into public.packages(name,name_ar,price_monthly,price_yearly,price_yearly_regular,quota_limit,sort_order)
    values(trim(p_name),trim(p_name_ar),v_monthly,p_price_yearly,p_price_yearly_regular,p_quota_limit,p_sort_order)
    returning * into v_package;
  else
    update public.packages
    set name_ar=trim(p_name_ar),price_monthly=v_monthly,price_yearly=p_price_yearly,
        price_yearly_regular=p_price_yearly_regular,quota_limit=p_quota_limit,sort_order=p_sort_order
    where id=p_package_id returning * into v_package;
    if not found then raise exception 'PACKAGE_NOT_FOUND'; end if;
  end if;
  return jsonb_build_object('success',true,'package_id',v_package.id,'name',v_package.name,
    'name_ar',v_package.name_ar,'price_monthly',v_package.price_monthly,
    'price_yearly',v_package.price_yearly,'price_yearly_regular',v_package.price_yearly_regular,
    'quota_limit',v_package.quota_limit);
end;
$$;

revoke all on function public.admin_save_package(uuid,text,text,numeric,numeric,integer,integer) from public, anon;
grant execute on function public.admin_save_package(uuid,text,text,numeric,numeric,integer,integer) to authenticated;

create or replace function public.admin_approve_institution(
  p_institution_id uuid,
  p_billing_cycle text default 'monthly',
  p_payment_status text default 'unpaid'
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_i public.institutions%rowtype;
  v_p public.packages%rowtype;
  v_sub_id uuid;
  v_amount numeric(12,2);
  v_quota integer;
  v_starts timestamptz:=now();
  v_ends timestamptz;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_billing_cycle not in ('monthly','yearly') then raise exception 'INVALID_BILLING_CYCLE'; end if;
  if p_payment_status not in ('unpaid','pending','paid','failed','refunded') then raise exception 'INVALID_PAYMENT_STATUS'; end if;

  select * into v_i from public.institutions where id=p_institution_id for update;
  if not found then raise exception 'INSTITUTION_NOT_FOUND'; end if;
  select * into v_p from public.packages where id=v_i.package_id;
  if not found then raise exception 'PACKAGE_NOT_FOUND'; end if;

  if coalesce(nullif(trim(v_i.commercial_registration_number),''), nullif(trim(v_i.commercial_reg),'')) is null
     or coalesce(nullif(trim(v_i.tax_card_number),''), nullif(trim(v_i.tax_number),'')) is null then
    raise exception 'REQUIRED_LEGAL_DATA_MISSING';
  end if;

  v_amount:=case when p_billing_cycle='yearly' then coalesce(v_p.price_yearly,0) else coalesce(v_p.price_monthly,0) end;
  v_quota:=coalesce(v_p.quota_limit,v_i.quota_total,10);
  v_ends:=case when lower(coalesce(v_p.name,''))='trial' then v_starts+interval '14 days'
              when p_billing_cycle='yearly' then v_starts+interval '1 year'
              else v_starts+interval '1 month' end;

  update public.institutions
  set status='approved',approved_at=now(),approved_by=auth.uid(),rejection_reason=null,
      quota_total=greatest(quota_used,v_quota),updated_at=now()
  where id=v_i.id;

  select id into v_sub_id from public.subscriptions
  where institution_id=v_i.id and status='active'
  order by created_at desc limit 1;

  if v_sub_id is null then
    insert into public.subscriptions(
      institution_id,package_id,billing_cycle,status,starts_at,ends_at,
      quota_limit,quota_used,amount,currency,payment_status
    ) values(
      v_i.id,v_i.package_id,p_billing_cycle,'active',v_starts,v_ends,
      v_quota,0,v_amount,'EGP',p_payment_status
    ) returning id into v_sub_id;
  else
    update public.subscriptions set package_id=v_i.package_id,billing_cycle=p_billing_cycle,
      starts_at=v_starts,ends_at=v_ends,quota_limit=v_quota,amount=v_amount,
      payment_status=p_payment_status,updated_at=now()
    where id=v_sub_id;
  end if;

  return jsonb_build_object('success',true,'institution_id',v_i.id,'subscription_id',v_sub_id,
    'status','approved','quota_total',greatest(v_i.quota_used,v_quota));
end;
$$;

drop function if exists public.admin_list_subscriptions(text);
create function public.admin_list_subscriptions(p_status text default null)
returns table(
  id uuid,institution_id uuid,institution_name text,package_name text,billing_cycle text,
  amount numeric(12,2),currency text,payment_status text,status text,payment_reference text,
  created_at timestamptz,ends_at timestamptz
)
language plpgsql
security definer
set search_path=public
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
revoke all on function public.admin_list_subscriptions(text) from public, anon;
grant execute on function public.admin_list_subscriptions(text) to authenticated;
