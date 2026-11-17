-- Add structured trainer records and dated training sessions without changing existing enrollment or attendance rows.
create table if not exists public.institution_trainers (
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 branch_id uuid null references public.institution_branches(id) on delete set null,
 full_name text not null check (length(btrim(full_name)) between 2 and 200),
 phone text null,
 email text null,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint institution_trainers_id_institution_unique unique (id,institution_id)
);
create index if not exists institution_trainers_institution_branch_idx on public.institution_trainers(institution_id,branch_id,is_active);
alter table public.institution_course_runs add column if not exists trainer_id uuid null;
alter table public.institution_course_runs add constraint institution_course_runs_trainer_fk foreign key (trainer_id,institution_id) references public.institution_trainers(id,institution_id) on delete no action;
create table if not exists public.institution_course_sessions (
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 course_run_id uuid not null references public.institution_course_runs(id) on delete cascade,
 trainer_id uuid null,
 title text null,
 session_date date not null,
 starts_at time null,
 ends_at time null,
 location text null,
 status text not null default 'planned' check (status in ('planned','completed','cancelled')),
 notes text null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint institution_course_sessions_time_check check (starts_at is null or ends_at is null or ends_at > starts_at),
 constraint institution_course_sessions_trainer_fk foreign key (trainer_id,institution_id) references public.institution_trainers(id,institution_id) on delete no action
);
create index if not exists institution_course_sessions_institution_date_idx on public.institution_course_sessions(institution_id,session_date,status);
create index if not exists institution_course_sessions_run_date_idx on public.institution_course_sessions(course_run_id,session_date);
create index if not exists institution_course_runs_trainer_id_idx on public.institution_course_runs(trainer_id);
alter table public.institution_trainers enable row level security;
alter table public.institution_course_sessions enable row level security;
grant select,insert,update on public.institution_trainers to authenticated;
grant select,insert,update on public.institution_course_sessions to authenticated;
create policy institution_trainers_select on public.institution_trainers for select to authenticated using (institution_has_permission(institution_id,'courses.view',branch_id));
create policy institution_trainers_insert on public.institution_trainers for insert to authenticated with check (institution_has_permission(institution_id,'courses.manage',branch_id));
create policy institution_trainers_update on public.institution_trainers for update to authenticated using (institution_has_permission(institution_id,'courses.manage',branch_id)) with check (institution_has_permission(institution_id,'courses.manage',branch_id));
create policy institution_course_sessions_select on public.institution_course_sessions for select to authenticated using (
 exists (select 1 from public.institution_course_runs r where r.id=course_run_id and r.institution_id=institution_course_sessions.institution_id and institution_has_permission(institution_course_sessions.institution_id,'courses.view',r.branch_id))
);
create policy institution_course_sessions_insert on public.institution_course_sessions for insert to authenticated with check (
 exists (select 1 from public.institution_course_runs r where r.id=course_run_id and r.institution_id=institution_course_sessions.institution_id and institution_has_permission(institution_course_sessions.institution_id,'courses.manage',r.branch_id))
 and (trainer_id is null or exists(select 1 from public.institution_trainers t where t.id=trainer_id and t.institution_id=institution_course_sessions.institution_id and (t.branch_id is null or t.branch_id=(select r.branch_id from public.institution_course_runs r where r.id=course_run_id))))
);
create policy institution_course_sessions_update on public.institution_course_sessions for update to authenticated using (
 exists (select 1 from public.institution_course_runs r where r.id=course_run_id and r.institution_id=institution_course_sessions.institution_id and institution_has_permission(institution_course_sessions.institution_id,'courses.manage',r.branch_id))
) with check (
 exists (select 1 from public.institution_course_runs r where r.id=course_run_id and r.institution_id=institution_course_sessions.institution_id and institution_has_permission(institution_course_sessions.institution_id,'courses.manage',r.branch_id))
);
