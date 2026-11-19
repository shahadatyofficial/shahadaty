-- Company application review workflow.
-- A direct job application is an explicit request to be considered by that employer.
-- Return only application-safe identity and qualification fields; never expose contact details or private file paths.
create or replace function public.company_list_job_applications(p_limit integer default 100)
returns table (
  id uuid,
  job_id uuid,
  status text,
  created_at timestamptz,
  cover_message text,
  job_title text,
  applicant_name text,
  qualification_name text,
  specialization text,
  graduation_year integer,
  governorate text,
  center text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    ja.id,
    ja.job_id,
    ja.status,
    ja.created_at,
    ja.cover_message,
    j.title,
    ap.full_name,
    aq.qualification_name,
    aq.specialization,
    aq.graduation_year,
    ap.governorate,
    ap.center
  from public.job_applications ja
  join public.job_announcements j on j.id = ja.job_id
  join public.alumni_profiles ap on ap.id = ja.alumni_id
  left join lateral (
    select q.qualification_name, q.specialization, q.graduation_year
    from public.alumni_qualifications q
    where q.alumni_id = ap.id
    order by q.sort_order nulls last, q.created_at
    limit 1
  ) aq on true
  where (select auth.uid()) is not null
    and j.company_id = (select public.current_approved_company_id())
  order by ja.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 200));
$$;

revoke all on function public.company_list_job_applications(integer) from public, anon;
grant execute on function public.company_list_job_applications(integer) to authenticated;

-- Companies can change only the application status, and only for their own approved-company jobs.
revoke update on table public.job_applications from anon, authenticated;
grant update (status) on table public.job_applications to authenticated;

drop policy if exists "approved companies update applications to own jobs" on public.job_applications;
create policy "approved companies update applications to own jobs"
on public.job_applications
for update
to authenticated
using (
  status in ('submitted', 'reviewing', 'shortlisted')
  and exists (
    select 1
    from public.job_announcements j
    where j.id = job_applications.job_id
      and j.company_id = (select public.current_approved_company_id())
  )
)
with check (
  status in ('reviewing', 'shortlisted', 'rejected', 'hired')
  and exists (
    select 1
    from public.job_announcements j
    where j.id = job_applications.job_id
      and j.company_id = (select public.current_approved_company_id())
  )
);

create or replace function public.set_job_application_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

drop trigger if exists set_job_application_updated_at on public.job_applications;
create trigger set_job_application_updated_at
before update of status on public.job_applications
for each row
execute function public.set_job_application_updated_at();
