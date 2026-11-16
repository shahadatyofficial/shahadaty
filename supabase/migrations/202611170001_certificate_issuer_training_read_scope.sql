-- Allow certificate issuers to inspect the minimum training context needed to issue certificates.
-- RLS continues to restrict rows to their assigned institution branches.
insert into public.institution_role_permissions (role, permission_key)
values
  ('certificate_issuer', 'trainees.view'),
  ('certificate_issuer', 'courses.view')
on conflict (role, permission_key) do nothing;
