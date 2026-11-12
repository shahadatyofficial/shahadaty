REVOKE ALL ON FUNCTION public.admin_reactivate_institution(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reactivate_institution(uuid) TO authenticated;
