-- Hide expired approved job announcements from graduate accounts at the database boundary.
-- The UI also labels expired listings, but RLS is the authoritative access control.

DROP POLICY IF EXISTS "registered graduates view approved jobs" ON public.job_announcements;

CREATE POLICY "registered graduates view current approved jobs"
ON public.job_announcements
FOR SELECT
TO authenticated
USING (
  status = 'approved'
  AND (expires_at IS NULL OR expires_at > now())
  AND EXISTS (
    SELECT 1
    FROM public.graduate_profiles AS g
    WHERE g.auth_user_id = (SELECT auth.uid())
  )
);
