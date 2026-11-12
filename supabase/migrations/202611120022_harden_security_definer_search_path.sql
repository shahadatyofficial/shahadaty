-- Explicitly place pg_temp after public for every SECURITY DEFINER function
-- currently configured with search_path=public. PostgreSQL otherwise searches
-- the temporary schema first for relation/type names when pg_temp is omitted.
-- All application relations and project helper functions in these routines are
-- schema-qualified; this preserves behavior while preventing temp-object shadowing.
DO $migration$
DECLARE
  fn record;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=public']
  LOOP
    EXECUTE format(
      'ALTER FUNCTION %s SET search_path TO public, pg_temp',
      fn.signature
    );
  END LOOP;
END
$migration$;
