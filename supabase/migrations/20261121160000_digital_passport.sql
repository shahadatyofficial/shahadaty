-- Public digital passport: one consent-controlled index of individually shareable certificates.
ALTER TABLE public.graduate_profiles
  ADD COLUMN IF NOT EXISTS digital_passport_public_consent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS digital_passport_public_consent_at timestamptz;

CREATE OR REPLACE FUNCTION public.get_public_digital_passport(p_profile_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'profile', jsonb_build_object(
      'id', gp.id,
      'full_name', gp.full_name,
      'governorate', gp.governorate,
      'qualification', gp.qualification,
      'specialization', gp.specialization,
      'graduation_year', gp.graduation_year
    ),
    'certificates', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'cert_number', c.cert_number,
          'course', c.course,
          'specialization', c.specialization,
          'issue_date', c.issue_date,
          'expiry_date', c.expiry_date,
          'grade', c.grade,
          'duration', c.duration,
          'status', COALESCE(c.status,'unknown'),
          'record_type', c.record_type,
          'source_type', c.source_type,
          'institution_name', i.name,
          'institution_type', i.institution_type
        )
        ORDER BY c.issue_date DESC, c.created_at DESC
      )
      FROM public.certificates c
      JOIN public.institutions i ON i.id = c.institution_id AND i.status = 'approved'
      WHERE NULLIF(regexp_replace(COALESCE(gp.phone,''),'[^0-9]','','g'),'') IS NOT NULL
        AND regexp_replace(COALESCE(gp.phone,''),'[^0-9]','','g')
          = regexp_replace(COALESCE(c.student_phone,''),'[^0-9]','','g')
        AND c.visible_to_companies IS TRUE
        AND c.consent_given_at IS NOT NULL
    ), '[]'::jsonb)
  )
  FROM public.graduate_profiles gp
  WHERE gp.id = p_profile_id
    AND gp.digital_passport_public_consent IS TRUE
    AND EXISTS (
      SELECT 1
      FROM public.certificates c
      JOIN public.institutions i ON i.id = c.institution_id AND i.status = 'approved'
      WHERE NULLIF(regexp_replace(COALESCE(gp.phone,''),'[^0-9]','','g'),'') IS NOT NULL
        AND regexp_replace(COALESCE(gp.phone,''),'[^0-9]','','g')
          = regexp_replace(COALESCE(c.student_phone,''),'[^0-9]','','g')
        AND c.visible_to_companies IS TRUE
        AND c.consent_given_at IS NOT NULL
    )
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.get_public_digital_passport(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_digital_passport(uuid) TO anon, authenticated;

COMMENT ON FUNCTION public.get_public_digital_passport(uuid) IS
'Returns a graduate digital passport only after separate public-passport consent. Includes only certificates individually marked visible_to_companies with consent_given_at, from approved institutions. Excludes contact details, national IDs, private files, and certificate PDF URLs.';

CREATE OR REPLACE FUNCTION public.search_alumni_for_company_v3(
  p_query text DEFAULT NULL,
  p_qualification text DEFAULT NULL,
  p_specialization text DEFAULT NULL,
  p_governorate text DEFAULT NULL,
  p_graduation_year integer DEFAULT NULL,
  p_skill text DEFAULT NULL,
  p_center text DEFAULT NULL
)
RETURNS TABLE (
  alumni_id uuid,
  graduate_profile_id uuid,
  full_name text,
  qualification_name text,
  graduation_year integer,
  governorate text,
  center text,
  public_profile_available boolean,
  digital_passport_available boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_company_id uuid;
  v_credits integer;
  v_rows integer;
BEGIN
  SELECT c.id, COALESCE(c.search_credits,0)
    INTO v_company_id, v_credits
  FROM public.companies c
  WHERE c.auth_user_id = auth.uid() AND c.status = 'approved'
  ORDER BY c.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_company_id IS NULL THEN RAISE EXCEPTION 'APPROVED_COMPANY_REQUIRED'; END IF;
  IF v_credits <= 0 THEN RAISE EXCEPTION 'SEARCH_CREDITS_EXHAUSTED'; END IF;

  RETURN QUERY
  SELECT
    p.id,
    g.id,
    p.full_name,
    q.qualification_name,
    q.graduation_year,
    p.governorate,
    p.center,
    COALESCE(g.public_profile_consent IS TRUE, false),
    COALESCE(g.digital_passport_public_consent IS TRUE, false)
  FROM public.alumni_profiles p
  JOIN public.alumni_qualifications q
    ON q.alumni_id = p.id AND q.verification_status = 'verified'
  LEFT JOIN public.graduate_profiles g ON g.id = p.legacy_graduate_profile_id
  WHERE p.visibility_status = 'public'
    AND p.publication_consent IS TRUE
    AND (NULLIF(BTRIM(p_query),'') IS NULL OR p.full_name ILIKE '%' || BTRIM(p_query) || '%')
    AND (NULLIF(BTRIM(p_qualification),'') IS NULL OR q.qualification_name ILIKE '%' || BTRIM(p_qualification) || '%')
    AND (NULLIF(BTRIM(p_specialization),'') IS NULL OR COALESCE(q.specialization,'') ILIKE '%' || BTRIM(p_specialization) || '%')
    AND (NULLIF(BTRIM(p_governorate),'') IS NULL OR COALESCE(p.governorate,'') ILIKE '%' || BTRIM(p_governorate) || '%')
    AND (p_graduation_year IS NULL OR q.graduation_year = p_graduation_year)
    AND (NULLIF(BTRIM(p_skill),'') IS NULL OR EXISTS (
      SELECT 1 FROM public.alumni_skills sk
      WHERE sk.alumni_id = p.id AND sk.skill_name ILIKE '%' || BTRIM(p_skill) || '%'
        AND (
          sk.skill_category NOT IN ('graduate_profile','graduate_language','graduate_target_role')
          OR EXISTS (
            SELECT 1 FROM public.graduate_membership_requests m
            WHERE m.auth_user_id = g.auth_user_id
              AND m.status = 'approved' AND m.ends_at > now()
          )
        )
    ))
    AND (NULLIF(BTRIM(p_center),'') IS NULL OR COALESCE(p.center,'') ILIKE '%' || BTRIM(p_center) || '%')
  ORDER BY p.full_name, q.graduation_year DESC NULLS LAST
  LIMIT 100;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows > 0 THEN
    UPDATE public.companies
    SET search_credits = GREATEST(COALESCE(search_credits,0)-1,0)
    WHERE id = v_company_id;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.search_alumni_for_company_v3(text,text,text,text,integer,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_alumni_for_company_v3(text,text,text,text,integer,text,text) TO authenticated;

COMMENT ON FUNCTION public.search_alumni_for_company_v3(text,text,text,text,integer,text,text) IS
'Employer search v3 returns verified qualifications and only indicates availability of public professional profiles or digital passports when the graduate has explicitly consented.';
