ALTER TABLE public.platform_notifications
  ADD COLUMN IF NOT EXISTS email_processing_at timestamptz;

ALTER TABLE public.platform_notifications
  DROP CONSTRAINT IF EXISTS platform_notifications_email_status_check;

ALTER TABLE public.platform_notifications
  ADD CONSTRAINT platform_notifications_email_status_check
  CHECK (email_status IN ('not_requested','queued','processing','sent','failed','not_configured'));

CREATE INDEX IF NOT EXISTS platform_notifications_email_processing_idx
  ON public.platform_notifications (email_processing_at)
  WHERE email_status = 'processing';
