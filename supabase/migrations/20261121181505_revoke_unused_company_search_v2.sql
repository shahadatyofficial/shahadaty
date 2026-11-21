-- v2 was superseded by search_alumni_for_company_v3 before the new portal is released.
REVOKE ALL ON FUNCTION public.search_alumni_for_company_v2(text,text,text,text,integer,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_alumni_for_company_v2(text,text,text,text,integer,text,text) TO service_role;
