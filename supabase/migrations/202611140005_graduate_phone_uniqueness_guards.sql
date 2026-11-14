create unique index if not exists graduate_profiles_phone_unique_idx
on public.graduate_profiles (phone)
where phone is not null;

create unique index if not exists graduate_access_requests_phone_active_unique_idx
on public.graduate_access_requests (phone)
where status in ('pending','approved');