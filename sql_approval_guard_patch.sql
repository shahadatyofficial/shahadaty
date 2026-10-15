-- Applied to the connected Supabase project on 2026-10-14.
-- Approval must not succeed until both required legal documents are approved.

create or replace function public.admin_approve_institution(
  p_institution_id uuid,
  p_billing_cycle text default 'monthly',
  p_payment_status text default 'unpaid'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $fn$
declare
  v_i public.institutions%rowtype;
  v_p public.packages%rowtype;
  v_sub_id uuid;
  v_amount integer;
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

  if not exists(
    select 1 from public.institution_documents d
    where d.institution_id=v_i.id
      and d.document_type='commercial_registration'
      and d.status='approved'
  ) or not exists(
    select 1 from public.institution_documents d
    where d.institution_id=v_i.id
      and d.document_type='tax_card'
      and d.status='approved'
  ) then
    raise exception 'REQUIRED_DOCUMENTS_NOT_APPROVED';
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
$fn$;

revoke execute on function public.admin_approve_institution(uuid,text,text) from public, anon;
grant execute on function public.admin_approve_institution(uuid,text,text) to authenticated;
notify pgrst, 'reload schema';
