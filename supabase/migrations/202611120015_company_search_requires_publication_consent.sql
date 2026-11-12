-- Company-facing discovery must honor the graduate's explicit public-publication consent.
create or replace function public.is_public_alumni_profile(p_alumni_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select public.current_approved_company_id() is not null
    and exists (
      select 1
      from public.alumni_profiles p
      where p.id = p_alumni_id
        and p.visibility_status = 'public'
        and p.publication_consent is true
    );
$function$;

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
begin
  if public.current_approved_company_id() is null then
    raise exception 'Approved company account required';
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
end;
$function$;

revoke all on function public.is_public_alumni_profile(uuid) from public, anon;
grant execute on function public.is_public_alumni_profile(uuid) to authenticated;
revoke all on function public.search_alumni_for_company(text,text,text,text,integer,text) from public, anon;
grant execute on function public.search_alumni_for_company(text,text,text,text,integer,text) to authenticated;
