-- Public alumni search filters, normalized qualification matching and academic result metadata.
alter table public.alumni_qualifications
  add column if not exists grade text;

-- Backfill academic details already stored on linked certificate records.
update public.alumni_qualifications q
set institution_name = coalesce(nullif(trim(q.institution_name),''), nullif(trim(c.university),'')),
    faculty_name = coalesce(nullif(trim(q.faculty_name),''), nullif(trim(c.faculty),'')),
    grade = coalesce(nullif(trim(q.grade),''), nullif(trim(c.grade),''))
from public.certificates c
where q.certificate_id = c.id
  and (q.institution_name is null or q.faculty_name is null or q.grade is null);

drop function if exists public.search_public_alumni(text,text);

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
    select
      regexp_replace(
        regexp_replace(
          translate(lower(trim(coalesce(p_qualification,''))), 'أإآٱىةـ', 'ااايه'),
          '^(ليسانس|بكالوريوس|بكالريوس|بكلوريوس|بكالوريوس|بكالوريس|دبلوم|ماجستير|دكتوراه)[[:space:]]+',
          ''
        ),
        '^[[:space:]]*ال', ''
      ) as qualification_key
  ),
  candidates as (
    select
      p.full_name,
      q.qualification_name,
      q.institution_name,
      q.faculty_name,
      q.graduation_year,
      q.grade,
      regexp_replace(
        regexp_replace(
          translate(lower(trim(q.qualification_name)), 'أإآٱىةـ', 'ااايه'),
          '^(ليسانس|بكالوريوس|بكالريوس|بكلوريوس|بكالوريس|دبلوم|ماجستير|دكتوراه)[[:space:]]+',
          ''
        ),
        '^[[:space:]]*ال', ''
      ) as qualification_key
    from public.alumni_profiles p
    join public.alumni_qualifications q on q.alumni_id = p.id
    where p.visibility_status = 'public'
  )
  select c.full_name, c.qualification_name, c.institution_name, c.faculty_name, c.graduation_year, c.grade
  from candidates c
  cross join search_input s
  where s.qualification_key <> ''
    and c.qualification_key ilike '%' || s.qualification_key || '%'
    and (nullif(trim(p_university),'') is null or coalesce(c.institution_name,'') ilike '%' || trim(p_university) || '%')
    and (nullif(trim(p_college),'') is null or coalesce(c.faculty_name,'') ilike '%' || trim(p_college) || '%')
    and (p_graduation_year is null or c.graduation_year = p_graduation_year)
    and (nullif(trim(p_grade),'') is null or coalesce(c.grade,'') ilike '%' || trim(p_grade) || '%')
  order by c.full_name, c.graduation_year desc nulls last
  limit 100;
$$;

revoke all on function public.search_public_alumni(text,text,text,integer,text) from public;
grant execute on function public.search_public_alumni(text,text,text,integer,text) to anon, authenticated;
