-- Extend the public graduate directory to include consented training certificates.
-- Public search remains consent-gated: academic profiles require public visibility and
-- explicit profile consent; training certificates require explicit certificate consent.

create or replace function public.search_public_alumni(
  p_qualification text,
  p_university text default null,
  p_college text default null,
  p_graduation_year integer default null,
  p_grade text default null
)
returns table (
  full_name text,
  qualification_name text,
  institution_name text,
  faculty_name text,
  graduation_year integer,
  grade text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with search_input as (
    select regexp_replace(
      regexp_replace(
        translate(lower(trim(coalesce(p_qualification,''))), 'أإآٱىةـ', 'اااايه'),
        '^(ليسانس|بكالوريوس|بكالريوس|بكلوريوس|بكالوريس|دبلوم|ماجستير|دكتوراه)[[:space:]]+',
        ''
      ),
      '^[[:space:]]*ال', ''
    ) as search_key
  ),
  candidates as (
    -- Academic qualifications: only profiles with explicit publication consent.
    select
      p.full_name::text as full_name,
      q.qualification_name::text as qualification_name,
      q.institution_name::text as institution_name,
      q.faculty_name::text as faculty_name,
      q.graduation_year::integer as graduation_year,
      q.grade::text as grade,
      regexp_replace(
        regexp_replace(
          translate(lower(trim(coalesce(q.qualification_name,'') || ' ' || coalesce(p.full_name,''))), 'أإآٱىةـ', 'اااايه'),
          '^(ليسانس|بكالوريوس|بكالريوس|بكلوريوس|بكالوريس|دبلوم|ماجستير|دكتوراه)[[:space:]]+',
          ''
        ),
        '^[[:space:]]*ال', ''
      ) as searchable_text
    from public.alumni_profiles p
    join public.alumni_qualifications q on q.alumni_id = p.id
    where p.visibility_status = 'public'
      and p.publication_consent is true

    union all

    -- Training certificates: only active records with explicit graduate consent.
    select
      c.student_name::text as full_name,
      c.course::text as qualification_name,
      i.name::text as institution_name,
      c.specialization::text as faculty_name,
      extract(year from c.issue_date)::integer as graduation_year,
      c.grade::text as grade,
      translate(
        lower(trim(coalesce(c.course,'') || ' ' || coalesce(c.specialization,'') || ' ' ||
                   coalesce(c.student_name,'') || ' ' || coalesce(c.student_name_en,''))),
        'أإآٱىةـ', 'اااايه'
      ) as searchable_text
    from public.certificates c
    left join public.institutions i on i.id = c.institution_id
    where c.record_type = 'training'
      and c.status = 'active'
      and c.declaration_accepted is true
  )
  select
    c.full_name,
    c.qualification_name,
    c.institution_name,
    c.faculty_name,
    c.graduation_year,
    c.grade
  from candidates c
  cross join search_input s
  where s.search_key <> ''
    and c.searchable_text ilike '%' || s.search_key || '%'
    and (nullif(trim(p_university),'') is null or coalesce(c.institution_name,'') ilike '%' || trim(p_university) || '%')
    and (nullif(trim(p_college),'') is null or coalesce(c.faculty_name,'') ilike '%' || trim(p_college) || '%')
    and (p_graduation_year is null or c.graduation_year = p_graduation_year)
    and (nullif(trim(p_grade),'') is null or coalesce(c.grade,'') ilike '%' || trim(p_grade) || '%')
  order by c.full_name, c.graduation_year desc nulls last
  limit 100;
$$;

revoke all on function public.search_public_alumni(text,text,text,integer,text) from public;
grant execute on function public.search_public_alumni(text,text,text,integer,text) to anon, authenticated;
