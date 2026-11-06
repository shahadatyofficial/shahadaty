-- Development migration: package catalog management for platform admins.
-- Apply only after reviewing this migration in an isolated test database.
create or replace function public.admin_save_package(
  p_package_id uuid,
  p_name text,
  p_name_ar text,
  p_price_monthly integer,
  p_price_yearly integer,
  p_quota_limit integer,
  p_sort_order integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_package public.packages%rowtype;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_name_ar),'')='' then raise exception 'PACKAGE_NAME_REQUIRED'; end if;
  if p_price_monthly is null or p_price_yearly is null or p_quota_limit is null or p_sort_order is null
     or p_price_monthly<0 or p_price_yearly<0 or p_quota_limit<0 or p_sort_order<0 then
    raise exception 'INVALID_PACKAGE_VALUES';
  end if;
  if p_package_id is null then
    insert into public.packages(name,name_ar,price_monthly,price_yearly,quota_limit,sort_order)
    values(trim(p_name),trim(p_name_ar),p_price_monthly,p_price_yearly,p_quota_limit,p_sort_order)
    returning * into v_package;
  else
    update public.packages set name_ar=trim(p_name_ar),price_monthly=p_price_monthly,
      price_yearly=p_price_yearly,quota_limit=p_quota_limit,sort_order=p_sort_order
    where id=p_package_id returning * into v_package;
    if not found then raise exception 'PACKAGE_NOT_FOUND'; end if;
  end if;
  return jsonb_build_object('success',true,'package_id',v_package.id,'name',v_package.name,
    'name_ar',v_package.name_ar,'price_monthly',v_package.price_monthly,
    'price_yearly',v_package.price_yearly,'quota_limit',v_package.quota_limit);
end;
$$;

create or replace function public.admin_delete_package(p_package_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if exists(select 1 from public.institutions where package_id=p_package_id)
     or exists(select 1 from public.subscriptions where package_id=p_package_id) then
    raise exception 'PACKAGE_IN_USE';
  end if;
  delete from public.packages where id=p_package_id;
  if not found then raise exception 'PACKAGE_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'package_id',p_package_id);
end;
$$;

revoke all on function public.admin_save_package(uuid,text,text,integer,integer,integer,integer) from public, anon;
revoke all on function public.admin_delete_package(uuid) from public, anon;
grant execute on function public.admin_save_package(uuid,text,text,integer,integer,integer,integer) to authenticated;
grant execute on function public.admin_delete_package(uuid) to authenticated;
