-- Safe public company onboarding through a narrow SECURITY DEFINER RPC.
-- Direct browser-role INSERT remains revoked; requests are always pending with zero credits.
drop policy if exists companies_public_insert on public.companies;

create unique index if not exists companies_contact_email_unique_idx
on public.companies (lower(contact_email))
where contact_email is not null;

create or replace function public.submit_company_registration(
  p_company_name text,
  p_contact_name text,
  p_contact_email text,
  p_contact_phone text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
  v_email text := lower(btrim(coalesce(p_contact_email, '')));
  v_user_id uuid := auth.uid();
begin
  if p_company_name is null or length(btrim(p_company_name)) not between 2 and 200 then
    raise exception 'INVALID_COMPANY_NAME';
  end if;
  if p_contact_name is null or length(btrim(p_contact_name)) not between 2 and 100 then
    raise exception 'INVALID_CONTACT_NAME';
  end if;
  if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(v_email) > 254 then
    raise exception 'INVALID_CONTACT_EMAIL';
  end if;
  if p_contact_phone is null or length(btrim(p_contact_phone)) not between 7 and 32 then
    raise exception 'INVALID_CONTACT_PHONE';
  end if;
  if exists (
    select 1 from public.companies c
    where lower(c.contact_email) = v_email
      and c.status in ('pending', 'approved')
  ) then
    raise exception 'COMPANY_EMAIL_ALREADY_REGISTERED';
  end if;

  insert into public.companies (
    company_name, contact_name, contact_email, contact_phone,
    status, search_credits, auth_user_id
  )
  values (
    btrim(p_company_name), btrim(p_contact_name), v_email, btrim(p_contact_phone),
    'pending', 0, v_user_id
  )
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function public.submit_company_registration(text,text,text,text) from public;
grant execute on function public.submit_company_registration(text,text,text,text) to anon, authenticated;
