-- Manage academic reference lists from the platform admin panel
begin;

create table if not exists public.academic_degrees (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.academic_degrees(name) values
('دبلوم'),('دبلوم عالي'),('بكالوريوس'),('ليسانس'),('ماجستير'),
('دكتوراه'),('دكتوراه مهنية'),('زمالة'),('أخرى')
on conflict(name) do nothing;

alter table public.academic_degrees enable row level security;
drop policy if exists academic_degrees_admin_read on public.academic_degrees;
create policy academic_degrees_admin_read on public.academic_degrees
for select to authenticated using (public.is_platform_admin());
grant select on public.academic_degrees to authenticated;

create or replace function public.admin_manage_academic_reference(
  p_list text,
  p_action text,
  p_id uuid default null,
  p_name text default null,
  p_active boolean default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_id uuid;
  v_name text := nullif(trim(p_name),'');
  v_active boolean;
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'NOT_ALLOWED';
  end if;
  if p_list not in ('universities','faculties','degrees') then
    raise exception 'INVALID_REFERENCE_LIST';
  end if;
  if p_action not in ('add','rename','set_active') then
    raise exception 'INVALID_ACTION';
  end if;

  if p_action in ('add','rename') and (v_name is null or length(v_name)>180) then
    raise exception 'INVALID_NAME';
  end if;

  if p_list='universities' then
    if p_action='add' then
      insert into public.academic_universities(name) values(v_name) returning id into v_id;
    elsif p_action='rename' then
      update public.academic_universities set name=v_name where id=p_id returning id into v_id;
    else
      update public.academic_universities set is_active=p_active where id=p_id returning id,is_active into v_id,v_active;
    end if;
  elsif p_list='faculties' then
    if p_action='add' then
      insert into public.academic_faculties(name) values(v_name) returning id into v_id;
    elsif p_action='rename' then
      update public.academic_faculties set name=v_name where id=p_id returning id into v_id;
    else
      update public.academic_faculties set is_active=p_active where id=p_id returning id,is_active into v_id,v_active;
    end if;
  else
    if p_action='add' then
      insert into public.academic_degrees(name) values(v_name) returning id into v_id;
    elsif p_action='rename' then
      update public.academic_degrees set name=v_name where id=p_id returning id into v_id;
    else
      update public.academic_degrees set is_active=p_active where id=p_id returning id,is_active into v_id,v_active;
    end if;
  end if;

  if v_id is null then raise exception 'REFERENCE_NOT_FOUND'; end if;
  insert into public.activity_log(action,details,actor_id,actor_type,target_type,target_id)
  values('manage_academic_reference',p_action||' '||p_list||': '||coalesce(v_name,p_id::text),
    auth.uid(),'admin','academic_reference',v_id);
  return jsonb_build_object('success',true,'id',v_id,'name',v_name,'is_active',v_active);
end;
$function$;

revoke all on function public.admin_manage_academic_reference(text,text,uuid,text,boolean) from public, anon;
grant execute on function public.admin_manage_academic_reference(text,text,uuid,text,boolean) to authenticated;

commit;
