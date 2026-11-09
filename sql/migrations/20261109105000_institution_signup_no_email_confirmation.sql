-- Rate-limit public institution account provisioning without exposing service credentials.
create schema if not exists private;

revoke all on schema private from public, anon, authenticated;

create table if not exists private.institution_signup_attempts (
  id bigint generated always as identity primary key,
  identifier_hash text not null,
  attempted_at timestamptz not null default now()
);

create index if not exists institution_signup_attempts_identifier_time_idx
  on private.institution_signup_attempts (identifier_hash, attempted_at desc);

revoke all on table private.institution_signup_attempts from public, anon, authenticated;
grant usage on schema private to service_role;
grant select, insert, delete on table private.institution_signup_attempts to service_role;

create or replace function public.consume_institution_signup_limit(p_identifier_hash text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, private
as $$
declare
  v_role text;
  v_attempts integer;
begin
  v_role := coalesce(auth.jwt() ->> 'role', '');
  if v_role <> 'service_role' then
    raise exception 'not_allowed';
  end if;

  delete from private.institution_signup_attempts
  where attempted_at < now() - interval '24 hours';

  select count(*)::integer
    into v_attempts
  from private.institution_signup_attempts
  where identifier_hash = p_identifier_hash
    and attempted_at > now() - interval '15 minutes';

  if v_attempts >= 5 then
    return false;
  end if;

  insert into private.institution_signup_attempts(identifier_hash)
  values (p_identifier_hash);

  return true;
end;
$$;

revoke all on function public.consume_institution_signup_limit(text) from public, anon, authenticated;
grant execute on function public.consume_institution_signup_limit(text) to service_role;
