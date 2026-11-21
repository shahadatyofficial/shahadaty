-- Unified in-app notifications with an opt-in email queue.
-- All event notifications are generated server-side; clients can only read their own and mark them read.

CREATE SCHEMA IF NOT EXISTS app_private;
REVOKE ALL ON SCHEMA app_private FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.platform_notification_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  in_app_enabled boolean NOT NULL DEFAULT true,
  email_enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.platform_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  notification_type text NOT NULL,
  title text NOT NULL,
  body text,
  action_url text,
  related_entity_type text,
  related_entity_id uuid,
  in_app_visible boolean NOT NULL DEFAULT true,
  email_requested boolean NOT NULL DEFAULT false,
  email_status text NOT NULL DEFAULT 'not_requested'
    CHECK (email_status IN ('not_requested','queued','sent','failed','not_configured')),
  email_attempts integer NOT NULL DEFAULT 0 CHECK (email_attempts >= 0),
  email_error text,
  email_sent_at timestamptz,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS platform_notifications_recipient_created_idx
  ON public.platform_notifications (recipient_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS platform_notifications_email_queue_idx
  ON public.platform_notifications (created_at)
  WHERE email_status = 'queued';

ALTER TABLE public.platform_notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS platform_notification_preferences_select_own ON public.platform_notification_preferences;
CREATE POLICY platform_notification_preferences_select_own
  ON public.platform_notification_preferences FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
DROP POLICY IF EXISTS platform_notification_preferences_insert_own ON public.platform_notification_preferences;
CREATE POLICY platform_notification_preferences_insert_own
  ON public.platform_notification_preferences FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
DROP POLICY IF EXISTS platform_notification_preferences_update_own ON public.platform_notification_preferences;
CREATE POLICY platform_notification_preferences_update_own
  ON public.platform_notification_preferences FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS platform_notifications_select_own ON public.platform_notifications;
CREATE POLICY platform_notifications_select_own
  ON public.platform_notifications FOR SELECT TO authenticated
  USING (recipient_user_id = (SELECT auth.uid()) AND in_app_visible IS TRUE);
DROP POLICY IF EXISTS platform_notifications_mark_own_read ON public.platform_notifications;
CREATE POLICY platform_notifications_mark_own_read
  ON public.platform_notifications FOR UPDATE TO authenticated
  USING (recipient_user_id = (SELECT auth.uid()) AND in_app_visible IS TRUE)
  WITH CHECK (recipient_user_id = (SELECT auth.uid()) AND in_app_visible IS TRUE);

REVOKE ALL ON TABLE public.platform_notification_preferences FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE (in_app_enabled, email_enabled, updated_at) ON public.platform_notification_preferences TO authenticated;
REVOKE ALL ON TABLE public.platform_notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.platform_notifications TO authenticated;
GRANT UPDATE (read_at) ON public.platform_notifications TO authenticated;

CREATE OR REPLACE FUNCTION app_private.enqueue_platform_notification(
  p_recipient_user_id uuid,
  p_notification_type text,
  p_title text,
  p_body text DEFAULT NULL,
  p_action_url text DEFAULT NULL,
  p_related_entity_type text DEFAULT NULL,
  p_related_entity_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_in_app boolean := true;
  v_email boolean := false;
  v_id uuid;
BEGIN
  IF p_recipient_user_id IS NULL OR NULLIF(BTRIM(p_title),'') IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(pref.in_app_enabled,true), COALESCE(pref.email_enabled,false)
    INTO v_in_app, v_email
  FROM (SELECT 1) seed
  LEFT JOIN public.platform_notification_preferences pref
    ON pref.user_id = p_recipient_user_id;

  IF NOT v_in_app AND NOT v_email THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.platform_notifications (
    recipient_user_id, notification_type, title, body, action_url,
    related_entity_type, related_entity_id, in_app_visible,
    email_requested, email_status
  ) VALUES (
    p_recipient_user_id, p_notification_type, LEFT(BTRIM(p_title),180),
    LEFT(NULLIF(BTRIM(p_body),''),2000), p_action_url,
    p_related_entity_type, p_related_entity_id, v_in_app,
    v_email, CASE WHEN v_email THEN 'queued' ELSE 'not_requested' END
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app_private.notify_marketplace_application_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_course_name text;
  v_run_name text;
  v_institution_name text;
  v_recipient record;
  v_graduate_user_id uuid;
  v_title text;
  v_body text;
BEGIN
  SELECT c.name, r.run_name, i.name
    INTO v_course_name, v_run_name, v_institution_name
  FROM public.institution_course_runs r
  JOIN public.institution_courses c ON c.id = r.course_id
  JOIN public.institutions i ON i.id = r.institution_id
  WHERE r.id = NEW.course_run_id;

  IF TG_OP = 'INSERT' THEN
    v_title := 'طلب التحاق جديد';
    v_body := 'وصل طلب التحاق جديد بدورة ' || COALESCE(v_course_name,'تدريبية') ||
      CASE WHEN NULLIF(v_run_name,'') IS NOT NULL THEN ' — ' || v_run_name ELSE '' END || '.';
    FOR v_recipient IN
      SELECT i.auth_user_id AS user_id
      FROM public.institutions i
      WHERE i.id = NEW.institution_id AND i.auth_user_id IS NOT NULL
      UNION
      SELECT iu.auth_user_id
      FROM public.institution_users iu
      WHERE iu.institution_id = NEW.institution_id
        AND iu.status = 'active'
        AND iu.role IN ('owner','manager')
    LOOP
      PERFORM app_private.enqueue_platform_notification(
        v_recipient.user_id,'training_application_new',v_title,v_body,
        'institution.html','training_marketplace_application',NEW.id
      );
    END LOOP;
  ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
    SELECT gp.auth_user_id INTO v_graduate_user_id
    FROM public.graduate_profiles gp
    WHERE gp.id = NEW.graduate_profile_id;
    v_title := CASE NEW.status
      WHEN 'accepted' THEN 'تم قبول طلب الالتحاق'
      WHEN 'rejected' THEN 'تحديث طلب الالتحاق'
      WHEN 'withdrawn' THEN 'تم سحب طلب الالتحاق'
      ELSE 'تحديث طلب الالتحاق'
    END;
    v_body := 'تم تحديث طلبك لدورة ' || COALESCE(v_course_name,'تدريبية') ||
      ' لدى ' || COALESCE(v_institution_name,'المؤسسة') || ' إلى الحالة: ' || NEW.status || '.';
    PERFORM app_private.enqueue_platform_notification(
      v_graduate_user_id,'training_application_status',v_title,v_body,
      'graduate-v2.html','training_marketplace_application',NEW.id
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION app_private.notify_graduate_membership_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_title text;
  v_body text;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    v_title := CASE NEW.status WHEN 'approved' THEN 'تم تفعيل عضويتك' WHEN 'rejected' THEN 'تحديث طلب العضوية' ELSE 'تحديث طلب العضوية' END;
    v_body := CASE NEW.status
      WHEN 'approved' THEN 'تمت الموافقة على طلب العضوية السنوية وأصبحت العضوية مفعلة.'
      WHEN 'rejected' THEN 'لم تتم الموافقة على طلب العضوية. راجع بوابة الخريج لمعرفة التفاصيل.'
      ELSE 'تم تحديث حالة طلب العضوية إلى: ' || NEW.status || '.'
    END;
    PERFORM app_private.enqueue_platform_notification(
      NEW.auth_user_id,'graduate_membership_status',v_title,v_body,
      'graduate-v2.html','graduate_membership_request',NEW.id
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION app_private.notify_subscription_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_recipient record;
  v_body text;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status
     AND OLD.payment_status IS NOT DISTINCT FROM NEW.payment_status
     AND OLD.ends_at IS NOT DISTINCT FROM NEW.ends_at THEN
    RETURN NEW;
  END IF;
  v_body := 'تم تحديث اشتراك المؤسسة. الحالة: ' || NEW.status ||
    '، حالة السداد: ' || NEW.payment_status ||
    CASE WHEN NEW.ends_at IS NOT NULL THEN '، تاريخ الانتهاء: ' || NEW.ends_at::date::text ELSE '' END || '.';
  FOR v_recipient IN
    SELECT i.auth_user_id AS user_id
    FROM public.institutions i
    WHERE i.id = NEW.institution_id AND i.auth_user_id IS NOT NULL
    UNION
    SELECT iu.auth_user_id
    FROM public.institution_users iu
    WHERE iu.institution_id = NEW.institution_id
      AND iu.status = 'active'
      AND iu.role IN ('owner','manager')
  LOOP
    PERFORM app_private.enqueue_platform_notification(
      v_recipient.user_id,'institution_subscription_update','تحديث اشتراك المؤسسة',v_body,
      'institution.html','subscription',NEW.id
    );
  END LOOP;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION app_private.notify_job_application_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_company_user_id uuid;
  v_graduate_user_id uuid;
  v_job_title text;
  v_company_name text;
BEGIN
  SELECT c.auth_user_id, j.title, j.company_display_name
    INTO v_company_user_id, v_job_title, v_company_name
  FROM public.job_announcements j
  LEFT JOIN public.companies c ON c.id = j.company_id
  WHERE j.id = NEW.job_id;

  IF TG_OP = 'INSERT' THEN
    PERFORM app_private.enqueue_platform_notification(
      v_company_user_id,'job_application_new','طلب توظيف جديد',
      'وصل طلب جديد للتقديم على وظيفة ' || COALESCE(v_job_title,'معلنة') || '.',
      'company.html','job_application',NEW.id
    );
  ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
    SELECT gp.auth_user_id INTO v_graduate_user_id
    FROM public.alumni_profiles ap
    JOIN public.graduate_profiles gp ON gp.id = ap.legacy_graduate_profile_id
    WHERE ap.id = NEW.alumni_id;
    PERFORM app_private.enqueue_platform_notification(
      v_graduate_user_id,'job_application_status','تحديث طلب التوظيف',
      'تم تحديث حالة طلبك لوظيفة ' || COALESCE(v_job_title,'معلنة') ||
        ' لدى ' || COALESCE(v_company_name,'الشركة') || ' إلى: ' || NEW.status || '.',
      'graduate-v2.html','job_application',NEW.id
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION app_private.notify_institution_subscription_or_session()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_recipient record;
  v_title text;
  v_body text;
  v_entity_id uuid;
  v_institution_id uuid;
BEGIN
  IF TG_TABLE_NAME = 'institution_course_sessions' THEN
    v_institution_id := NEW.institution_id;
    v_entity_id := NEW.id;
    v_title := 'تمت إضافة جلسة تدريبية';
    v_body := 'تمت إضافة جلسة جديدة: ' || COALESCE(NEW.title,'جلسة تدريبية') ||
      ' بتاريخ ' || NEW.session_date::text ||
      CASE WHEN NEW.starts_at IS NOT NULL THEN ' الساعة ' || NEW.starts_at::text ELSE '' END || '.';
  ELSE
    RETURN NEW;
  END IF;

  FOR v_recipient IN
    SELECT i.auth_user_id AS user_id
    FROM public.institutions i
    WHERE i.id = v_institution_id AND i.auth_user_id IS NOT NULL
    UNION
    SELECT iu.auth_user_id
    FROM public.institution_users iu
    WHERE iu.institution_id = v_institution_id
      AND iu.status = 'active'
      AND iu.role IN ('owner','manager')
  LOOP
    PERFORM app_private.enqueue_platform_notification(
      v_recipient.user_id,'training_session_created',v_title,v_body,
      'institution.html','training_session',v_entity_id
    );
  END LOOP;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION app_private.notify_admin_new_institution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_admin record;
BEGIN
  IF NEW.status = 'pending' THEN
    FOR v_admin IN
      SELECT pa.auth_user_id
      FROM public.platform_admins pa
      WHERE pa.status = 'active'
    LOOP
      PERFORM app_private.enqueue_platform_notification(
        v_admin.auth_user_id,'institution_registration_new','طلب مؤسسة جديد',
        'تم استلام طلب تسجيل مؤسسة جديد ويحتاج إلى المراجعة.',
        'admin.html','institution',NEW.id
      );
    END LOOP;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION app_private.notify_admin_new_graduate_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_admin record;
BEGIN
  IF NEW.status = 'pending' THEN
    FOR v_admin IN
      SELECT pa.auth_user_id
      FROM public.platform_admins pa
      WHERE pa.status = 'active'
    LOOP
      PERFORM app_private.enqueue_platform_notification(
        v_admin.auth_user_id,'graduate_registration_new','طلب خريج جديد',
        'تم استلام طلب انضمام خريج جديد ويحتاج إلى المراجعة.',
        'admin.html','graduate_access_request',NEW.id
      );
    END LOOP;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_platform_notify_marketplace_application ON public.training_marketplace_applications;
CREATE TRIGGER trg_platform_notify_marketplace_application
AFTER INSERT OR UPDATE OF status ON public.training_marketplace_applications
FOR EACH ROW EXECUTE FUNCTION app_private.notify_marketplace_application_event();

DROP TRIGGER IF EXISTS trg_platform_notify_graduate_membership ON public.graduate_membership_requests;
CREATE TRIGGER trg_platform_notify_graduate_membership
AFTER UPDATE OF status ON public.graduate_membership_requests
FOR EACH ROW EXECUTE FUNCTION app_private.notify_graduate_membership_event();

DROP TRIGGER IF EXISTS trg_platform_notify_subscription ON public.subscriptions;
CREATE TRIGGER trg_platform_notify_subscription
AFTER UPDATE OF status, payment_status, ends_at ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION app_private.notify_subscription_event();

DROP TRIGGER IF EXISTS trg_platform_notify_job_application ON public.job_applications;
CREATE TRIGGER trg_platform_notify_job_application
AFTER INSERT OR UPDATE OF status ON public.job_applications
FOR EACH ROW EXECUTE FUNCTION app_private.notify_job_application_event();

DROP TRIGGER IF EXISTS trg_platform_notify_institution_registration ON public.institutions;
CREATE TRIGGER trg_platform_notify_institution_registration
AFTER INSERT ON public.institutions
FOR EACH ROW EXECUTE FUNCTION app_private.notify_admin_new_institution();

DROP TRIGGER IF EXISTS trg_platform_notify_graduate_registration ON public.graduate_access_requests;
CREATE TRIGGER trg_platform_notify_graduate_registration
AFTER INSERT ON public.graduate_access_requests
FOR EACH ROW EXECUTE FUNCTION app_private.notify_admin_new_graduate_request();

DROP TRIGGER IF EXISTS trg_platform_notify_training_session ON public.institution_course_sessions;
CREATE TRIGGER trg_platform_notify_training_session
AFTER INSERT ON public.institution_course_sessions
FOR EACH ROW EXECUTE FUNCTION app_private.notify_institution_subscription_or_session();

COMMENT ON TABLE public.platform_notifications IS
'Unified in-app notification inbox and opt-in email queue. Notifications are scoped to one auth user.';
COMMENT ON TABLE public.platform_notification_preferences IS
'Per-user notification preferences. In-app is enabled by default; email is opt-in.';
