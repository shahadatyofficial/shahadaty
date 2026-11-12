-- Automatically create hidden alumni directory records for academic certificates.
-- Public search continues to expose only profiles explicitly switched to visibility_status='public'.

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
begin
  v_profile_number := 'LEGACY-CERT-' || coalesce(nullif(trim(new.cert_number), ''), new.id::text);

  if new.record_type is distinct from 'academic'
     or new.status is distinct from 'active'
     or nullif(trim(new.student_name), '') is null then
    update public.alumni_profiles
       set visibility_status = 'hidden',
           updated_at = now()
     where profile_number = v_profile_number;
    return new;
  end if;

  select q.alumni_id into v_profile_id
    from public.alumni_qualifications q
   where q.certificate_id = new.id
   limit 1;

  if v_profile_id is null then
    insert into public.alumni_profiles (profile_number, full_name, visibility_status)
    values (v_profile_number, trim(new.student_name), 'hidden')
    on conflict (profile_number) do update
      set full_name = excluded.full_name,
          updated_at = now()
    returning id into v_profile_id;
  else
    update public.alumni_profiles
       set full_name = trim(new.student_name),
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
  graduation_year, grade
on public.certificates
for each row
execute function public.sync_academic_certificate_to_alumni();

comment on function public.sync_academic_certificate_to_alumni() is
  'Synchronizes active academic certificate records into hidden alumni directory profiles; public visibility remains an explicit admin action.';
