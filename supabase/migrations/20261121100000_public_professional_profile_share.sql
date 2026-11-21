-- Public, consent-gated professional profile sharing.
-- Public sharing is a separate, explicit choice from employer-directory visibility.
ALTER TABLE public.graduate_profiles
  ADD COLUMN IF NOT EXISTS public_profile_consent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS public_profile_consent_at timestamptz;

CREATE OR REPLACE FUNCTION public.get_public_professional_profile(p_profile_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'profile', jsonb_build_object(
      'id', p.id,
      'profile_number', p.profile_number,
      'full_name', p.full_name,
      'professional_summary', p.professional_summary,
      'governorate', p.governorate,
      'center', p.center,
      'updated_at', p.updated_at
    ),
    'qualifications', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'qualification', q.qualification_name,
          'institution', q.institution_name,
          'faculty', q.faculty_name,
          'specialization', q.specialization,
          'graduation_year', q.graduation_year,
          'verification_status', q.verification_status
        )
        ORDER BY q.sort_order, q.graduation_year DESC NULLS LAST
      )
      FROM public.alumni_qualifications q
      WHERE q.alumni_id = p.id
        AND q.verification_status = 'verified'
    ), '[]'::jsonb),
    'skills', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object('name', s.skill_name, 'proficiency', s.proficiency)
        ORDER BY s.skill_name
      )
      FROM public.alumni_skills s
      WHERE s.alumni_id = p.id
        AND s.skill_category = 'general'
    ), '[]'::jsonb)
  )
  FROM public.alumni_profiles p
  JOIN public.graduate_profiles g ON g.id = p.legacy_graduate_profile_id
  WHERE p.id = p_profile_id
    AND p.visibility_status = 'public'
    AND p.publication_consent IS TRUE
    AND g.public_profile_consent IS TRUE
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.get_public_professional_profile(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_professional_profile(uuid) TO anon, authenticated;

COMMENT ON FUNCTION public.get_public_professional_profile(uuid) IS
'Returns a minimal public professional profile only when platform publication approval, employer publication consent, and separate public-link consent are all active. Never returns contact details, private documents, CV paths, or unverified qualifications.';
