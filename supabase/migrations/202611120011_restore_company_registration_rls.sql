-- Restore the strict company self-registration RLS policy after switching
-- the initial SECURITY DEFINER experiment to direct RLS-protected inserts.
create policy companies_public_insert
on public.companies
for insert
to anon, authenticated
with check (
  length(btrim(company_name)) between 2 and 200
  and status = 'pending'
  and coalesce(search_credits, 0) = 0
  and (contact_name is null or length(btrim(contact_name)) between 2 and 100)
  and (contact_email is null or length(btrim(contact_email)) <= 254)
  and (contact_phone is null or length(btrim(contact_phone)) between 7 and 32)
  and (
    ((select auth.uid()) is null and auth_user_id is null)
    or auth_user_id = (select auth.uid())
  )
);
