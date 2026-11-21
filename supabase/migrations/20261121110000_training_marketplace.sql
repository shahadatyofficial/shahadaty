-- Public training marketplace with graduate applications and institution review.
-- Existing courses and course runs remain private unless a manager explicitly publishes a run.

ALTER TABLE public.institution_course_runs
  ADD COLUMN IF NOT EXISTS is_publicly_listed boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS public_description text,
  ADD COLUMN IF NOT EXISTS price_amount numeric(10,2),
  ADD COLUMN IF NOT EXISTS currency_code text NOT NULL DEFAULT 'EGP',
  ADD COLUMN IF NOT EXISTS delivery_mode text NOT NULL DEFAULT 'onsite',
  ADD COLUMN IF NOT EXISTS registration_deadline date;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.institution_course_runs'::regclass
      AND conname = 'institution_course_runs_price_nonnegative'
  ) THEN
    ALTER TABLE public.institution_course_runs
      ADD CONSTRAINT institution_course_runs_price_nonnegative
      CHECK (price_amount IS NULL OR price_amount >= 0);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.institution_course_runs'::regclass
      AND conname = 'institution_course_runs_delivery_mode_valid'
  ) THEN
    ALTER TABLE public.institution_course_runs
      ADD CONSTRAINT institution_course_runs_delivery_mode_valid
      CHECK (delivery_mode IN ('onsite','online','hybrid'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS institution_course_runs_public_marketplace_idx
  ON public.institution_course_runs (start_date, institution_id)
  WHERE is_publicly_listed IS TRUE AND status IN ('open','in_progress');

CREATE TABLE IF NOT EXISTS public.training_marketplace_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_run_id uuid NOT NULL REFERENCES public.institution_course_runs(id) ON DELETE CASCADE,
  institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES public.institution_branches(id) ON DELETE SET NULL,
  graduate_profile_id uuid NOT NULL REFERENCES public.graduate_profiles(id) ON DELETE CASCADE,
  auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  applicant_message text,
  contact_sharing_consent boolean NOT NULL DEFAULT false,
  contact_sharing_consented_at timestamptz,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','accepted','rejected','withdrawn')),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT training_marketplace_contact_consent_required
    CHECK (contact_sharing_consent IS TRUE AND contact_sharing_consented_at IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS training_marketplace_one_active_application_idx
  ON public.training_marketplace_applications (course_run_id, graduate_profile_id)
  WHERE status IN ('pending','accepted');
CREATE INDEX IF NOT EXISTS training_marketplace_institution_status_idx
  ON public.training_marketplace_applications (institution_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS training_marketplace_graduate_created_idx
  ON public.training_marketplace_applications (auth_user_id, created_at DESC);

ALTER TABLE public.training_marketplace_applications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS training_marketplace_applications_select_scoped ON public.training_marketplace_applications;
CREATE POLICY training_marketplace_applications_select_scoped
  ON public.training_marketplace_applications
  FOR SELECT TO authenticated
  USING (
    auth_user_id = (SELECT auth.uid())
    OR public.institution_has_permission(institution_id, 'courses.view', branch_id)
  );

REVOKE ALL ON TABLE public.training_marketplace_applications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.training_marketplace_applications TO authenticated;

CREATE OR REPLACE FUNCTION public.get_public_training_marketplace(
  p_query text DEFAULT NULL,
  p_governorate text DEFAULT NULL,
  p_delivery_mode text DEFAULT NULL,
  p_limit integer DEFAULT 60
)
RETURNS TABLE (
  course_run_id uuid,
  course_id uuid,
  institution_id uuid,
  institution_name text,
  institution_logo_url text,
  governorate text,
  center text,
  branch_name text,
  course_name text,
  specialization text,
  duration text,
  run_name text,
  public_description text,
  start_date date,
  end_date date,
  capacity integer,
  price_amount numeric,
  currency_code text,
  delivery_mode text,
  registration_deadline date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    r.id,
    c.id,
    i.id,
    i.name,
    pp.logo_url,
    COALESCE(b.governorate, i.governorate),
    i.center,
    b.name,
    c.name,
    c.specialization,
    c.duration,
    r.run_name,
    r.public_description,
    r.start_date,
    r.end_date,
    r.capacity,
    r.price_amount,
    r.currency_code,
    r.delivery_mode,
    r.registration_deadline
  FROM public.institution_course_runs r
  JOIN public.institution_courses c ON c.id = r.course_id AND c.institution_id = r.institution_id
  JOIN public.institutions i ON i.id = r.institution_id AND i.status = 'approved'
  JOIN public.institution_public_profiles pp
    ON pp.institution_id = i.id AND pp.status = 'approved' AND pp.show_courses IS TRUE
  LEFT JOIN public.institution_branches b
    ON b.id = r.branch_id AND b.institution_id = r.institution_id AND b.is_active IS TRUE
  WHERE r.is_publicly_listed IS TRUE
    AND r.status IN ('open','in_progress')
    AND c.is_active IS TRUE
    AND (r.registration_deadline IS NULL OR r.registration_deadline >= CURRENT_DATE)
    AND (NULLIF(BTRIM(p_query),'') IS NULL OR
      (c.name ILIKE '%' || BTRIM(p_query) || '%'
       OR COALESCE(c.specialization,'') ILIKE '%' || BTRIM(p_query) || '%'
       OR COALESCE(r.public_description,'') ILIKE '%' || BTRIM(p_query) || '%'
       OR i.name ILIKE '%' || BTRIM(p_query) || '%'))
    AND (NULLIF(BTRIM(p_governorate),'') IS NULL OR
      COALESCE(b.governorate, i.governorate, '') ILIKE '%' || BTRIM(p_governorate) || '%')
    AND (NULLIF(BTRIM(p_delivery_mode),'') IS NULL OR r.delivery_mode = p_delivery_mode)
  ORDER BY r.start_date ASC NULLS LAST, r.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit,60),100));
$function$;

CREATE OR REPLACE FUNCTION public.submit_training_marketplace_application(
  p_course_run_id uuid,
  p_applicant_message text DEFAULT NULL,
  p_contact_sharing_consent boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_graduate_id uuid;
  v_institution_id uuid;
  v_branch_id uuid;
  v_capacity integer;
  v_enrolled integer;
  v_application_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF p_contact_sharing_consent IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTACT_SHARING_CONSENT_REQUIRED';
  END IF;

  SELECT gp.id INTO v_graduate_id
  FROM public.graduate_profiles gp
  WHERE gp.auth_user_id = v_user_id
  ORDER BY gp.created_at DESC
  LIMIT 1;
  IF v_graduate_id IS NULL THEN
    RAISE EXCEPTION 'GRADUATE_PROFILE_REQUIRED';
  END IF;

  SELECT r.institution_id, r.branch_id, r.capacity
    INTO v_institution_id, v_branch_id, v_capacity
  FROM public.institution_course_runs r
  JOIN public.institution_courses c ON c.id = r.course_id AND c.institution_id = r.institution_id
  JOIN public.institutions i ON i.id = r.institution_id AND i.status = 'approved'
  JOIN public.institution_public_profiles pp
    ON pp.institution_id = i.id AND pp.status = 'approved' AND pp.show_courses IS TRUE
  WHERE r.id = p_course_run_id
    AND r.is_publicly_listed IS TRUE
    AND r.status IN ('open','in_progress')
    AND c.is_active IS TRUE
    AND (r.registration_deadline IS NULL OR r.registration_deadline >= CURRENT_DATE)
  FOR UPDATE OF r;
  IF v_institution_id IS NULL THEN
    RAISE EXCEPTION 'COURSE_NOT_AVAILABLE';
  END IF;

  SELECT COUNT(*) INTO v_accepted
  FROM public.training_marketplace_applications a
  WHERE a.course_run_id = p_course_run_id AND a.status = 'accepted';
  IF v_capacity IS NOT NULL AND v_accepted >= v_capacity THEN
    RAISE EXCEPTION 'COURSE_CAPACITY_REACHED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.training_marketplace_applications a
    WHERE a.course_run_id = p_course_run_id
      AND a.graduate_profile_id = v_graduate_id
      AND a.status IN ('pending','accepted')
  ) THEN
    RAISE EXCEPTION 'APPLICATION_ALREADY_EXISTS';
  END IF;

  INSERT INTO public.training_marketplace_applications (
    course_run_id, institution_id, branch_id, graduate_profile_id,
    auth_user_id, applicant_message, contact_sharing_consent,
    contact_sharing_consented_at
  ) VALUES (
    p_course_run_id, v_institution_id, v_branch_id, v_graduate_id,
    v_user_id, LEFT(NULLIF(BTRIM(p_applicant_message),''),2000),
    true, now()
  )
  RETURNING id INTO v_application_id;

  RETURN v_application_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'APPLICATION_ALREADY_EXISTS';
END;
$function$;

CREATE OR REPLACE FUNCTION public.graduate_list_my_training_applications(p_limit integer DEFAULT 50)
RETURNS TABLE (
  application_id uuid,
  status text,
  applicant_message text,
  created_at timestamptz,
  reviewed_at timestamptz,
  course_name text,
  run_name text,
  institution_name text,
  governorate text,
  start_date date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT a.id, a.status, a.applicant_message, a.created_at, a.reviewed_at,
         c.name, r.run_name, i.name, COALESCE(b.governorate,i.governorate), r.start_date
  FROM public.training_marketplace_applications a
  JOIN public.institution_course_runs r ON r.id = a.course_run_id
  JOIN public.institution_courses c ON c.id = r.course_id
  JOIN public.institutions i ON i.id = a.institution_id
  LEFT JOIN public.institution_branches b ON b.id = a.branch_id
  WHERE a.auth_user_id = auth.uid()
  ORDER BY a.created_at DESC
  LIMIT GREATEST(1,LEAST(COALESCE(p_limit,50),100));
$function$;

CREATE OR REPLACE FUNCTION public.institution_list_training_marketplace_applications(p_limit integer DEFAULT 100)
RETURNS TABLE (
  application_id uuid,
  course_run_id uuid,
  status text,
  applicant_message text,
  created_at timestamptz,
  reviewed_at timestamptz,
  graduate_name text,
  graduate_phone text,
  graduate_email text,
  course_name text,
  run_name text,
  branch_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT a.id, a.course_run_id, a.status, a.applicant_message, a.created_at, a.reviewed_at,
         g.full_name, CASE WHEN a.contact_sharing_consent THEN g.phone END,
         CASE WHEN a.contact_sharing_consent THEN g.email END,
         c.name, r.run_name, b.name
  FROM public.training_marketplace_applications a
  JOIN public.graduate_profiles g ON g.id = a.graduate_profile_id
  JOIN public.institution_course_runs r ON r.id = a.course_run_id
  JOIN public.institution_courses c ON c.id = r.course_id
  LEFT JOIN public.institution_branches b ON b.id = a.branch_id
  WHERE public.institution_has_permission(a.institution_id, 'courses.manage', a.branch_id)
  ORDER BY a.created_at DESC
  LIMIT GREATEST(1,LEAST(COALESCE(p_limit,100),200));
$function$;

CREATE OR REPLACE FUNCTION public.institution_review_training_marketplace_application(
  p_application_id uuid,
  p_status text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_application public.training_marketplace_applications%ROWTYPE;
  v_graduate public.graduate_profiles%ROWTYPE;
  v_capacity integer;
  v_accepted integer;
  v_course_id uuid;
  v_trainee_id uuid;
BEGIN
  IF p_status NOT IN ('accepted','rejected') THEN
    RAISE EXCEPTION 'INVALID_APPLICATION_STATUS';
  END IF;

  SELECT * INTO v_application
  FROM public.training_marketplace_applications
  WHERE id = p_application_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'APPLICATION_NOT_FOUND';
  END IF;
  IF NOT public.institution_has_permission(
    v_application.institution_id, 'courses.manage', v_application.branch_id
  ) THEN
    RAISE EXCEPTION 'NOT_ALLOWED';
  END IF;
  IF v_application.status <> 'pending' THEN
    RAISE EXCEPTION 'APPLICATION_ALREADY_REVIEWED';
  END IF;

  IF p_status = 'accepted' THEN
    SELECT r.capacity, r.course_id INTO v_capacity, v_course_id
    FROM public.institution_course_runs r
    JOIN public.institution_courses c ON c.id = r.course_id AND c.institution_id = r.institution_id
    JOIN public.institutions i ON i.id = r.institution_id AND i.status = 'approved'
    JOIN public.institution_public_profiles pp
      ON pp.institution_id = i.id AND pp.status = 'approved' AND pp.show_courses IS TRUE
    WHERE r.id = v_application.course_run_id
      AND r.is_publicly_listed IS TRUE
      AND r.status IN ('open','in_progress')
      AND c.is_active IS TRUE
    FOR UPDATE OF r;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'COURSE_NOT_AVAILABLE';
    END IF;

    SELECT * INTO v_graduate
    FROM public.graduate_profiles
    WHERE id = v_application.graduate_profile_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'GRADUATE_PROFILE_NOT_FOUND';
    END IF;

    SELECT t.id INTO v_trainee_id
    FROM public.institution_trainees t
    WHERE t.institution_id = v_application.institution_id
      AND t.status = 'active'
      AND (
        (v_graduate.phone IS NOT NULL AND t.phone = v_graduate.phone)
        OR (v_graduate.email IS NOT NULL AND lower(t.email) = lower(v_graduate.email))
      )
    ORDER BY
      CASE WHEN v_graduate.phone IS NOT NULL AND t.phone = v_graduate.phone THEN 0 ELSE 1 END,
      t.created_at DESC
    LIMIT 1;

    IF v_trainee_id IS NULL THEN
      INSERT INTO public.institution_trainees (
        institution_id, branch_id, full_name, phone, email, governorate,
        status, created_by, notes
      ) VALUES (
        v_application.institution_id, v_application.branch_id,
        v_graduate.full_name, v_graduate.phone, v_graduate.email,
        v_graduate.governorate, 'active', auth.uid(),
        'تم التسجيل من سوق الدورات. رقم الطلب: ' || v_application.id::text
      )
      RETURNING id INTO v_trainee_id;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.institution_enrollments e
      WHERE e.institution_id = v_application.institution_id
        AND e.course_run_id = v_application.course_run_id
        AND e.trainee_id = v_trainee_id
    ) THEN
      SELECT COUNT(*) INTO v_enrolled
      FROM public.institution_enrollments e
      WHERE e.course_run_id = v_application.course_run_id
        AND e.status NOT IN ('cancelled','withdrawn');
      IF v_capacity IS NOT NULL AND v_enrolled >= v_capacity THEN
        RAISE EXCEPTION 'COURSE_CAPACITY_REACHED';
      END IF;

      INSERT INTO public.institution_enrollments (
        institution_id, course_run_id, course_id, trainee_id, status,
        enrolled_at, notes
      ) VALUES (
        v_application.institution_id, v_application.course_run_id,
        v_course_id, v_trainee_id, 'enrolled', now(),
        'تم القيد بعد قبول طلب سوق الدورات: ' || v_application.id::text
      );
    END IF;
  END IF;

  UPDATE public.training_marketplace_applications
  SET status = p_status, reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  WHERE id = p_application_id;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_public_training_marketplace(text,text,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_training_marketplace(text,text,text,integer) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_training_marketplace_application(uuid,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_training_marketplace_application(uuid,text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.graduate_list_my_training_applications(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.graduate_list_my_training_applications(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.institution_list_training_marketplace_applications(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.institution_list_training_marketplace_applications(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.institution_review_training_marketplace_application(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.institution_review_training_marketplace_application(uuid,text) TO authenticated;

COMMENT ON FUNCTION public.get_public_training_marketplace(text,text,text,integer) IS
'Public marketplace endpoint. Returns only published courses from approved institutions with an approved public profile.';
COMMENT ON FUNCTION public.submit_training_marketplace_application(uuid,text,boolean) IS
'Creates a course application for the signed-in graduate and requires explicit consent to share contact details with the selected institution.';
