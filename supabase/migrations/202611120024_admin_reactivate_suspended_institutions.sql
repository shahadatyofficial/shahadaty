CREATE OR REPLACE FUNCTION public.admin_reactivate_institution(p_institution_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_i public.institutions%rowtype;
  v_sub public.subscriptions%rowtype;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'NOT_ALLOWED';
  END IF;

  SELECT * INTO v_i
  FROM public.institutions
  WHERE id = p_institution_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INSTITUTION_NOT_FOUND';
  END IF;
  IF v_i.status <> 'suspended' THEN
    RAISE EXCEPTION 'INSTITUTION_NOT_SUSPENDED';
  END IF;

  SELECT * INTO v_sub
  FROM public.subscriptions
  WHERE institution_id = p_institution_id
    AND status = 'suspended'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SUBSCRIPTION_NOT_FOUND';
  END IF;
  IF v_sub.ends_at IS NULL OR v_sub.ends_at <= now() THEN
    RAISE EXCEPTION 'SUBSCRIPTION_EXPIRED';
  END IF;
  IF coalesce(v_sub.amount, 0) > 0 AND v_sub.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'PAYMENT_REQUIRED';
  END IF;

  UPDATE public.subscriptions
  SET status = 'active', updated_at = now()
  WHERE id = v_sub.id;

  UPDATE public.institutions
  SET status = 'approved', rejection_reason = NULL, updated_at = now()
  WHERE id = p_institution_id;

  RETURN jsonb_build_object(
    'success', true,
    'institution_id', p_institution_id,
    'subscription_id', v_sub.id,
    'status', 'approved',
    'subscription_status', 'active'
  );
END;
$function$;
