create table if not exists public.institution_public_profiles (
 institution_id uuid primary key references public.institutions(id) on delete cascade,
 description text not null default '', logo_url text, public_phone text, whatsapp text,
 public_email text, website_url text, show_courses boolean not null default true,
 status text not null default 'draft' check (status in ('draft','pending','approved','rejected')),
 rejection_reason text, submitted_at timestamptz, reviewed_at timestamptz, reviewed_by uuid,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists institution_public_profiles_status_idx on public.institution_public_profiles(status,updated_at desc);
alter table public.institution_public_profiles enable row level security;
grant select,insert,update on public.institution_public_profiles to authenticated;
grant select on public.institution_public_profiles to anon;
create policy institution_public_profiles_public_select on public.institution_public_profiles for select to anon,authenticated using(status='approved');
create policy institution_public_profiles_member_select on public.institution_public_profiles for select to authenticated using(institution_has_permission(institution_id,'branches.view') or institution_has_permission(institution_id,'team.manage'));
create policy institution_public_profiles_member_insert on public.institution_public_profiles for insert to authenticated with check(institution_has_permission(institution_id,'team.manage') or institution_has_permission(institution_id,'branches.manage'));
create policy institution_public_profiles_member_update on public.institution_public_profiles for update to authenticated using(institution_has_permission(institution_id,'team.manage') or institution_has_permission(institution_id,'branches.manage')) with check(institution_has_permission(institution_id,'team.manage') or institution_has_permission(institution_id,'branches.manage'));
create policy institution_public_profiles_admin_select on public.institution_public_profiles for select to authenticated using(exists(select 1 from public.platform_admins pa where pa.auth_user_id=(select auth.uid()) and pa.status='active'));
create policy institution_public_profiles_admin_update on public.institution_public_profiles for update to authenticated using(exists(select 1 from public.platform_admins pa where pa.auth_user_id=(select auth.uid()) and pa.status='active')) with check(exists(select 1 from public.platform_admins pa where pa.auth_user_id=(select auth.uid()) and pa.status='active'));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('institution-logos','institution-logos',true,2097152,array['image/png','image/jpeg','image/webp']) on conflict(id) do update set public=true,file_size_limit=2097152,allowed_mime_types=array['image/png','image/jpeg','image/webp'];
create policy institution_logos_member_upload on storage.objects for insert to authenticated with check(bucket_id='institution-logos' and exists(select 1 from public.institutions i where i.id::text=(storage.foldername(name))[1] and (i.auth_user_id=(select auth.uid()) or exists(select 1 from public.institution_users iu where iu.institution_id=i.id and iu.auth_user_id=(select auth.uid()) and iu.status='active' and iu.role in ('owner','manager')))));
create policy institution_logos_member_update on storage.objects for update to authenticated using(bucket_id='institution-logos' and exists(select 1 from public.institutions i where i.id::text=(storage.foldername(name))[1] and (i.auth_user_id=(select auth.uid()) or exists(select 1 from public.institution_users iu where iu.institution_id=i.id and iu.auth_user_id=(select auth.uid()) and iu.status='active' and iu.role in ('owner','manager'))))) with check(bucket_id='institution-logos' and exists(select 1 from public.institutions i where i.id::text=(storage.foldername(name))[1] and (i.auth_user_id=(select auth.uid()) or exists(select 1 from public.institution_users iu where iu.institution_id=i.id and iu.auth_user_id=(select auth.uid()) and iu.status='active' and iu.role in ('owner','manager')))));
create policy institution_logos_member_delete on storage.objects for delete to authenticated using(bucket_id='institution-logos' and exists(select 1 from public.institutions i where i.id::text=(storage.foldername(name))[1] and (i.auth_user_id=(select auth.uid()) or exists(select 1 from public.institution_users iu where iu.institution_id=i.id and iu.auth_user_id=(select auth.uid()) and iu.status='active' and iu.role in ('owner','manager')))));
create or replace function public.get_public_institution_directory()
returns table(institution_id uuid,institution_name text,institution_type text,governorate text,description text,logo_url text,public_phone text,whatsapp text,public_email text,website_url text,branches jsonb,courses jsonb)
language sql stable security definer set search_path=public,pg_temp as $$
 select i.id,i.name,coalesce(i.institution_type,i.inst_type,'مؤسسة تعليمية'),i.governorate,p.description,p.logo_url,
 coalesce(nullif(p.public_phone,''),i.contact_phone),p.whatsapp,coalesce(nullif(p.public_email,''),i.contact_email),p.website_url,
 coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'governorate',b.governorate,'address',b.address,'phone',b.phone) order by b.is_main desc,b.name) from public.institution_branches b where b.institution_id=i.id and b.is_active),'[]'::jsonb),
 case when p.show_courses then coalesce((select jsonb_agg(distinct jsonb_build_object('name',c.name,'specialization',c.specialization,'duration',c.duration) order by jsonb_build_object('name',c.name,'specialization',c.specialization,'duration',c.duration)) from public.institution_courses c where c.institution_id=i.id and c.is_active),'[]'::jsonb) else '[]'::jsonb end
 from public.institution_public_profiles p join public.institutions i on i.id=p.institution_id where p.status='approved' and i.status='approved' order by i.name;
$$;
revoke all on function public.get_public_institution_directory() from public;
grant execute on function public.get_public_institution_directory() to anon,authenticated;
