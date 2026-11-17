-- Secure one-time graduate account claims initiated by an approved institution.
create table if not exists public.graduate_account_claims (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  trainee_id uuid not null references public.institution_trainees(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null default (now() + interval '7 days'),
  consumed_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists graduate_account_claims_active_trainee_idx
  on public.graduate_account_claims (trainee_id, created_at desc)
  where consumed_at is null;
alter table public.graduate_account_claims enable row level security;
revoke all on public.graduate_account_claims from public, anon, authenticated;
grant select, insert, update, delete on public.graduate_account_claims to service_role;
comment on table public.graduate_account_claims is
  'Hashed, expiring, one-time tokens for a trainee to claim a graduate login; raw tokens are shown only once and never stored.';
