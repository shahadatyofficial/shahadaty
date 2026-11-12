-- Add covering indexes for foreign keys reported by Supabase Performance Advisor.
-- These indexes support joins and avoid child-table scans when referenced rows change.
CREATE INDEX IF NOT EXISTS idx_accreditation_requests_institution_id
  ON public.accreditation_requests (institution_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_institution_id
  ON public.activity_log (institution_id);
CREATE INDEX IF NOT EXISTS idx_alumni_access_requests_admin_decided_by
  ON public.alumni_access_requests (admin_decided_by);
CREATE INDEX IF NOT EXISTS idx_alumni_access_requests_requested_by
  ON public.alumni_access_requests (requested_by);
CREATE INDEX IF NOT EXISTS idx_alumni_notifications_related_job_id
  ON public.alumni_notifications (related_job_id);
CREATE INDEX IF NOT EXISTS idx_alumni_notifications_related_training_id
  ON public.alumni_notifications (related_training_id);
CREATE INDEX IF NOT EXISTS idx_alumni_profiles_created_by
  ON public.alumni_profiles (created_by);
CREATE INDEX IF NOT EXISTS idx_alumni_profiles_updated_by
  ON public.alumni_profiles (updated_by);
CREATE INDEX IF NOT EXISTS idx_alumni_qualifications_certificate_id
  ON public.alumni_qualifications (certificate_id);
CREATE INDEX IF NOT EXISTS idx_alumni_skills_alumni_id
  ON public.alumni_skills (alumni_id);
CREATE INDEX IF NOT EXISTS idx_institutions_package_id
  ON public.institutions (package_id);
CREATE INDEX IF NOT EXISTS idx_job_announcements_company_id
  ON public.job_announcements (company_id);
CREATE INDEX IF NOT EXISTS idx_job_announcements_created_by
  ON public.job_announcements (created_by);
CREATE INDEX IF NOT EXISTS idx_job_applications_alumni_id
  ON public.job_applications (alumni_id);
CREATE INDEX IF NOT EXISTS idx_training_announcements_created_by
  ON public.training_announcements (created_by);
