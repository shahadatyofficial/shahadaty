-- Link every active institutional/academic certificate to one hidden graduate record.
-- Existing graduate login approval and explicit publication consent remain unchanged.

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
  v_phone text;
  v_profile_matches integer := 0;
  v_graduate_id uuid;
  v_graduate_matches integer := 0;
begin
  if new.status is distinct from 'active'
     or nullif(trim(new.student_name), '') is null then
    return new;
  end if;

  v_phone := nullif(regexp_replace(coalesce(new.student_phone, ''), '[^0-9]', '', 'g'), '');
  v_profile_number := 'CERT-' || coalesce(nullif(trim(new.cert_number), ''), new.id::text);

  -- Prefer an already-linked record for this exact certificate.
  select q.alumni_id into v_profile_id
    from public.alumni_qualifications q
   where q.certificate_id = new.id
   limit 1;

  -- Reuse a graduate profile only when the normalized phone identifies exactly one record.
  if v_profile_id is null and v_phone is not null then
    select count(*), min(p.id)
      into v_profile_matches, v_profile_id
      from public.alumni_profiles p
     where nullif(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), '') = v_phone;
    if v_profile_matches <> 1 then
      v_profile_id := null;
    end if;
  end if;

  if v_profile_id is null then
    insert into public.alumni_profiles (
      profile_number, full_name, phone, email, center,
      visibility_status, publication_consent, contact_sharing_requires_approval
    )
    values (
      v_profile_number, trim(new.student_name), nullif(trim(new.student_phone), ''),
      nullif(lower(trim(new.student_email)), ''), nullif(trim(new.center), ''),
      'hidden', false, true
    )
    on conflict (profile_number) do update
      set full_name = excluded.full_name,
          phone = coalesce(public.alumni_profiles.phone, excluded.phone),
          email = coalesce(public.alumni_profiles.email, excluded.email),
          center = coalesce(public.alumni_profiles.center, excluded.center),
          updated_at = now()
    returning id into v_profile_id;
  else
    update public.alumni_profiles
       set full_name = trim(new.student_name),
           phone = coalesce(phone, nullif(trim(new.student_phone), '')),
           email = coalesce(email, nullif(lower(trim(new.student_email)), '')),
           center = coalesce(center, nullif(trim(new.center), '')),
           updated_at = now()
     where id = v_profile_id;
  end if;

  -- Attach an already-approved graduate account only on an unambiguous phone match.
  if v_phone is not null then
    select count(*), min(g.id)
      into v_graduate_matches, v_graduate_id
      from public.graduate_profiles g
     where nullif(regexp_replace(coalesce(g.phone, ''), '[^0-9]', '', 'g'), '') = v_phone
       and g.auth_user_id is not null;
    if v_graduate_matches = 1 then
      update public.alumni_profiles
         set legacy_graduate_profile_id = v_graduate_id,
             updated_at = now()
       where id = v_profile_id
         and (legacy_graduate_profile_id is null or legacy_graduate_profile_id = v_graduate_id);
    end if;
  end if;

  v_qualification_name := coalesce(
    nullif(trim(concat_ws(' ',
      nullif(trim(new.academic_degree), ''),
      nullif(trim(new.academic_faculty), '')
    )), ''),
    nullif(trim(new.specialization), ''),
    nullif(trim(new.course), ''),
    'مؤهل / شهادة تدريبية'
  );

  insert into public.alumni_qualifications (
    alumni_id, certificate_id, qualification_name, institution_name,
    faculty_name, specialization, graduation_year, grade, verification_status
  )
  values (
    v_profile_id, new.id, v_qualification_name,
    coalesce(nullif(trim(new.academic_university), ''), nullif(trim(new.center), '')),
    nullif(trim(new.academic_faculty), ''),
    nullif(trim(new.specialization), ''),
    new.graduation_year,
    nullif(trim(new.grade), ''),
    'verified'
  )
  on conflict (alumni_id, certificate_id) do update
    set qualification_name = excluded.qualification_name,
        institution_name = excluded.institution_name,
        faculty_name = excluded.faculty_name,
        specialization = excluded.specialization,
        graduation_year = excluded.graduation_year,
        grade = excluded.grade,
        verification_status = 'verified';

  return new;
end;
$$;

revoke all on function public.sync_academic_certificate_to_alumni() from public, anon, authenticated;

drop trigger if exists trg_sync_academic_certificate_to_alumni on public.certificates;
create trigger trg_sync_academic_certificate_to_alumni
after insert or update of
  cert_number, student_name, student_phone, student_email, center, record_type,
  status, academic_degree, academic_faculty, academic_university, course,
  specialization, graduation_year, grade
on public.certificates
for each row
execute function public.sync_academic_certificate_to_alumni();

-- When a graduate's account is approved and its profile is created, claim matching
-- certificate profiles automatically. Ambiguous phone matches are deliberately not linked.
create or replace function public.link_approved_graduate_to_certificate_profiles()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_phone text;
  v_matches integer := 0;
begin
  v_phone := nullif(regexp_replace(coalesce(new.phone, ''), '[^0-9]', '', 'g'), '');
  if new.auth_user_id is null or v_phone is null then
    return new;
  end if;

  select count(*) into v_matches
    from public.graduate_profiles g
   where g.auth_user_id is not null
     and nullif(regexp_replace(coalesce(g.phone, ''), '[^0-9]', '', 'g'), '') = v_phone;

  if v_matches = 1 then
    update public.alumni_profiles p
       set legacy_graduate_profile_id = new.id,
           updated_at = now()
     where nullif(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), '') = v_phone
       and (p.legacy_graduate_profile_id is null or p.legacy_graduate_profile_id = new.id);
  end if;
  return new;
end;
$$;

revoke all on function public.link_approved_graduate_to_certificate_profiles() from public, anon, authenticated;
drop trigger if exists trg_link_approved_graduate_to_certificate_profiles on public.graduate_profiles;
create trigger trg_link_approved_graduate_to_certificate_profiles
after insert or update of auth_user_id, phone on public.graduate_profiles
for each row execute function public.link_approved_graduate_to_certificate_profiles();

comment on function public.sync_academic_certificate_to_alumni() is
  'Links active certificates to hidden alumni profiles, reuses an unambiguous phone match, and never grants public visibility or account access.';
