drop policy if exists institution_public_profiles_member_select on public.institution_public_profiles;
create policy institution_public_profiles_member_select on public.institution_public_profiles for select to authenticated using(public.has_institution_role(institution_id,array['owner','manager']::text[]));
drop policy if exists institution_public_profiles_member_insert on public.institution_public_profiles;
create policy institution_public_profiles_member_insert on public.institution_public_profiles for insert to authenticated with check(public.has_institution_role(institution_id,array['owner','manager']::text[]));
drop policy if exists institution_public_profiles_member_update on public.institution_public_profiles;
create policy institution_public_profiles_member_update on public.institution_public_profiles for update to authenticated using(public.has_institution_role(institution_id,array['owner','manager']::text[])) with check(public.has_institution_role(institution_id,array['owner','manager']::text[]));
