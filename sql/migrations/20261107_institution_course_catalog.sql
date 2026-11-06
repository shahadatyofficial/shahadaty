-- Institution course catalog.
-- Safe to apply only after the platform's isolated test database is available.
create table if not exists public.institution_courses (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 160),
  specialization text,
  duration text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists institution_courses_name_unique_idx
  on public.institution_courses(institution_id, lower(trim(name)));
create index if not exists institution_courses_institution_active_idx
  on public.institution_courses(institution_id,is_active);
alter table public.institution_courses enable row level security;
drop policy if exists institution_courses_select_member on public.institution_courses;
create policy institution_courses_select_member on public.institution_courses
  for select to authenticated using (public.is_institution_member(institution_id));
drop policy if exists institution_courses_insert_manager on public.institution_courses;
create policy institution_courses_insert_manager on public.institution_courses
  for insert to authenticated with check (public.has_institution_role(institution_id,array['owner','manager']));
drop policy if exists institution_courses_update_manager on public.institution_courses;
create policy institution_courses_update_manager on public.institution_courses
  for update to authenticated using (public.has_institution_role(institution_id,array['owner','manager']))
  with check (public.has_institution_role(institution_id,array['owner','manager']));
drop policy if exists institution_courses_delete_manager on public.institution_courses;
create policy institution_courses_delete_manager on public.institution_courses
  for delete to authenticated using (public.has_institution_role(institution_id,array['owner','manager']));
grant select,insert,update,delete on public.institution_courses to authenticated;
