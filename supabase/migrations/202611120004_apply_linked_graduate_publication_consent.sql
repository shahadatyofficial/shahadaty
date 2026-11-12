-- Apply previously recorded graduate consent when an administrator links the profile later.
create or replace function public.apply_linked_graduate_publication_consent()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.legacy_graduate_profile_id is not null then
    select coalesce(gp.publication_consent, false),
           case when gp.publication_consent is true
             then coalesce(gp.publication_consent_at, now()) else null end
      into new.publication_consent, new.publication_consent_at
      from public.graduate_profiles gp
     where gp.id = new.legacy_graduate_profile_id;

    if not found then
      new.publication_consent := false;
      new.publication_consent_at := null;
    end if;

    new.visibility_status := case when new.publication_consent is true
      then 'public' else 'hidden' end;
  end if;
  return new;
end;
$$;

revoke all on function public.apply_linked_graduate_publication_consent() from public, anon, authenticated;

drop trigger if exists trg_apply_linked_graduate_publication_consent on public.alumni_profiles;
create trigger trg_apply_linked_graduate_publication_consent
before insert or update of legacy_graduate_profile_id
on public.alumni_profiles
for each row execute function public.apply_linked_graduate_publication_consent();
