-- Correct the pending marketplace reminder message concatenation in the scheduled reminder function.
CREATE OR REPLACE FUNCTION app_private.enqueue_due_platform_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE 'Africa/Cairo')::date;
  v_row record;
  v_recipient record;
  v_notification_id uuid;
  v_count integer := 0;
BEGIN
  -- Remind institution owners and managers about tomorrow's planned sessions.
  FOR v_row IN
    SELECT s.id, s.institution_id, s.course_run_id, s.title, s.session_date, s.starts_at,
           r.run_name, c.name AS course_name
    FROM public.institution_course_sessions s
    JOIN public.institution_course_runs r ON r.id = s.course_run_id
    JOIN public.institution_courses c ON c.id = r.course_id
    WHERE s.session_date = v_today + 1 AND s.status = 'planned'
  LOOP
    FOR v_recipient IN
      SELECT i.auth_user_id AS user_id
      FROM public.institutions i
      WHERE i.id = v_row.institution_id AND i.auth_user_id IS NOT NULL
      UNION
      SELECT iu.auth_user_id
      FROM public.institution_users iu
      WHERE iu.institution_id = v_row.institution_id
        AND iu.status = 'active' AND iu.role IN ('owner','manager')
    LOOP
      v_notification_id := app_private.enqueue_deduplicated_platform_notification(
        v_recipient.user_id,'training_session_reminder','تذكير بجلسة تدريبية غدًا',
        'لديكم جلسة ' || COALESCE(v_row.title,'تدريبية') || ' غدًا ضمن دورة ' ||
          COALESCE(v_row.course_name,'') ||
          CASE WHEN v_row.starts_at IS NOT NULL THEN ' الساعة ' || v_row.starts_at::text ELSE '' END || '.',
        'institution.html','training_session',v_row.id,
        'session:' || v_row.id::text || ':' || v_today::text
      );
      IF v_notification_id IS NOT NULL THEN v_count := v_count + 1; END IF;
    END LOOP;

    FOR v_recipient IN
      SELECT DISTINCT gp.auth_user_id AS user_id
      FROM public.institution_enrollments e
      JOIN public.institution_trainees t ON t.id = e.trainee_id
      JOIN public.graduate_profiles gp
        ON regexp_replace(COALESCE(gp.phone,''),'[^0-9]','','g')
         = regexp_replace(COALESCE(t.phone,''),'[^0-9]','','g')
      WHERE e.course_run_id = v_row.course_run_id
        AND e.status IN ('enrolled','attending')
        AND gp.auth_user_id IS NOT NULL
        AND NULLIF(regexp_replace(COALESCE(t.phone,''),'[^0-9]','','g'),'') IS NOT NULL
    LOOP
      v_notification_id := app_private.enqueue_deduplicated_platform_notification(
        v_recipient.user_id,'training_session_reminder','تذكير بموعد جلسة غدًا',
        'لديك جلسة ' || COALESCE(v_row.title,'تدريبية') || ' غدًا ضمن دورة ' ||
          COALESCE(v_row.course_name,'') ||
          CASE WHEN v_row.starts_at IS NOT NULL THEN ' الساعة ' || v_row.starts_at::text ELSE '' END || '.',
        'graduate-v2.html','training_session',v_row.id,
        'graduate-session:' || v_row.id::text || ':' || v_today::text
      );
      IF v_notification_id IS NOT NULL THEN v_count := v_count + 1; END IF;
    END LOOP;
  END LOOP;

  -- Remind institutions 7, 3, and 1 days before a paid subscription ends.
  FOR v_row IN
    SELECT s.id, s.institution_id, s.ends_at
    FROM public.subscriptions s
    WHERE s.status = 'active' AND s.payment_status = 'paid'
      AND s.ends_at IS NOT NULL
      AND (s.ends_at AT TIME ZONE 'Africa/Cairo')::date IN (v_today + 7, v_today + 3, v_today + 1)
  LOOP
    FOR v_recipient IN
      SELECT i.auth_user_id AS user_id
      FROM public.institutions i
      WHERE i.id = v_row.institution_id AND i.auth_user_id IS NOT NULL
      UNION
      SELECT iu.auth_user_id
      FROM public.institution_users iu
      WHERE iu.institution_id = v_row.institution_id
        AND iu.status = 'active' AND iu.role IN ('owner','manager')
    LOOP
      v_notification_id := app_private.enqueue_deduplicated_platform_notification(
        v_recipient.user_id,'subscription_expiry_reminder','موعد تجديد اشتراك المؤسسة',
        'يتبقى ' || ((v_row.ends_at AT TIME ZONE 'Africa/Cairo')::date - v_today)::text ||
          ' يومًا على انتهاء اشتراك المؤسسة. راجع صفحة الاشتراكات لتجنب توقف الخدمات.',
        'institution.html','subscription',v_row.id,
        'subscription:' || v_row.id::text || ':' || (v_row.ends_at AT TIME ZONE 'Africa/Cairo')::date::text || ':' || ((v_row.ends_at AT TIME ZONE 'Africa/Cairo')::date - v_today)::text
      );
      IF v_notification_id IS NOT NULL THEN v_count := v_count + 1; END IF;
    END LOOP;
  END LOOP;

  -- Escalate pending course applications that have waited more than 48 hours.
  FOR v_row IN
    SELECT a.id, a.institution_id, a.created_at, c.name AS course_name
    FROM public.training_marketplace_applications a
    JOIN public.institution_course_runs r ON r.id = a.course_run_id
    JOIN public.institution_courses c ON c.id = r.course_id
    WHERE a.status = 'pending' AND a.created_at < now() - interval '48 hours'
  LOOP
    FOR v_recipient IN
      SELECT i.auth_user_id AS user_id
      FROM public.institutions i
      WHERE i.id = v_row.institution_id AND i.auth_user_id IS NOT NULL
      UNION
      SELECT iu.auth_user_id
      FROM public.institution_users iu
      WHERE iu.institution_id = v_row.institution_id
        AND iu.status = 'active' AND iu.role IN ('owner','manager')
    LOOP
      v_notification_id := app_private.enqueue_deduplicated_platform_notification(
        v_recipient.user_id,'training_application_pending_reminder','طلب التحاق يحتاج إلى مراجعة',
        'يوجد طلب التحاق بدورة ' || COALESCE(v_row.course_name,'تدريبية') ||
          ' لم تتم مراجعته منذ أكثر من 48 ساعة.',
        'institution.html','training_marketplace_application',v_row.id,
        'marketplace-pending:' || v_row.id::text || ':' || v_today::text
      );
      IF v_notification_id IS NOT NULL THEN v_count := v_count + 1; END IF;
    END LOOP;
  END LOOP;

  -- Daily reminders to platform admins about unreviewed registrations.
  FOR v_row IN
    SELECT id FROM public.institutions
    WHERE status = 'pending' AND created_at < now() - interval '24 hours'
    UNION ALL
    SELECT id FROM public.graduate_access_requests
    WHERE status = 'pending' AND created_at < now() - interval '24 hours'
    UNION ALL
    SELECT id FROM public.graduate_membership_requests
    WHERE status = 'pending' AND created_at < now() - interval '24 hours'
  LOOP
    FOR v_recipient IN
      SELECT pa.auth_user_id AS user_id
      FROM public.platform_admins pa
      WHERE pa.status = 'active'
    LOOP
      v_notification_id := app_private.enqueue_deduplicated_platform_notification(
        v_recipient.user_id,'admin_pending_review_reminder','طلبات مراجعة معلقة',
        'توجد طلبات تسجيل أو عضوية تجاوزت 24 ساعة وتحتاج إلى المراجعة.',
        'admin.html','pending_review',v_row.id,
        'admin-review:' || v_row.id::text || ':' || v_today::text
      );
      IF v_notification_id IS NOT NULL THEN v_count := v_count + 1; END IF;
    END LOOP;
  END LOOP;

  RETURN v_count;
END;
$function$;
