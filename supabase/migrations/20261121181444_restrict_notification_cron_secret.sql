-- The cron-secret verifier is an internal Edge Function helper, not a public API.
REVOKE ALL ON FUNCTION public.is_notification_cron_secret(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_notification_cron_secret(text) TO service_role;
