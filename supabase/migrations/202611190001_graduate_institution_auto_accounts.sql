-- Separate direct graduate applications from institution-issued graduate accounts.
alter table public.graduate_access_requests
  add column if not exists origin text not null default 'direct',
  add column if not exists institution_id uuid null references public.institutions(id) on delete set null,
  add column if not exists certificate_id uuid null references public.certificates(id) on delete set null;
alter table public.graduate_access_requests
  drop constraint if exists graduate_access_requests_origin_check;
alter table public.graduate_access_requests
  add constraint graduate_access_requests_origin_check check (origin in ('direct','institution'));
create unique index if not exists graduate_access_requests_certificate_uidx
  on public.graduate_access_requests(certificate_id) where certificate_id is not null;
create index if not exists graduate_access_requests_origin_status_created_idx
  on public.graduate_access_requests(origin,status,created_at desc);

alter table public.graduate_profiles
  add column if not exists account_origin text not null default 'direct',
  add column if not exists institution_id uuid null references public.institutions(id) on delete set null,
  add column if not exists source_certificate_id uuid null references public.certificates(id) on delete set null;
alter table public.graduate_profiles
  drop constraint if exists graduate_profiles_account_origin_check;
alter table public.graduate_profiles
  add constraint graduate_profiles_account_origin_check check (account_origin in ('direct','institution'));
create index if not exists graduate_profiles_institution_id_idx
  on public.graduate_profiles(institution_id) where institution_id is not null;

comment on column public.graduate_access_requests.origin is 'direct = self-registration; institution = account created from an institution-issued certificate.';
comment on column public.graduate_profiles.account_origin is 'Separates direct platform graduates from institution-issued graduate accounts.';
