-- citus--10.0-1--10.0-2
--#include "../../columnar/sql/columnar--10.0-1--10.0-2.sql"
DO $check_columnar$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension AS e
             INNER JOIN pg_catalog.pg_depend AS d ON (d.refobjid = e.oid)
             INNER JOIN pg_catalog.pg_proc AS p ON (p.oid = d.objid)
             WHERE e.extname='citus_columnar' and p.proname = 'columnar_handler'
  ) THEN
-- columnar--10.0-1--10.0-2.sql
-- grant read access for columnar metadata tables to unprivileged user
GRANT USAGE ON SCHEMA columnar TO PUBLIC;
GRANT SELECT ON ALL tables IN SCHEMA columnar TO PUBLIC ;
  END IF;
END;
$check_columnar$;
GRANT SELECT ON public.citus_tables TO public;
