-- Optimize row-level security auth.uid() evaluation and remove exact duplicate SELECT policies.
-- The removed policies were verified to have identical roles, commands and predicates
-- to the retained policy on the same table.

ALTER POLICY graduate_profiles_insert_own ON public.graduate_profiles
  WITH CHECK (auth_user_id = (SELECT auth.uid()));
ALTER POLICY graduate_profiles_select_own ON public.graduate_profiles
  USING (auth_user_id = (SELECT auth.uid()));
ALTER POLICY graduate_profiles_update_own ON public.graduate_profiles
  USING (auth_user_id = (SELECT auth.uid()))
  WITH CHECK (auth_user_id = (SELECT auth.uid()));

ALTER POLICY "approved companies create access requests" ON public.alumni_access_requests
  WITH CHECK (
    status = 'pending'
    AND requested_by = (SELECT auth.uid())
    AND company_id = current_approved_company_id()
    AND is_public_alumni_profile(alumni_id)
  );

-- Keep one canonical SELECT policy per table; these pairs were exact duplicates.
DROP POLICY IF EXISTS institutions_select_own ON public.institutions;
ALTER POLICY institutions_select_member ON public.institutions
  USING ((auth_user_id = (SELECT auth.uid())) OR is_institution_member(id));

DROP POLICY IF EXISTS institution_users_select_own ON public.institution_users;
ALTER POLICY institution_users_select_member ON public.institution_users
  USING (
    (auth_user_id = (SELECT auth.uid()))
    OR has_institution_role(institution_id, ARRAY['owner'::text, 'manager'::text])
  );

ALTER POLICY "registered graduates view approved jobs" ON public.job_announcements
  USING (
    status = 'approved'
    AND EXISTS (
      SELECT 1
      FROM public.graduate_profiles g
      WHERE g.auth_user_id = (SELECT auth.uid())
    )
  );
