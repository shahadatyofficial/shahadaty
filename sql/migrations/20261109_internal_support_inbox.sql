-- Internal visitor support inbox for Shahadaty
create table if not exists public.support_conversations (
  id uuid primary key,
  access_token uuid not null,
  visitor_name text not null check (char_length(btrim(visitor_name)) between 2 and 100),
  visitor_email text,
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.support_conversations(id) on delete cascade,
  sender text not null check (sender in ('visitor','admin')),
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists support_conversations_status_updated_idx on public.support_conversations(status,updated_at desc);
create index if not exists support_messages_conversation_created_idx on public.support_messages(conversation_id,created_at);
create index if not exists support_messages_unread_idx on public.support_messages(sender,read_at) where sender='visitor' and read_at is null;

alter table public.support_conversations enable row level security;
alter table public.support_messages enable row level security;
revoke all on public.support_conversations from public, anon, authenticated;
revoke all on public.support_messages from public, anon, authenticated;
grant insert on public.support_conversations to anon;
grant insert,select,update on public.support_conversations to authenticated;
grant insert,select,update on public.support_messages to authenticated;

drop policy if exists support_conversations_visitor_insert on public.support_conversations;
create policy support_conversations_visitor_insert on public.support_conversations
for insert to anon with check (status='open' and visitor_name=btrim(visitor_name));
drop policy if exists support_conversations_admin_select on public.support_conversations;
create policy support_conversations_admin_select on public.support_conversations
for select to authenticated using ((select public.is_platform_admin()));
drop policy if exists support_conversations_admin_update on public.support_conversations;
create policy support_conversations_admin_update on public.support_conversations
for update to authenticated using ((select public.is_platform_admin()))
with check ((select public.is_platform_admin()));

drop policy if exists support_messages_visitor_insert on public.support_messages;
create policy support_messages_visitor_insert on public.support_messages
for insert to anon with check (sender='visitor');
drop policy if exists support_messages_admin_select on public.support_messages;
create policy support_messages_admin_select on public.support_messages
for select to authenticated using ((select public.is_platform_admin()));
drop policy if exists support_messages_admin_insert on public.support_messages;
create policy support_messages_admin_insert on public.support_messages
for insert to authenticated with check (sender='admin' and (select public.is_platform_admin()));
drop policy if exists support_messages_admin_update on public.support_messages;
create policy support_messages_admin_update on public.support_messages
for update to authenticated using ((select public.is_platform_admin()))
with check ((select public.is_platform_admin()));

create or replace function public.get_visitor_support_messages(p_conversation_id uuid,p_access_token uuid)
returns table(id uuid,sender text,body text,created_at timestamptz)
language plpgsql stable security definer set search_path=public
as $fn$
begin
  if not exists(select 1 from public.support_conversations c where c.id=p_conversation_id and c.access_token=p_access_token) then
    raise exception 'SUPPORT_SESSION_INVALID';
  end if;
  return query
    select m.id,m.sender,m.body,m.created_at
    from public.support_messages m
    where m.conversation_id=p_conversation_id
    order by m.created_at asc limit 200;
end;
$fn$;
revoke all on function public.get_visitor_support_messages(uuid,uuid) from public;
grant execute on function public.get_visitor_support_messages(uuid,uuid) to anon,authenticated;

do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='support_messages') then
    execute 'alter publication supabase_realtime add table public.support_messages';
  end if;
end $$;
