-- Automatically synchronize active certificate records with the alumni directory.
-- Public visibility requires explicit company-sharing consent and its timestamp.
create or replace function public.sync_certificate_to_alumni(p_certificate public.certificates)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile_id uuid;
  v_profile_number text;
  v_qualification text;
  v_is_public boolean;
begin
  if p_certificate.cert_number is null or nullif(trim(p_certificate.student_name), '') is null then
    return;
  end if;

  v_profile_number := 'CERT-' || p_certificate.cert_number;
  v_is_public := coalesce(p_certificate.status = 'active', false)
    and coalesce(p_certificate.visible_to_companies, false)
    and p_certificate.consent_given_at is not null;

  -- Reuse profiles imported by the previous migration to avoid duplicate people.
  select p.id
    into v_profile_id
  from public.alumni_profiles p
  where p.profile_number in (
    'LEGACY-CERT-' || p_certificate.cert_number,
    v_profile_number
  )
  order by case when p.profile_number = 'LEGACY-CERT-' || p_certificate.cert_number then 0 else 1 end
  limit 1;

  if v_profile_id is null then
    insert into public.alumni_profiles (
      profile_number, full_name, visibility_status
    )
    values (
      v_profile_number,
      p_certificate.student_name,
      case when v_is_public then 'public' else 'hidden' end
    )
    returning id into v_profile_id;
  else
    update public.alumni_profiles
    set full_name = p_certificate.student_name,
        visibility_status = case when v_is_public then 'public' else 'hidden' end,
        updated_at = now()
    where id = v_profile_id;
  end if;

  v_qualification := coalesce(
    nullif(trim(concat_ws(' ',
      nullif(trim(p_certificate.academic_degree), ''),
      nullif(trim(p_certificate.academic_faculty), '')
    )), ''),
    nullif(trim(p_certificate.course), ''),
    nullif(trim(p_certificate.specialization), ''),
    'مؤهل مسجل'
  );

  insert into public.alumni_qualifications (
    alumni_id, certificate_id, qualification_name, institution_name,
    faculty_name, specialization, graduation_year, grade
  )
  values (
    v_profile_id,
    p_certificate.id,
    v_qualification,
    nullif(trim(p_certificate.academic_university), ''),
    nullif(trim(p_certificate.academic_faculty), ''),
    nullif(trim(p_certificate.specialization), ''),
    p_certificate.graduation_year,
    nullif(trim(p_certificate.grade), '')
  )
  on conflict (alumni_id, certificate_id)
  do update set
    qualification_name = excluded.qualification_name,
    institution_name = excluded.institution_name,
    faculty_name = excluded.faculty_name,
    specialization = excluded.specialization,
    graduation_year = excluded.graduation_year,
    grade = excluded.grade;
end;
$$;

revoke all on function public.sync_certificate_to_alumni(public.certificates) from public, anon, authenticated;

create or replace function public.sync_certificate_to_alumni_trigger()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.sync_certificate_to_alumni(new);
  return new;
end;
$$;

revoke all on function public.sync_certificate_to_alumni_trigger() from public, anon, authenticated;

drop trigger if exists sync_certificate_to_alumni_after_write on public.certificates;
create trigger sync_certificate_to_alumni_after_write
after insert or update of
  cert_number, student_name, course, specialization, status,
  visible_to_companies, consent_given_at, academic_university,
  academic_faculty, academic_degree, graduation_year, grade
on public.certificates
for each row
execute function public.sync_certificate_to_alumni_trigger();

-- Backfill every existing certificate. Profiles without explicit sharing consent stay hidden.
do $$
declare
  r public.certificates%rowtype;
begin
  for r in select * from public.certificates loop
    perform public.sync_certificate_to_alumni(r);
  end loop;
end;
$$;
