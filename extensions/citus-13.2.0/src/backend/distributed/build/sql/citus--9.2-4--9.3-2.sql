-- citus--9.2-4--9.3-2
-- bump version to 9.3-2
-- we use the citus_extradata_container function as a range table entry in the query part
-- executed on the coordinator. Now that we are letting this query be planned by the
-- postgres planner we need to be able to pass column names and type information with this
-- function. This requires the change of the prototype of the function and add a return
-- type. Changing the return type of the function requires we drop the function first.
DROP FUNCTION citus_extradata_container(INTERNAL);
CREATE OR REPLACE FUNCTION citus_extradata_container(INTERNAL)
    RETURNS SETOF record
    LANGUAGE C
AS 'MODULE_PATHNAME', $$citus_extradata_container$$;
COMMENT ON FUNCTION pg_catalog.citus_extradata_container(INTERNAL)
    IS 'placeholder function to store additional data in postgres node trees';
CREATE OR REPLACE FUNCTION pg_catalog.update_distributed_table_colocation(table_name regclass, colocate_with text)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$update_distributed_table_colocation$$;
COMMENT ON FUNCTION pg_catalog.update_distributed_table_colocation(table_name regclass, colocate_with text)
    IS 'updates colocation of a table';
CREATE FUNCTION pg_catalog.replicate_reference_tables()
  RETURNS VOID
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$replicate_reference_tables$$;
COMMENT ON FUNCTION pg_catalog.replicate_reference_tables()
  IS 'replicate reference tables to all nodes';
REVOKE ALL ON FUNCTION pg_catalog.replicate_reference_tables() FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_remote_connection_stats(
 OUT hostname text,
 OUT port int,
 OUT database_name text,
 OUT connection_count_to_node int)
RETURNS SETOF RECORD
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_remote_connection_stats$$;
COMMENT ON FUNCTION pg_catalog.citus_remote_connection_stats(
 OUT hostname text,
 OUT port int,
 OUT database_name text,
 OUT connection_count_to_node int)
     IS 'returns statistics about remote connections';
REVOKE ALL ON FUNCTION pg_catalog.citus_remote_connection_stats(
  OUT hostname text,
  OUT port int,
  OUT database_name text,
  OUT connection_count_to_node int)
FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.worker_create_or_alter_role(
    role_name text,
    create_role_utility_query text,
    alter_role_utility_query text)
    RETURNS BOOL
    LANGUAGE C
AS 'MODULE_PATHNAME', $$worker_create_or_alter_role$$;
COMMENT ON FUNCTION pg_catalog.worker_create_or_alter_role(
    role_name text,
    create_role_utility_query text,
    alter_role_utility_query text)
    IS 'runs the create role query, if the role doesn''t exists, runs the alter role query if it does';
CREATE OR REPLACE FUNCTION truncate_local_data_after_distributing_table(function_name regclass)
  RETURNS void
  LANGUAGE C CALLED ON NULL INPUT
  AS 'MODULE_PATHNAME', $$truncate_local_data_after_distributing_table$$;
COMMENT ON FUNCTION truncate_local_data_after_distributing_table(function_name regclass)
  IS 'truncates local records of a distributed table';
-- add citus extension owner as a distributed object, if not already in there
INSERT INTO citus.pg_dist_object SELECT
  (SELECT oid FROM pg_class WHERE relname = 'pg_authid') AS oid,
  (SELECT oid FROM pg_authid WHERE rolname = current_user) as objid,
  0 as objsubid
ON CONFLICT DO NOTHING;
