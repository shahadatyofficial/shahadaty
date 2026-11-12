CREATE OR REPLACE FUNCTION public.admin_confirm_subscription_payment(
  p_subscription_id uuid,
  p_payment_reference text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_sub public.subscriptions%rowtype;
  v_package public.packages%rowtype;
  v_expected_amount numeric(12,2);
  v_start timestamptz;
  v_end timestamptz;
  v_reference text;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'NOT_ALLOWED';
  END IF;

  v_reference := nullif(trim(p_payment_reference), '');
  IF v_reference IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_REFERENCE_REQUIRED';
  END IF;
  IF length(v_reference) > 200 THEN
    RAISE EXCEPTION 'PAYMENT_REFERENCE_TOO_LONG';
  END IF;

  SELECT * INTO v_sub
  FROM public.subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SUBSCRIPTION_NOT_FOUND';
  END IF;

  IF v_sub.status NOT IN ('pending', 'suspended', 'active') THEN
    RAISE EXCEPTION 'SUBSCRIPTION_NOT_CONFIRMABLE';
  END IF;
  IF v_sub.payment_status = 'paid' THEN
    RAISE EXCEPTION 'PAYMENT_ALREADY_CONFIRMED';
  END IF;
  IF v_sub.payment_status NOT IN ('unpaid', 'pending', 'failed') THEN
    RAISE EXCEPTION 'PAYMENT_STATUS_NOT_CONFIRMABLE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.institutions
    WHERE id = v_sub.institution_id AND status = 'approved'
  ) THEN
    RAISE EXCEPTION 'INSTITUTION_NOT_APPROVED';
  END IF;

  SELECT * INTO v_package
  FROM public.packages
  WHERE id = v_sub.package_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PACKAGE_NOT_FOUND';
  END IF;
  IF v_sub.billing_cycle NOT IN ('monthly', 'yearly') THEN
    RAISE EXCEPTION 'INVALID_BILLING_CYCLE';
  END IF;

  v_expected_amount := CASE
    WHEN v_sub.billing_cycle = 'yearly' THEN coalesce(v_package.price_yearly, 0)
    ELSE coalesce(v_package.price_monthly, 0)
  END;

  IF v_expected_amount <= 0 THEN
    RAISE EXCEPTION 'PAYMENT_NOT_REQUIRED';
  END IF;
  IF abs(coalesce(v_sub.amount, 0) - v_expected_amount) > 0.009 THEN
    RAISE EXCEPTION 'SUBSCRIPTION_AMOUNT_MISMATCH';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.subscriptions other_sub
    WHERE other_sub.id <> p_subscription_id
      AND lower(trim(coalesce(other_sub.payment_reference, ''))) = lower(v_reference)
  ) THEN
    RAISE EXCEPTION 'PAYMENT_REFERENCE_ALREADY_USED';
  END IF;

  v_start := greatest(now(), coalesce(v_sub.ends_at, now()));
  v_end := CASE
    WHEN v_sub.billing_cycle = 'yearly' THEN v_start + interval '1 year'
    ELSE v_start + interval '1 month'
  END;

  UPDATE public.subscriptions
  SET payment_status = 'paid',
      payment_reference = v_reference,
      status = 'active',
      starts_at = coalesce(starts_at, now()),
      ends_at = v_end,
      updated_at = now()
  WHERE id = p_subscription_id;

  RETURN jsonb_build_object(
    'success', true,
    'subscription_id', p_subscription_id,
    'status', 'active',
    'payment_status', 'paid',
    'ends_at', v_end
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_activate_subscription(p_subscription_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_sub public.subscriptions%rowtype;
  v_package public.packages%rowtype;
  v_expected_amount numeric(12,2);
  v_start timestamptz;
  v_end timestamptz;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'NOT_ALLOWED';
  END IF;

  SELECT * INTO v_sub
  FROM public.subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SUBSCRIPTION_NOT_FOUND';
  END IF;
  IF v_sub.status NOT IN ('pending', 'suspended') THEN
    RAISE EXCEPTION 'SUBSCRIPTION_NOT_ACTIVATABLE';
  END IF;
  IF v_sub.payment_status <> 'paid'
     OR nullif(trim(coalesce(v_sub.payment_reference, '')), '') IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_CONFIRMED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.institutions
    WHERE id = v_sub.institution_id AND status = 'approved'
  ) THEN
    RAISE EXCEPTION 'INSTITUTION_NOT_APPROVED';
  END IF;

  SELECT * INTO v_package
  FROM public.packages
  WHERE id = v_sub.package_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PACKAGE_NOT_FOUND';
  END IF;

  IF v_sub.billing_cycle NOT IN ('monthly', 'yearly') THEN
    RAISE EXCEPTION 'INVALID_BILLING_CYCLE';
  END IF;

  v_expected_amount := CASE
    WHEN v_sub.billing_cycle = 'yearly' THEN coalesce(v_package.price_yearly, 0)
    ELSE coalesce(v_package.price_monthly, 0)
  END;
  IF v_expected_amount <= 0
     OR abs(coalesce(v_sub.amount, 0) - v_expected_amount) > 0.009 THEN
    RAISE EXCEPTION 'SUBSCRIPTION_AMOUNT_MISMATCH';
  END IF;

  v_start := greatest(now(), coalesce(v_sub.ends_at, now()));
  v_end := CASE
    WHEN v_sub.billing_cycle = 'yearly' THEN v_start + interval '1 year'
    ELSE v_start + interval '1 month'
  END;

  UPDATE public.subscriptions
  SET status = 'active',
      starts_at = coalesce(starts_at, now()),
      ends_at = v_end,
      updated_at = now()
  WHERE id = p_subscription_id;

  RETURN jsonb_build_object(
    'success', true,
    'subscription_id', p_subscription_id,
    'status', 'active',
    'ends_at', v_end
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_confirm_subscription_payment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_confirm_subscription_payment(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_activate_subscription(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activate_subscription(uuid) TO authenticated;

-- Enforce reference uniqueness at the database level to prevent concurrent reuse.
CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_payment_reference_unique_idx
ON public.subscriptions (lower(btrim(payment_reference)))
WHERE payment_reference IS NOT NULL AND btrim(payment_reference) <> '';
