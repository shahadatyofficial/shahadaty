-- Restrict newly added privileged RPCs to signed-in users.
-- Public-facing ticker, directory search, stats and certificate verification RPCs remain public.
revoke execute on function public.admin_link_alumni_graduate(uuid,text) from anon, public;
revoke execute on function public.admin_link_company_user(uuid,text) from anon, public;
revoke execute on function public.company_can_access_alumni_document(text) from anon, public;
revoke execute on function public.company_get_approved_alumni_contact(uuid) from anon, public;
revoke execute on function public.current_alumni_profile_id() from anon, public;
revoke execute on function public.current_approved_company_id() from anon, public;
revoke execute on function public.current_approved_company_name() from anon, public;
revoke execute on function public.graduate_list_my_access_requests() from anon, public;
revoke execute on function public.is_approved_company(uuid) from anon, public;
revoke execute on function public.is_public_alumni_profile(uuid) from anon, public;
revoke execute on function public.respond_alumni_access_request(uuid,boolean) from anon, public;
revoke execute on function public.search_alumni_for_company(text,text,text,text,integer,text) from anon, public;

grant execute on function public.admin_link_alumni_graduate(uuid,text) to authenticated;
grant execute on function public.admin_link_company_user(uuid,text) to authenticated;
grant execute on function public.company_can_access_alumni_document(text) to authenticated;
grant execute on function public.company_get_approved_alumni_contact(uuid) to authenticated;
grant execute on function public.current_alumni_profile_id() to authenticated;
grant execute on function public.current_approved_company_id() to authenticated;
grant execute on function public.current_approved_company_name() to authenticated;
grant execute on function public.graduate_list_my_access_requests() to authenticated;
grant execute on function public.is_approved_company(uuid) to authenticated;
grant execute on function public.is_public_alumni_profile(uuid) to authenticated;
grant execute on function public.respond_alumni_access_request(uuid,boolean) to authenticated;
grant execute on function public.search_alumni_for_company(text,text,text,text,integer,text) to authenticated;
