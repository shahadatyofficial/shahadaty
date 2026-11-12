-- Public alumni directory visibility follows the student's explicit publication declaration.
-- Existing records without explicit consent remain hidden.

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
  v_visibility_status text;
begin
  v_profile_number := 'LEGACY-CERT-' || coalesce(nullif(trim(new.cert_number), ''), new.id::text);

  if new.record_type is distinct from 'academic'
     or new.status is distinct from 'active'
     or nullif(trim(new.student_name), '') is null then
    update public.alumni_profiles p
       set visibility_status = 'hidden',
           updated_at = now()
     where p.profile_number = v_profile_number
        or p.id in (
          select q.alumni_id
            from public.alumni_qualifications q
           where q.certificate_id = new.id
        );
    return new;
  end if;

  v_visibility_status := case
    when new.declaration_accepted is true then 'public'
    else 'hidden'
  end;

  select q.alumni_id into v_profile_id
    from public.alumni_qualifications q
   where q.certificate_id = new.id
   limit 1;

  if v_profile_id is null then
    insert into public.alumni_profiles (profile_number, full_name, visibility_status)
    values (v_profile_number, trim(new.student_name), v_visibility_status)
    on conflict (profile_number) do update
      set full_name = excluded.full_name,
          visibility_status = excluded.visibility_status,
          updated_at = now()
    returning id into v_profile_id;
  else
    update public.alumni_profiles
       set full_name = trim(new.student_name),
           visibility_status = v_visibility_status,
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
for each row
execute function public.sync_academic_certificate_to_alumni();

comment on function public.sync_academic_certificate_to_alumni() is
  'Synchronizes active academic certificate records into alumni profiles; public visibility is granted only when the student explicitly accepted the publication declaration.';

-- Reprocess every existing active academic record through the same trigger.
-- Explicitly consented records become public; all others remain hidden.
update public.certificates
   set declaration_accepted = declaration_accepted
 where record_type = 'academic'
   and status = 'active'
   and nullif(trim(student_name), '') is not null;
