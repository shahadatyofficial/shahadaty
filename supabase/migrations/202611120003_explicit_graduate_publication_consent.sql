-- Explicit graduate publication consent is required for public alumni search.
alter table public.alumni_profiles
  add column if not exists publication_consent boolean not null default false,
  add column if not exists publication_consent_at timestamptz;

alter table public.graduate_profiles
  add column if not exists publication_consent boolean not null default false,
  add column if not exists publication_consent_at timestamptz;

create or replace function public.enforce_alumni_publication_consent()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.publication_consent is true then
    new.publication_consent_at := coalesce(new.publication_consent_at, now());
  else
    new.publication_consent_at := null;
    new.visibility_status := 'hidden';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_alumni_publication_consent on public.alumni_profiles;
create trigger trg_enforce_alumni_publication_consent
before insert or update of publication_consent, visibility_status
on public.alumni_profiles
for each row execute function public.enforce_alumni_publication_consent();

create or replace function public.sync_graduate_publication_consent()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.alumni_profiles ap
     set publication_consent = coalesce(new.publication_consent, false),
         publication_consent_at = case when new.publication_consent is true
           then coalesce(new.publication_consent_at, now()) else null end,
         visibility_status = case when new.publication_consent is true
           then 'public' else 'hidden' end,
         updated_at = now()
   where ap.legacy_graduate_profile_id = new.id;
  return new;
end;
$$;

revoke all on function public.sync_graduate_publication_consent() from public, anon, authenticated;

drop trigger if exists trg_sync_graduate_publication_consent on public.graduate_profiles;
create trigger trg_sync_graduate_publication_consent
after insert or update of publication_consent, publication_consent_at
on public.graduate_profiles
for each row execute function public.sync_graduate_publication_consent();

create or replace function public.sync_academic_certificate_to_alumni()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile_id uuid;
  v_profile_number text;
  v_qualification_name text;
  v_consent boolean;
begin
  v_profile_number := 'LEGACY-CERT-' || coalesce(nullif(trim(new.cert_number), ''), new.id::text);

  if new.record_type is distinct from 'academic'
     or new.status is distinct from 'active'
     or nullif(trim(new.student_name), '') is null then
    update public.alumni_profiles p
       set visibility_status = 'hidden',
           publication_consent = false,
           updated_at = now()
     where p.profile_number = v_profile_number
        or p.id in (
          select q.alumni_id from public.alumni_qualifications q where q.certificate_id = new.id
        );
    return new;
  end if;

  v_consent := coalesce(new.declaration_accepted, false);

  select q.alumni_id into v_profile_id
    from public.alumni_qualifications q
   where q.certificate_id = new.id
   limit 1;

  if v_profile_id is null then
    insert into public.alumni_profiles (
      profile_number, full_name, visibility_status, publication_consent, publication_consent_at
    )
    values (
      v_profile_number, trim(new.student_name),
      case when v_consent then 'public' else 'hidden' end,
      v_consent,
      case when v_consent then coalesce(new.declaration_accepted_at, now()) else null end
    )
    on conflict (profile_number) do update
      set full_name = excluded.full_name,
          visibility_status = excluded.visibility_status,
          publication_consent = excluded.publication_consent,
          publication_consent_at = excluded.publication_consent_at,
          updated_at = now()
    returning id into v_profile_id;
  else
    update public.alumni_profiles
       set full_name = trim(new.student_name),
           visibility_status = case when v_consent then 'public' else 'hidden' end,
           publication_consent = v_consent,
           publication_consent_at = case when v_consent
             then coalesce(new.declaration_accepted_at, now()) else null end,
           updated_at = now()
     where id = v_profile_id;
  end if;

  v_qualification_name := coalesce(
    nullif(trim(concat_ws(' ',
      nullif(trim(new.academic_degree), ''),
      nullif(trim(new.academic_faculty), '')
    )), ''),
    nullif(trim(new.specialization), ''),
    nullif(trim(new.course), ''),
    'مؤهل علمي'
  );

  insert into public.alumni_qualifications (
    alumni_id, certificate_id, qualification_name, institution_name,
    faculty_name, specialization, graduation_year, grade
  )
  values (
    v_profile_id, new.id, v_qualification_name,
    nullif(trim(new.academic_university), ''),
    nullif(trim(new.academic_faculty), ''),
    nullif(trim(new.specialization), ''),
    new.graduation_year,
    nullif(trim(new.grade), '')
  )
  on conflict (alumni_id, certificate_id) do update
    set qualification_name = excluded.qualification_name,
        institution_name = excluded.institution_name,
        faculty_name = excluded.faculty_name,
        specialization = excluded.specialization,
        graduation_year = excluded.graduation_year,
        grade = excluded.grade;

  return new;
end;
$$;

revoke all on function public.sync_academic_certificate_to_alumni() from public, anon, authenticated;

drop trigger if exists trg_sync_academic_certificate_to_alumni on public.certificates;
create trigger trg_sync_academic_certificate_to_alumni
after insert or update of
  cert_number, student_name, record_type, status, academic_degree,
  academic_faculty, academic_university, course, specialization,
  graduation_year, grade, declaration_accepted, declaration_accepted_at
on public.certificates
for each row execute function public.sync_academic_certificate_to_alumni();

-- Backfill only explicit certificate consents; do not infer consent from prior visibility flags.
update public.alumni_profiles ap
   set publication_consent = true,
       publication_consent_at = coalesce(c.declaration_accepted_at, now()),
       visibility_status = 'public',
       updated_at = now()
  from public.alumni_qualifications q
  join public.certificates c on c.id = q.certificate_id
 where q.alumni_id = ap.id
   and c.record_type = 'academic'
   and c.status = 'active'
   and c.declaration_accepted is true;

update public.alumni_profiles ap
   set publication_consent = false,
       publication_consent_at = null,
       visibility_status = 'hidden',
       updated_at = now()
 where not exists (
   select 1
     from public.alumni_qualifications q
     join public.certificates c on c.id = q.certificate_id
    where q.alumni_id = ap.id
      and c.record_type = 'academic'
      and c.status = 'active'
      and c.declaration_accepted is true
 )
 and ap.legacy_graduate_profile_id is null;
