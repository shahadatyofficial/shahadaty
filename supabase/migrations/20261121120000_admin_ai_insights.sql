-- Aggregate-only AI administration insights. No names, emails, phones, or record-level data leave the database.
CREATE OR REPLACE FUNCTION public.get_admin_ai_insights_context()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_context jsonb;
BEGIN
  IF auth.uid() IS NULL OR public.is_platform_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'ADMIN_REQUIRED';
  END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'institutions', jsonb_build_object(
      'total', (SELECT COUNT(*) FROM public.institutions),
      'approved', (SELECT COUNT(*) FROM public.institutions WHERE status = 'approved'),
      'pending', (SELECT COUNT(*) FROM public.institutions WHERE status = 'pending'),
      'rejected', (SELECT COUNT(*) FROM public.institutions WHERE status = 'rejected')
    ),
    'subscriptions', jsonb_build_object(
      'total', (SELECT COUNT(*) FROM public.subscriptions),
      'active', (SELECT COUNT(*) FROM public.subscriptions WHERE status = 'active' AND payment_status = 'paid' AND (ends_at IS NULL OR ends_at > now())),
      'pending_payment', (SELECT COUNT(*) FROM public.subscriptions WHERE payment_status = 'pending' OR status = 'pending'),
      'ending_within_30_days', (SELECT COUNT(*) FROM public.subscriptions WHERE status = 'active' AND ends_at BETWEEN now() AND now() + interval '30 days'),
      'expired_but_marked_active', (SELECT COUNT(*) FROM public.subscriptions WHERE status = 'active' AND ends_at < now())
    ),
    'training', jsonb_build_object(
      'courses_total', (SELECT COUNT(*) FROM public.institution_courses),
      'courses_active', (SELECT COUNT(*) FROM public.institution_courses WHERE is_active IS TRUE),
      'groups_open', (SELECT COUNT(*) FROM public.institution_course_runs WHERE status = 'open'),
      'groups_in_progress', (SELECT COUNT(*) FROM public.institution_course_runs WHERE status = 'in_progress'),
      'enrollments_total', (SELECT COUNT(*) FROM public.institution_enrollments),
      'enrollments_active', (SELECT COUNT(*) FROM public.institution_enrollments WHERE status IN ('enrolled','attending')),
      'attendance_present', (SELECT COUNT(*) FROM public.institution_attendance WHERE attendance_status = 'present'),
      'attendance_absent', (SELECT COUNT(*) FROM public.institution_attendance WHERE attendance_status = 'absent'),
      'public_course_listings', (SELECT COUNT(*) FROM public.institution_course_runs WHERE is_publicly_listed IS TRUE AND status IN ('open','in_progress')),
      'marketplace_applications_pending', (SELECT COUNT(*) FROM public.training_marketplace_applications WHERE status = 'pending')
    ),
    'certificates', jsonb_build_object(
      'total', (SELECT COUNT(*) FROM public.certificates),
      'active', (SELECT COUNT(*) FROM public.certificates WHERE status = 'active'),
      'not_active', (SELECT COUNT(*) FROM public.certificates WHERE status IS DISTINCT FROM 'active')
    ),
    'graduates', jsonb_build_object(
      'total', (SELECT COUNT(*) FROM public.graduate_profiles),
      'employer_publication_consent', (SELECT COUNT(*) FROM public.graduate_profiles WHERE publication_consent IS TRUE),
      'public_link_consent', (SELECT COUNT(*) FROM public.graduate_profiles WHERE public_profile_consent IS TRUE),
      'access_requests_pending', (SELECT COUNT(*) FROM public.graduate_access_requests WHERE status = 'pending'),
      'memberships_pending', (SELECT COUNT(*) FROM public.graduate_membership_requests WHERE status = 'pending'),
      'memberships_active', (SELECT COUNT(*) FROM public.graduate_membership_requests WHERE status = 'approved' AND ends_at > now())
    ),
    'employers', jsonb_build_object(
      'companies_total', (SELECT COUNT(*) FROM public.companies),
      'companies_approved', (SELECT COUNT(*) FROM public.companies WHERE status = 'approved'),
      'companies_pending', (SELECT COUNT(*) FROM public.companies WHERE status = 'pending'),
      'job_announcements_pending', (SELECT COUNT(*) FROM public.job_announcements WHERE status = 'pending'),
      'job_announcements_published', (SELECT COUNT(*) FROM public.job_announcements WHERE status = 'approved' AND (expires_at IS NULL OR expires_at >= now())),
      'job_applications_total', (SELECT COUNT(*) FROM public.job_applications)
    ),
    'support', jsonb_build_object(
      'open_conversations', (SELECT COUNT(*) FROM public.support_conversations WHERE status = 'open')
    )
  ) INTO v_context;

  RETURN v_context;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_admin_ai_insights_context() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_admin_ai_insights_context() TO authenticated;

COMMENT ON FUNCTION public.get_admin_ai_insights_context() IS
'Returns aggregate operational metrics only, and only to authenticated platform administrators, for the admin AI assistant. No personally identifying or record-level data is returned.';
