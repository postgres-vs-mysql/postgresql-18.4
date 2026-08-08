ALTER TABLE pg_catalog.pg_dist_node ADD shouldhaveshards bool NOT NULL DEFAULT true;
COMMENT ON COLUMN pg_catalog.pg_dist_node.shouldhaveshards IS
    'indicates whether the node is eligible to contain data from distributed tables';
CREATE FUNCTION pg_catalog.master_set_node_property(
    nodename text,
    nodeport integer,
    property text,
    value boolean)
  RETURNS VOID
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', 'master_set_node_property';
COMMENT ON FUNCTION pg_catalog.master_set_node_property(
    nodename text,
    nodeport integer,
    property text,
    value boolean)
  IS 'set a property of a node in pg_dist_node';
REVOKE ALL ON FUNCTION pg_catalog.master_set_node_property(
    nodename text,
    nodeport integer,
    property text,
    value boolean)
  FROM PUBLIC;
CREATE FUNCTION pg_catalog.master_drain_node(
    nodename text,
    nodeport integer,
    shard_transfer_mode citus.shard_transfer_mode default 'auto')
  RETURNS VOID
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$master_drain_node$$;
COMMENT ON FUNCTION pg_catalog.master_drain_node(text,int,citus.shard_transfer_mode)
  IS 'mark a node to be drained of data and actually drain it as well';
REVOKE ALL ON FUNCTION pg_catalog.master_drain_node(text,int,citus.shard_transfer_mode) FROM PUBLIC;
CREATE FUNCTION pg_catalog.worker_create_schema(bigint)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_create_schema$$;
COMMENT ON FUNCTION pg_catalog.worker_create_schema(bigint)
    IS 'create schema in remote node';
REVOKE ALL ON FUNCTION pg_catalog.worker_create_schema(bigint) FROM PUBLIC;
CREATE FUNCTION pg_catalog.worker_repartition_cleanup(bigint)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_repartition_cleanup$$;
COMMENT ON FUNCTION pg_catalog.worker_repartition_cleanup(bigint)
    IS 'remove job in remote node';
REVOKE ALL ON FUNCTION pg_catalog.worker_repartition_cleanup(bigint) FROM PUBLIC;
-- rebalance_table_shards uses the shard rebalancer's C UDF functions to rebalance
-- shards of the given relation.
--
DROP FUNCTION pg_catalog.rebalance_table_shards;
CREATE OR REPLACE FUNCTION pg_catalog.rebalance_table_shards(
        relation regclass default NULL,
        threshold float4 default 0,
        max_shard_moves int default 1000000,
        excluded_shard_list bigint[] default '{}',
        shard_transfer_mode citus.shard_transfer_mode default 'auto',
        drain_only boolean default false)
    RETURNS VOID
    AS 'MODULE_PATHNAME'
    LANGUAGE C VOLATILE;
COMMENT ON FUNCTION pg_catalog.rebalance_table_shards(regclass, float4, int, bigint[], citus.shard_transfer_mode, boolean)
    IS 'rebalance the shards of the given table across the worker nodes (including colocated shards of other tables)';
-- get_rebalance_table_shards_plan shows the actual events that will be performed
-- if a rebalance operation will be performed with the same arguments, which allows users
-- to understand the impact of the change overall availability of the application and
-- network trafic.
--
DROP FUNCTION pg_catalog.get_rebalance_table_shards_plan;
CREATE OR REPLACE FUNCTION pg_catalog.get_rebalance_table_shards_plan(
        relation regclass default NULL,
        threshold float4 default 0,
        max_shard_moves int default 1000000,
        excluded_shard_list bigint[] default '{}',
        drain_only boolean default false)
    RETURNS TABLE (table_name regclass,
                   shardid bigint,
                   shard_size bigint,
                   sourcename text,
                   sourceport int,
                   targetname text,
                   targetport int)
    AS 'MODULE_PATHNAME'
    LANGUAGE C VOLATILE;
COMMENT ON FUNCTION pg_catalog.get_rebalance_table_shards_plan(regclass, float4, int, bigint[], boolean)
    IS 'returns the list of shard placement moves to be done on a rebalance operation';
-- Update the default groupId to -1
DROP FUNCTION master_add_node(text, integer, integer, noderole, name);
CREATE FUNCTION master_add_node(nodename text,
                                nodeport integer,
                                groupid integer default -1,
                                noderole noderole default 'primary',
                                nodecluster name default 'default')
  RETURNS INTEGER
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$master_add_node$$;
COMMENT ON FUNCTION master_add_node(nodename text, nodeport integer,
                                    groupid integer, noderole noderole, nodecluster name)
  IS 'add node to the cluster';
REVOKE ALL ON FUNCTION master_add_node(text,int,int,noderole,name) FROM PUBLIC;
-- Update the default groupId to -1
DROP FUNCTION master_add_inactive_node(text, integer, integer, noderole, name);
CREATE FUNCTION master_add_inactive_node(nodename text,
                                         nodeport integer,
                                         groupid integer default -1,
                                         noderole noderole default 'primary',
                                         nodecluster name default 'default')
  RETURNS INTEGER
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME',$$master_add_inactive_node$$;
COMMENT ON FUNCTION master_add_inactive_node(nodename text,nodeport integer,
                                             groupid integer, noderole noderole,
                                             nodecluster name)
  IS 'prepare node by adding it to pg_dist_node';
REVOKE ALL ON FUNCTION master_add_inactive_node(text,int,int,noderole,name) FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.alter_role_if_exists(
    role_name text,
    utility_query text)
    RETURNS BOOL
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$alter_role_if_exists$$;
COMMENT ON FUNCTION pg_catalog.alter_role_if_exists(
    role_name text,
    utility_query text)
    IS 'runs the utility query, if the role exists';
-- we don't maintain replication factor of reference tables anymore and just
-- use -1 instead.
UPDATE pg_dist_colocation SET replicationfactor = -1 WHERE distributioncolumntype = 0;
DO $proc$
BEGIN
-- PG16 has its own any_value, so only create it pre PG16.
IF substring(current_Setting('server_version'), '\d+')::int < 16 THEN
    EXECUTE $$
CREATE OR REPLACE FUNCTION pg_catalog.any_value_agg ( anyelement, anyelement )
RETURNS anyelement AS $agg$
        SELECT CASE WHEN $1 IS NULL THEN $2 ELSE $1 END;
$agg$ LANGUAGE SQL STABLE;
CREATE AGGREGATE pg_catalog.any_value (
        sfunc = pg_catalog.any_value_agg,
        combinefunc = pg_catalog.any_value_agg,
        basetype = anyelement,
        stype = anyelement
);
COMMENT ON AGGREGATE pg_catalog.any_value(anyelement) IS
    'Returns the value of any row in the group. It is mostly useful when you know there will be only 1 element.';
  $$;
END IF;
END $proc$;
-- drop function which was used for upgrading from 6.0
-- creation was removed from citus--7.0-1.sql
DROP FUNCTION IF EXISTS pg_catalog.master_initialize_node_metadata;
-- Support infrastructure for distributing aggregation
CREATE FUNCTION pg_catalog.worker_partial_agg_sfunc(internal, oid, anyelement)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C PARALLEL SAFE;
COMMENT ON FUNCTION pg_catalog.worker_partial_agg_sfunc(internal, oid, anyelement)
    IS 'transition function for worker_partial_agg';
CREATE FUNCTION pg_catalog.worker_partial_agg_ffunc(internal)
RETURNS cstring
AS 'MODULE_PATHNAME'
LANGUAGE C PARALLEL SAFE;
COMMENT ON FUNCTION pg_catalog.worker_partial_agg_ffunc(internal)
    IS 'finalizer for worker_partial_agg';
CREATE FUNCTION pg_catalog.coord_combine_agg_sfunc(internal, oid, cstring, anyelement)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C PARALLEL SAFE;
COMMENT ON FUNCTION pg_catalog.coord_combine_agg_sfunc(internal, oid, cstring, anyelement)
    IS 'transition function for coord_combine_agg';
CREATE FUNCTION pg_catalog.coord_combine_agg_ffunc(internal, oid, cstring, anyelement)
RETURNS anyelement
AS 'MODULE_PATHNAME'
LANGUAGE C PARALLEL SAFE;
COMMENT ON FUNCTION pg_catalog.coord_combine_agg_ffunc(internal, oid, cstring, anyelement)
    IS 'finalizer for coord_combine_agg';
-- select worker_partial_agg(agg, ...)
-- equivalent to
-- select to_cstring(agg_without_ffunc(...))
CREATE AGGREGATE pg_catalog.worker_partial_agg(oid, anyelement) (
    STYPE = internal,
    SFUNC = pg_catalog.worker_partial_agg_sfunc,
    FINALFUNC = pg_catalog.worker_partial_agg_ffunc
);
COMMENT ON AGGREGATE pg_catalog.worker_partial_agg(oid, anyelement)
    IS 'support aggregate for implementing partial aggregation on workers';
-- select coord_combine_agg(agg, col)
-- equivalent to
-- select agg_ffunc(agg_combine(from_cstring(col)))
CREATE AGGREGATE pg_catalog.coord_combine_agg(oid, cstring, anyelement) (
    STYPE = internal,
    SFUNC = pg_catalog.coord_combine_agg_sfunc,
    FINALFUNC = pg_catalog.coord_combine_agg_ffunc,
    FINALFUNC_EXTRA
);
COMMENT ON AGGREGATE pg_catalog.coord_combine_agg(oid, cstring, anyelement)
    IS 'support aggregate for implementing combining partial aggregate results from workers';
REVOKE ALL ON FUNCTION pg_catalog.worker_partial_agg_ffunc FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_catalog.worker_partial_agg_sfunc FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_catalog.coord_combine_agg_ffunc FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_catalog.coord_combine_agg_sfunc FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_catalog.worker_partial_agg FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_catalog.coord_combine_agg FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_catalog.worker_partial_agg_ffunc TO PUBLIC;
GRANT EXECUTE ON FUNCTION pg_catalog.worker_partial_agg_sfunc TO PUBLIC;
GRANT EXECUTE ON FUNCTION pg_catalog.coord_combine_agg_ffunc TO PUBLIC;
GRANT EXECUTE ON FUNCTION pg_catalog.coord_combine_agg_sfunc TO PUBLIC;
GRANT EXECUTE ON FUNCTION pg_catalog.worker_partial_agg TO PUBLIC;
GRANT EXECUTE ON FUNCTION pg_catalog.coord_combine_agg TO PUBLIC;
