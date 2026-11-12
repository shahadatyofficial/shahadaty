-- Allow an institution owner/manager to correct legal details and resubmit a rejected application.
create or replace function public.institution_resubmit_rejected_application(
  p_institution_id uuid,
  p_commercial_registration_number text,
  p_tax_card_number text,
  p_owner_name text,
  p_manager_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_institution public.institutions%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if coalesce(trim(p_commercial_registration_number), '') = ''
     or coalesce(trim(p_tax_card_number), '') = ''
     or coalesce(trim(p_owner_name), '') = ''
     or coalesce(trim(p_manager_name), '') = '' then
    raise exception 'REQUIRED_LEGAL_DATA_MISSING';
  end if;

  select i.* into v_institution
  from public.institutions i
  where i.id = p_institution_id
    and (
      i.auth_user_id = v_uid
      or exists (
        select 1
        from public.institution_users iu
        where iu.institution_id = i.id
          and iu.auth_user_id = v_uid
          and iu.status = 'active'
          and iu.role in ('owner', 'manager')
      )
    )
  for update;

  if not found then
    raise exception 'NOT_ALLOWED';
  end if;

  if v_institution.status <> 'rejected' then
    raise exception 'INSTITUTION_NOT_REJECTED';
  end if;

  update public.institutions
  set commercial_registration_number = trim(p_commercial_registration_number),
      tax_card_number = trim(p_tax_card_number),
      owner_name = trim(p_owner_name),
      manager_name = trim(p_manager_name),
      status = 'pending',
      rejection_reason = null,
      updated_at = now()
  where id = p_institution_id;

  insert into public.activity_log (
    institution_id, action, details, actor_id, actor_type, target_type, target_id
  ) values (
    p_institution_id,
    'institution_application_resubmitted',
    'تم تصحيح البيانات القانونية وإعادة إرسال طلب الاعتماد',
    v_uid,
    'institution',
    'institution',
    p_institution_id
  );

  return jsonb_build_object('success', true, 'institution_id', p_institution_id, 'status', 'pending');
end;
$$;

revoke all on function public.institution_resubmit_rejected_application(uuid,text,text,text,text) from public, anon;
grant execute on function public.institution_resubmit_rejected_application(uuid,text,text,text,text) to authenticated;
