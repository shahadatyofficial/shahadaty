-- Atomically update an employment mediation request and append its audit event.
-- The RPC checks platform-admin authorization and the expected current status.

CREATE OR REPLACE FUNCTION public.admin_update_employment_contact_request(
  p_request_id uuid,
  p_expected_status text,
  p_new_status text,
  p_admin_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_old_status text;
  v_actor_id uuid;
BEGIN
  v_actor_id := (SELECT auth.uid());

  IF v_actor_id IS NULL OR NOT COALESCE((SELECT public.is_platform_admin()), false) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE = '42501';
  END IF;

  IF p_new_status IS NULL OR p_new_status NOT IN (
    'new', 'reviewing', 'contacted_company', 'contacted_graduate',
    'interview_coordination', 'interviewed', 'hired',
    'closed_no_agreement', 'cancelled'
  ) THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = '22023';
  END IF;

  IF p_admin_notes IS NOT NULL AND length(p_admin_notes) > 5000 THEN
    RAISE EXCEPTION 'NOTES_TOO_LONG' USING ERRCODE = '22023';
  END IF;

  SELECT r.status INTO v_old_status
  FROM public.employment_contact_requests AS r
  WHERE r.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF p_expected_status IS NOT NULL AND v_old_status <> p_expected_status THEN
    RAISE EXCEPTION 'STATUS_CONFLICT' USING ERRCODE = '40001';
  END IF;

  UPDATE public.employment_contact_requests
  SET status = p_new_status,
      admin_notes = NULLIF(trim(p_admin_notes), ''),
      updated_at = now(),
      last_action_at = now()
  WHERE id = p_request_id;

  INSERT INTO public.employment_contact_request_events (
    request_id, actor_id, event_type, old_status, new_status, note
  )
  VALUES (
    p_request_id, v_actor_id, 'admin_update', v_old_status,
    p_new_status, NULLIF(trim(p_admin_notes), '')
  );

  RETURN jsonb_build_object(
    'request_id', p_request_id,
    'old_status', v_old_status,
    'new_status', p_new_status,
    'updated_at', now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_update_employment_contact_request(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_employment_contact_request(uuid, text, text, text) TO authenticated;
