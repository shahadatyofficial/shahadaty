-- Live support chat for Shahadaty.
-- Visitor identity is a high-entropy browser token; only its SHA-256 hash is stored.
create table if not exists public.support_conversations (
  id uuid primary key default gen_random_uuid(),
  visitor_token_hash text not null unique,
  visitor_name text,
  visitor_email text,
  status text not null default 'open' check (status in ('open','closed')),
  last_message_preview text,
  last_message_at timestamptz not null default now(),
  unread_admin_count integer not null default 0,
  unread_visitor_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.support_conversations(id) on delete cascade,
  sender_role text not null check (sender_role in ('visitor','admin')),
  sender_user_id uuid references auth.users(id) on delete set null,
  body text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists support_conversations_status_last_message_idx
  on public.support_conversations(status,last_message_at desc);
create index if not exists support_messages_conversation_created_idx
  on public.support_messages(conversation_id,created_at);

alter table public.support_conversations enable row level security;
alter table public.support_messages enable row level security;

-- Access only through the narrowly-scoped RPCs below.
revoke all on public.support_conversations from public, anon, authenticated;
revoke all on public.support_messages from public, anon, authenticated;

create or replace function public.support_chat_start(
  p_token text,p_name text,p_email text,p_message text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_hash text;
  v_conversation public.support_conversations%rowtype;
  v_created boolean:=false;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'INVALID_CHAT_TOKEN'; end if;
  if p_message is null or length(trim(p_message)) not between 1 and 2000 then raise exception 'INVALID_MESSAGE'; end if;
  if p_email is not null and length(trim(p_email))>254 then raise exception 'INVALID_EMAIL'; end if;
  if p_name is not null and length(trim(p_name))>100 then raise exception 'INVALID_NAME'; end if;
  v_hash:=encode(sha256(convert_to(p_token,'UTF8')),'hex');

  select * into v_conversation from public.support_conversations
  where visitor_token_hash=v_hash for update;

  if not found then
    insert into public.support_conversations(visitor_token_hash,visitor_name,visitor_email)
    values(v_hash,nullif(trim(p_name),''),nullif(trim(p_email),''))
    returning * into v_conversation;
    v_created:=true;
    insert into public.support_messages(conversation_id,sender_role,body)
    values(v_conversation.id,'visitor',trim(p_message));
    update public.support_conversations set last_message_preview=left(trim(p_message),180),
      last_message_at=now(),unread_admin_count=1,updated_at=now()
    where id=v_conversation.id returning * into v_conversation;
  elsif v_conversation.status='closed' then
    update public.support_conversations set status='open',updated_at=now()
    where id=v_conversation.id returning * into v_conversation;
  end if;

  return jsonb_build_object('conversation_id',v_conversation.id,'status',v_conversation.status,'created',v_created);
end;
$$;

create or replace function public.support_chat_send(p_token text,p_message text)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_id uuid; v_status text;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'INVALID_CHAT_TOKEN'; end if;
  if p_message is null or length(trim(p_message)) not between 1 and 2000 then raise exception 'INVALID_MESSAGE'; end if;
  select id,status into v_id,v_status from public.support_conversations
  where visitor_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') for update;
  if not found then raise exception 'CHAT_NOT_FOUND'; end if;
  if v_status='closed' then
    update public.support_conversations set status='open',updated_at=now() where id=v_id;
  end if;
  if (select count(*) from public.support_messages
      where conversation_id=v_id and sender_role='visitor' and created_at>now()-interval '1 minute')>=15 then
    raise exception 'CHAT_RATE_LIMIT';
  end if;
  insert into public.support_messages(conversation_id,sender_role,body)
  values(v_id,'visitor',trim(p_message));
  update public.support_conversations set last_message_preview=left(trim(p_message),180),
    last_message_at=now(),unread_admin_count=unread_admin_count+1,updated_at=now()
  where id=v_id;
  return jsonb_build_object('success',true);
end;
$$;

create or replace function public.support_chat_messages(p_token text)
returns table(id uuid,sender_role text,body text,created_at timestamptz)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_id uuid;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'INVALID_CHAT_TOKEN'; end if;
  select c.id into v_id from public.support_conversations c
  where c.visitor_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
  if not found then raise exception 'CHAT_NOT_FOUND'; end if;
  update public.support_messages set read_at=now()
  where conversation_id=v_id and sender_role='admin' and read_at is null;
  update public.support_conversations set unread_visitor_count=0,updated_at=now() where id=v_id;
  return query select m.id,m.sender_role,m.body,m.created_at
  from public.support_messages m where m.conversation_id=v_id
  order by m.created_at desc limit 100;
end;
$$;

create or replace function public.admin_support_chat_list(p_status text default 'open')
returns table(
  id uuid,visitor_name text,visitor_email text,status text,last_message_preview text,
  last_message_at timestamptz,unread_admin_count integer,created_at timestamptz
)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  return query select c.id,c.visitor_name,c.visitor_email,c.status,c.last_message_preview,
    c.last_message_at,c.unread_admin_count,c.created_at
  from public.support_conversations c
  where p_status is null or p_status='all' or c.status=p_status
  order by c.last_message_at desc limit 300;
end;
$$;

create or replace function public.admin_support_chat_messages(p_conversation_id uuid)
returns table(id uuid,sender_role text,body text,created_at timestamptz,read_at timestamptz)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  update public.support_messages set read_at=now()
  where conversation_id=p_conversation_id and sender_role='visitor' and read_at is null;
  update public.support_conversations set unread_admin_count=0,updated_at=now()
  where id=p_conversation_id;
  return query select m.id,m.sender_role,m.body,m.created_at,m.read_at
  from public.support_messages m where m.conversation_id=p_conversation_id
  order by m.created_at asc limit 300;
end;
$$;

create or replace function public.admin_support_chat_reply(p_conversation_id uuid,p_message text)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_status text;
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_message is null or length(trim(p_message)) not between 1 and 2000 then raise exception 'INVALID_MESSAGE'; end if;
  select status into v_status from public.support_conversations where id=p_conversation_id for update;
  if not found then raise exception 'CHAT_NOT_FOUND'; end if;
  if v_status='closed' then raise exception 'CHAT_CLOSED'; end if;
  insert into public.support_messages(conversation_id,sender_role,sender_user_id,body)
  values(p_conversation_id,'admin',auth.uid(),trim(p_message));
  update public.support_conversations set last_message_preview=left(trim(p_message),180),
    last_message_at=now(),unread_visitor_count=unread_visitor_count+1,updated_at=now()
  where id=p_conversation_id;
  return jsonb_build_object('success',true);
end;
$$;

create or replace function public.admin_support_chat_set_status(p_conversation_id uuid,p_status text)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if not public.is_platform_admin() then raise exception 'NOT_ALLOWED'; end if;
  if p_status not in ('open','closed') then raise exception 'INVALID_STATUS'; end if;
  update public.support_conversations set status=p_status,updated_at=now()
  where id=p_conversation_id;
  if not found then raise exception 'CHAT_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'status',p_status);
end;
$$;

revoke all on function public.support_chat_start(text,text,text,text) from public;
revoke all on function public.support_chat_send(text,text) from public;
revoke all on function public.support_chat_messages(text) from public;
revoke all on function public.admin_support_chat_list(text) from public,anon;
revoke all on function public.admin_support_chat_messages(uuid) from public,anon;
revoke all on function public.admin_support_chat_reply(uuid,text) from public,anon;
revoke all on function public.admin_support_chat_set_status(uuid,text) from public,anon;

grant execute on function public.support_chat_start(text,text,text,text) to anon,authenticated;
grant execute on function public.support_chat_send(text,text) to anon,authenticated;
grant execute on function public.support_chat_messages(text) to anon,authenticated;
grant execute on function public.admin_support_chat_list(text) to authenticated;
grant execute on function public.admin_support_chat_messages(uuid) to authenticated;
grant execute on function public.admin_support_chat_reply(uuid,text) to authenticated;
grant execute on function public.admin_support_chat_set_status(uuid,text) to authenticated;
