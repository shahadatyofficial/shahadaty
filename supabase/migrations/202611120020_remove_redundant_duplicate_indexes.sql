-- Remove three duplicate indexes identified by Supabase Performance Advisor.
-- Keep the indexes currently used by query plans and the unique constraint.
DROP INDEX IF EXISTS public.certificates_institution_id_idx;
DROP INDEX IF EXISTS public.certificates_cert_number_unique_idx;
DROP INDEX IF EXISTS public.institution_documents_institution_id_idx;
