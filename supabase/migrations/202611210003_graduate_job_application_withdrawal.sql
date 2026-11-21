-- Allow a graduate to withdraw only their own still-active job application.
-- The function deliberately preserves the unique job/profile record to prevent duplicate applications.

CREATE OR REPLACE FUNCTION public.graduate_withdraw_job_application(
  p_application_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_alumni_id uuid;
  v_old_status text;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  v_alumni_id := public.current_alumni_profile_id();
  IF v_alumni_id IS NULL THEN
    RAISE EXCEPTION 'GRADUATE_PROFILE_NOT_LINKED' USING ERRCODE = 'P0002';
  END IF;

  SELECT a.status INTO v_old_status
  FROM public.job_applications AS a
  WHERE a.id = p_application_id
    AND a.alumni_id = v_alumni_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APPLICATION_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_old_status NOT IN ('submitted', 'reviewing', 'shortlisted') THEN
    RAISE EXCEPTION 'APPLICATION_CANNOT_BE_WITHDRAWN' USING ERRCODE = '22023';
  END IF;

  UPDATE public.job_applications
  SET status = 'withdrawn', updated_at = now()
  WHERE id = p_application_id AND alumni_id = v_alumni_id;

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'old_status', v_old_status,
    'new_status', 'withdrawn',
    'updated_at', now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.graduate_withdraw_job_application(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.graduate_withdraw_job_application(uuid) TO authenticated;
