DROP FUNCTION IF EXISTS pg_catalog.worker_create_schema(jobid bigint);
CREATE FUNCTION pg_catalog.worker_create_schema(jobid bigint, username text)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_create_schema$$;
COMMENT ON FUNCTION pg_catalog.worker_create_schema(bigint, text)
    IS 'create schema in remote node';
REVOKE ALL ON FUNCTION pg_catalog.worker_create_schema(bigint, text) FROM PUBLIC;
-- reserve UINT32_MAX (4294967295) for a special node
ALTER SEQUENCE pg_catalog.pg_dist_node_nodeid_seq MAXVALUE 4294967294;
