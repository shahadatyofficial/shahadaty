create table if not exists public.graduate_access_requests (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null,
  phone text not null,
  governorate text,
  center text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint graduate_access_requests_email_unique unique (email),
  constraint graduate_access_requests_phone_unique unique (phone)
);
create index if not exists graduate_access_requests_status_created_idx on public.graduate_access_requests(status, created_at desc);
create table if not exists public.graduate_publication_consents (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  graduate_profile_id uuid references public.graduate_profiles(id) on delete set null,
  consent boolean not null,
  consent_text text not null,
  consent_version text not null default '2026-11-v1',
  scope text not null default 'graduate_profile_public_listing',
  source text not null default 'graduate_portal',
  created_at timestamptz not null default now()
);
create index if not exists graduate_publication_consents_user_created_idx on public.graduate_publication_consents(auth_user_id, created_at desc);
alter table public.graduate_access_requests enable row level security;
alter table public.graduate_publication_consents enable row level security;
drop policy if exists graduate_access_requests_admin_manage on public.graduate_access_requests;
create policy graduate_access_requests_admin_manage on public.graduate_access_requests for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());
drop policy if exists graduate_publication_consents_admin_select on public.graduate_publication_consents;
create policy graduate_publication_consents_admin_select on public.graduate_publication_consents for select to authenticated using (public.is_platform_admin());
drop policy if exists graduate_publication_consents_owner_select on public.graduate_publication_consents;
create policy graduate_publication_consents_owner_select on public.graduate_publication_consents for select to authenticated using (auth_user_id = (select auth.uid()));
drop policy if exists graduate_publication_consents_owner_insert on public.graduate_publication_consents;
create policy graduate_publication_consents_owner_insert on public.graduate_publication_consents for insert to authenticated with check (auth_user_id = (select auth.uid()));
grant select, insert on public.graduate_publication_consents to authenticated;
grant select, insert, update on public.graduate_access_requests to authenticated;
