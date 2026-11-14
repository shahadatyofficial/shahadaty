create or replace function public.company_can_access_alumni_document(p_storage_path text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select exists (
    select 1
    from public.alumni_documents d
    join public.alumni_profiles p on p.id = d.alumni_id
    join public.alumni_access_requests r on r.alumni_id = d.alumni_id
    where d.storage_path = p_storage_path
      and p.visibility_status = 'public'
      and p.publication_consent is true
      and r.company_id = public.current_approved_company_id()
      and r.status = 'approved'
      and r.alumni_consent_at is not null
      and (r.expires_at is null or r.expires_at > now())
      and (
        (d.document_type = 'cv' and r.request_cv = true and exists (
          select 1 from public.graduate_profiles gp
          join public.graduate_membership_requests m on m.auth_user_id = gp.auth_user_id
          where gp.id = p.legacy_graduate_profile_id
            and m.status = 'approved' and m.ends_at > now()
        ))
        or (d.document_type <> 'cv' and r.request_documents = true)
      )
  );
$function$;

create or replace function public.company_get_approved_alumni_contact(p_alumni_id uuid)
returns table(full_name text, phone text, email text, governorate text, professional_summary text)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select p.full_name, p.phone, p.email, p.governorate,
    case
      when p.legacy_graduate_profile_id is null or exists (
        select 1 from public.graduate_profiles gp
        join public.graduate_membership_requests m on m.auth_user_id = gp.auth_user_id
        where gp.id = p.legacy_graduate_profile_id
          and m.status = 'approved' and m.ends_at > now()
      ) then p.professional_summary
      else gp.bio
    end as professional_summary
  from public.alumni_profiles p
  left join public.graduate_profiles gp on gp.id = p.legacy_graduate_profile_id
  where p.id = p_alumni_id
    and p.visibility_status = 'public'
    and p.publication_consent is true
    and exists (
      select 1 from public.alumni_access_requests r
      where r.alumni_id = p.id
        and r.company_id = public.current_approved_company_id()
        and r.status = 'approved'
        and r.alumni_consent_at is not null
        and (r.expires_at is null or r.expires_at > now())
        and r.request_contact = true
    );
$function$;

create or replace function public.search_alumni_for_company(
 p_query text default null,
 p_qualification text default null,
 p_specialization text default null,
 p_governorate text default null,
 p_graduation_year integer default null,
 p_skill text default null,
 p_center text default null
)
returns table(alumni_id uuid, full_name text, qualification_name text, graduation_year integer, governorate text, center text)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare v_company_id uuid; v_credits integer; v_rows integer;
begin
 select c.id,coalesce(c.search_credits,0) into v_company_id,v_credits
 from public.companies c
 where c.auth_user_id=auth.uid() and c.status='approved'
 order by c.created_at desc limit 1 for update;
 if v_company_id is null then raise exception 'APPROVED_COMPANY_REQUIRED'; end if;
 if v_credits<=0 then raise exception 'SEARCH_CREDITS_EXHAUSTED'; end if;
 return query
 select p.id,p.full_name,q.qualification_name,q.graduation_year,p.governorate,p.center
 from public.alumni_profiles p
 join public.alumni_qualifications q on q.alumni_id=p.id
 where p.visibility_status='public' and p.publication_consent is true
 and (nullif(trim(p_query),'') is null or p.full_name ilike '%'||trim(p_query)||'%')
 and (nullif(trim(p_qualification),'') is null or q.qualification_name ilike '%'||trim(p_qualification)||'%')
 and (nullif(trim(p_specialization),'') is null or coalesce(q.specialization,'') ilike '%'||trim(p_specialization)||'%')
 and (nullif(trim(p_governorate),'') is null or coalesce(p.governorate,'') ilike '%'||trim(p_governorate)||'%')
 and (p_graduation_year is null or q.graduation_year=p_graduation_year)
 and (nullif(trim(p_skill),'') is null or exists(
   select 1 from public.alumni_skills sk
   where sk.alumni_id=p.id and sk.skill_name ilike '%'||trim(p_skill)||'%'
     and (
       sk.skill_category not in ('graduate_profile','graduate_language','graduate_target_role')
       or exists(
         select 1 from public.graduate_profiles gp
         join public.graduate_membership_requests m on m.auth_user_id=gp.auth_user_id
         where gp.id=p.legacy_graduate_profile_id
           and m.status='approved' and m.ends_at>now()
       )
     )
 ))
 and (nullif(trim(p_center),'') is null or coalesce(p.center,'') ilike '%'||trim(p_center)||'%')
 order by p.full_name,q.graduation_year desc nulls last limit 100;
 get diagnostics v_rows=row_count;
 if v_rows>0 then update public.companies set search_credits=greatest(coalesce(search_credits,0)-1,0) where id=v_company_id; end if;
end;
$function$;