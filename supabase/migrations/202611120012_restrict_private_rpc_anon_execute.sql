-- Remove anonymous EXECUTE access from RPCs that are private or admin-only.
-- The admin page runs as an authenticated user; graduate certificates require sign-in.
revoke all on function public.admin_list_institutions(text) from public, anon;
grant execute on function public.admin_list_institutions(text) to authenticated;

revoke all on function public.graduate_my_certificates() from public, anon;
grant execute on function public.graduate_my_certificates() to authenticated;

-- Trigger-only maintenance function: callers do not need direct EXECUTE permission.
revoke all on function public.touch_support_conversation() from public, anon, authenticated;
