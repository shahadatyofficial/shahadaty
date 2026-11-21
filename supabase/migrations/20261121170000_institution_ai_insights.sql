-- Institution-scoped aggregate analytics for the AI assistant.
CREATE OR REPLACE FUNCTION public.get_institution_ai_insights_context(
  p_institution_id uuid,
  p_branch_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_context jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.institution_branches b
    WHERE b.id = p_branch_id AND b.institution_id = p_institution_id
  ) THEN
    RAISE EXCEPTION 'BRANCH_NOT_FOUND';
  END IF;
  IF public.institution_has_permission(p_institution_id,'reports.view',p_branch_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'REPORTS_PERMISSION_REQUIRED';
  END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'scope', CASE WHEN p_branch_id IS NULL THEN 'institution' ELSE 'branch' END,
    'training', jsonb_build_object(
      'courses_total', (
        SELECT COUNT(DISTINCT r.course_id) FROM public.institution_course_runs r
        WHERE r.institution_id = p_institution_id AND (p_branch_id IS NULL OR r.branch_id = p_branch_id)
      ),
      'groups_total', (
        SELECT COUNT(*) FROM public.institution_course_runs r
        WHERE r.institution_id = p_institution_id AND (p_branch_id IS NULL OR r.branch_id = p_branch_id)
      ),
      'groups_open', (
        SELECT COUNT(*) FROM public.institution_course_runs r
        WHERE r.institution_id = p_institution_id AND r.status = 'open'
          AND (p_branch_id IS NULL OR r.branch_id = p_branch_id)
      ),
      'groups_in_progress', (
        SELECT COUNT(*) FROM public.institution_course_runs r
        WHERE r.institution_id = p_institution_id AND r.status = 'in_progress'
          AND (p_branch_id IS NULL OR r.branch_id = p_branch_id)
      ),
      'groups_overdue', (
        SELECT COUNT(*) FROM public.institution_course_runs r
        WHERE r.institution_id = p_institution_id AND r.end_date < CURRENT_DATE
          AND r.status NOT IN ('completed','cancelled')
          AND (p_branch_id IS NULL OR r.branch_id = p_branch_id)
      ),
      'enrollments_total', (
        SELECT COUNT(*) FROM public.institution_enrollments e
        JOIN public.institution_course_runs r ON r.id = e.course_run_id
        WHERE e.institution_id = p_institution_id AND (p_branch_id IS NULL OR r.branch_id = p_branch_id)
      ),
      'enrollments_active', (
        SELECT COUNT(*) FROM public.institution_enrollments e
        JOIN public.institution_course_runs r ON r.id = e.course_run_id
        WHERE e.institution_id = p_institution_id AND e.status IN ('enrolled','attending')
          AND (p_branch_id IS NULL OR r.branch_id = p_branch_id)
      ),
      'trainees_total', (
        SELECT COUNT(*) FROM public.institution_trainees t
        WHERE t.institution_id = p_institution_id AND t.status = 'active'
          AND (p_branch_id IS NULL OR t.branch_id = p_branch_id)
      ),
      'sessions_upcoming_7_days', (
        SELECT COUNT(*) FROM public.institution_course_sessions s
        WHERE s.institution_id = p_institution_id
          AND s.session_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
          AND (p_branch_id IS NULL OR s.branch_id = p_branch_id)
      ),
      'sessions_overdue_without_attendance', (
        SELECT COUNT(*) FROM public.institution_course_sessions s
        WHERE s.institution_id = p_institution_id AND s.session_date < CURRENT_DATE
          AND s.status = 'planned'
          AND (p_branch_id IS NULL OR s.branch_id = p_branch_id)
          AND NOT EXISTS (SELECT 1 FROM public.institution_attendance a WHERE a.session_id = s.id)
      )
    ),
    'attendance', jsonb_build_object(
      'records_total', (
        SELECT COUNT(*) FROM public.institution_attendance a
        JOIN public.institution_course_sessions s ON s.id = a.session_id
        WHERE s.institution_id = p_institution_id AND (p_branch_id IS NULL OR s.branch_id = p_branch_id)
      ),
      'present', (
        SELECT COUNT(*) FROM public.institution_attendance a
        JOIN public.institution_course_sessions s ON s.id = a.session_id
        WHERE s.institution_id = p_institution_id AND a.attendance_status = 'present'
          AND (p_branch_id IS NULL OR s.branch_id = p_branch_id)
      ),
      'absent', (
        SELECT COUNT(*) FROM public.institution_attendance a
        JOIN public.institution_course_sessions s ON s.id = a.session_id
        WHERE s.institution_id = p_institution_id AND a.attendance_status = 'absent'
          AND (p_branch_id IS NULL OR s.branch_id = p_branch_id)
      ),
      'late', (
        SELECT COUNT(*) FROM public.institution_attendance a
        JOIN public.institution_course_sessions s ON s.id = a.session_id
        WHERE s.institution_id = p_institution_id AND a.attendance_status = 'late'
          AND (p_branch_id IS NULL OR s.branch_id = p_branch_id)
      )
    ),
    'marketplace', jsonb_build_object(
      'public_listings', (
        SELECT COUNT(*) FROM public.institution_course_runs r
        WHERE r.institution_id = p_institution_id AND r.is_publicly_listed IS TRUE
          AND r.status IN ('open','in_progress')
          AND (p_branch_id IS NULL OR r.branch_id = p_branch_id)
      ),
      'applications_pending', (
        SELECT COUNT(*) FROM public.training_marketplace_applications a
        WHERE a.institution_id = p_institution_id AND a.status = 'pending'
          AND (p_branch_id IS NULL OR a.branch_id = p_branch_id)
      ),
      'applications_waiting_over_48_hours', (
        SELECT COUNT(*) FROM public.training_marketplace_applications a
        WHERE a.institution_id = p_institution_id AND a.status = 'pending'
          AND a.created_at < now() - interval '48 hours'
          AND (p_branch_id IS NULL OR a.branch_id = p_branch_id)
      )
    ),
    'institution_admin_only', CASE WHEN p_branch_id IS NULL THEN jsonb_build_object(
      'subscriptions_active', (
        SELECT COUNT(*) FROM public.subscriptions s
        WHERE s.institution_id = p_institution_id AND s.status = 'active'
          AND s.payment_status = 'paid' AND (s.ends_at IS NULL OR s.ends_at > now())
      ),
      'subscriptions_pending_payment', (
        SELECT COUNT(*) FROM public.subscriptions s
        WHERE s.institution_id = p_institution_id
          AND (s.payment_status = 'pending' OR s.status = 'pending')
      ),
      'subscriptions_ending_30_days', (
        SELECT COUNT(*) FROM public.subscriptions s
        WHERE s.institution_id = p_institution_id AND s.status = 'active'
          AND s.ends_at BETWEEN now() AND now() + interval '30 days'
      ),
      'certificates_total', (SELECT COUNT(*) FROM public.certificates c WHERE c.institution_id = p_institution_id),
      'certificates_issued_30_days', (
        SELECT COUNT(*) FROM public.certificates c
        WHERE c.institution_id = p_institution_id AND c.issue_date >= CURRENT_DATE - 30
      )
    ) ELSE NULL END
  ) INTO v_context;

  RETURN v_context;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_institution_ai_insights_context(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_institution_ai_insights_context(uuid,uuid) TO authenticated;

COMMENT ON FUNCTION public.get_institution_ai_insights_context(uuid,uuid) IS
'Returns aggregate institution or assigned-branch analytics to users with reports.view permission. Branch-level reports omit institution-wide subscription and certificate totals.';
