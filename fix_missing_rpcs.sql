-- Shahadaty: repair the two RPCs used by the public homepage and graduate dashboard.
-- Safe to run independently in Supabase SQL Editor.

drop function if exists public.public_platform_stats();

create or replace function public.public_platform_stats()
returns table(institutions_count bigint, certificates_count bigint, verifications_count bigint)
language sql
stable
security definer
set search_path=public
as $fn$
  select
    (select count(*) from public.institutions i where i.status='approved'),
    (select count(*) from public.certificates c
       join public.institutions i on i.id=c.institution_id
       where i.status='approved' and c.status='active'),
    (select count(*) from public.certificate_verifications);
$fn$;

revoke all on function public.public_platform_stats() from public;
grant execute on function public.public_platform_stats() to anon, authenticated;

drop function if exists public.graduate_my_certificates();

create or replace function public.graduate_my_certificates()
returns table(cert_number text, course text, issue_date date, grade text)
language plpgsql
stable
security definer
set search_path=public
as $fn$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  return query
  select c.cert_number, c.course, c.issue_date, c.grade
  from public.graduate_profiles gp
  join public.certificates c
    on regexp_replace(coalesce(gp.phone,''), '[^0-9]', '', 'g')
     = regexp_replace(coalesce(c.student_phone,''), '[^0-9]', '', 'g')
  join public.institutions i on i.id=c.institution_id
  where gp.auth_user_id=auth.uid()
    and nullif(regexp_replace(coalesce(gp.phone,''), '[^0-9]', '', 'g'),'') is not null
    and i.status='approved'
    and c.status='active'
  order by c.issue_date desc, c.created_at desc;
end;
$fn$;

revoke all on function public.graduate_my_certificates() from public;
grant execute on function public.graduate_my_certificates() to authenticated;
