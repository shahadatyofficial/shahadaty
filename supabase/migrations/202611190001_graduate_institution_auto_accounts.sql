-- Separate institution-issued graduate accounts from direct graduate applications.
-- Additive only: existing rows remain direct applications.
alter table public.graduate_access_requests
  add column if not exists account_origin text not null default 'direct',
  add column if not exists institution_id uuid references public.institutions(id) on delete set null,
  add column if not exists certificate_id uuid references public.certificates(id) on delete set null;

alter table public.graduate_profiles
  add column if not exists account_origin text not null default 'direct',
  add column if not exists institution_id uuid references public.institutions(id) on delete set null,
  add column if not exists source_certificate_id uuid references public.certificates(id) on delete set null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='graduate_access_requests_account_origin_check' and conrelid='public.graduate_access_requests'::regclass) then
    alter table public.graduate_access_requests add constraint graduate_access_requests_account_origin_check check (account_origin in ('direct','institution'));
  end if;
  if not exists (select 1 from pg_constraint where conname='graduate_profiles_account_origin_check' and conrelid='public.graduate_profiles'::regclass) then
    alter table public.graduate_profiles add constraint graduate_profiles_account_origin_check check (account_origin in ('direct','institution'));
  end if;
end $$;

create unique index if not exists graduate_access_requests_certificate_id_uidx
  on public.graduate_access_requests(certificate_id) where certificate_id is not null;
create index if not exists graduate_access_requests_origin_status_created_idx
  on public.graduate_access_requests(account_origin,status,created_at desc);
create index if not exists graduate_profiles_origin_institution_idx
  on public.graduate_profiles(account_origin,institution_id);
