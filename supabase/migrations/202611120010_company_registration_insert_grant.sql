-- Allow company onboarding requests through RLS, without a public SECURITY DEFINER endpoint.
-- The insert policy from 202611120008_secure_company_self_registration restricts:
-- pending status, zero credits, bounded inputs, and auth_user_id = auth.uid() (or NULL for anon).
revoke all on function public.submit_company_registration(text,text,text,text) from public, anon, authenticated;
drop function if exists public.submit_company_registration(text,text,text,text);
grant insert on table public.companies to anon, authenticated;
