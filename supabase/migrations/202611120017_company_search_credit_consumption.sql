-- Company search credits: one credit per search that returns at least one result.
-- Empty searches do not consume credits. Lock the company row to prevent concurrent overuse.
create or replace function public.search_alumni_for_company(
  p_query text default null,
  p_qualification text default null,
  p_specialization text default null,
  p_governorate text default null,
  p_graduation_year integer default null,
  p_skill text default null
)
returns table(
  alumni_id uuid,
  full_name text,
  qualification_name text,
  graduation_year integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_company_id uuid;
  v_credits integer;
  v_rows integer;
begin
  select c.id,coalesce(c.search_credits,0)
  into v_company_id,v_credits
  from public.companies c
  where c.auth_user_id=auth.uid()
    and c.status='approved'
  order by c.created_at desc
  limit 1
  for update;

  if v_company_id is null then
    raise exception 'APPROVED_COMPANY_REQUIRED';
  end if;

  if v_credits<=0 then
    raise exception 'SEARCH_CREDITS_EXHAUSTED';
  end if;

  return query
  select p.id,p.full_name,q.qualification_name,q.graduation_year
  from public.alumni_profiles p
  join public.alumni_qualifications q on q.alumni_id=p.id
  where p.visibility_status='public'
    and p.publication_consent is true
    and (nullif(trim(p_query),'') is null or p.full_name ilike '%'||trim(p_query)||'%')
    and (nullif(trim(p_qualification),'') is null or q.qualification_name ilike '%'||trim(p_qualification)||'%')
    and (nullif(trim(p_specialization),'') is null or coalesce(q.specialization,'') ilike '%'||trim(p_specialization)||'%')
    and (nullif(trim(p_governorate),'') is null or coalesce(p.governorate,'') ilike '%'||trim(p_governorate)||'%')
    and (p_graduation_year is null or q.graduation_year=p_graduation_year)
    and (
      nullif(trim(p_skill),'') is null
      or exists(
        select 1 from public.alumni_skills sk
        where sk.alumni_id=p.id
          and sk.skill_name ilike '%'||trim(p_skill)||'%'
      )
    )
  order by p.full_name,q.graduation_year desc nulls last
  limit 100;

  get diagnostics v_rows = row_count;

  if v_rows>0 then
    update public.companies
    set search_credits=greatest(coalesce(search_credits,0)-1,0)
    where id=v_company_id;
  end if;
end;
$function$;

create or replace function public.company_get_search_credits()
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_credits integer;
begin
  select coalesce(c.search_credits,0) into v_credits
  from public.companies c
  where c.id=public.current_approved_company_id();

  if not found then
    raise exception 'APPROVED_COMPANY_REQUIRED';
  end if;

  return v_credits;
end;
$function$;

revoke all on function public.search_alumni_for_company(text,text,text,text,integer,text) from public, anon;
grant execute on function public.search_alumni_for_company(text,text,text,text,integer,text) to authenticated;
revoke all on function public.company_get_search_credits() from public, anon;
grant execute on function public.company_get_search_credits() to authenticated;
