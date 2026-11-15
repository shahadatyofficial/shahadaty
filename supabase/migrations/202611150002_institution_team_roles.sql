-- Align institution membership roles with the permission matrix and invitation flow.
-- Preserve the legacy 'staff' role for existing memberships.
alter table public.institution_users
  drop constraint if exists institution_users_role_check;

alter table public.institution_users
  add constraint institution_users_role_check
  check (role in (
    'owner',
    'manager',
    'staff',
    'training_manager',
    'registrar',
    'certificate_issuer',
    'branch_manager',
    'viewer'
  ));

-- Ensure the constraint is validated against all existing rows before this migration succeeds.
