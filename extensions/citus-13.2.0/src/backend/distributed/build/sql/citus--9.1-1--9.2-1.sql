CREATE OR REPLACE FUNCTION pg_catalog.read_intermediate_results(
    result_ids text[],
    format pg_catalog.citus_copy_format default 'csv')
RETURNS SETOF record
LANGUAGE C STRICT VOLATILE PARALLEL SAFE
AS 'MODULE_PATHNAME', $$read_intermediate_result_array$$;
COMMENT ON FUNCTION pg_catalog.read_intermediate_results(text[],pg_catalog.citus_copy_format)
IS 'read a set files and return them as a set of records';
CREATE OR REPLACE FUNCTION pg_catalog.fetch_intermediate_results(
    result_ids text[],
    node_name text,
    node_port int)
RETURNS bigint
LANGUAGE C STRICT VOLATILE
AS 'MODULE_PATHNAME', $$fetch_intermediate_results$$;
COMMENT ON FUNCTION pg_catalog.fetch_intermediate_results(text[],text,int)
IS 'fetch array of intermediate results from a remote node. returns number of bytes read.';
CREATE OR REPLACE FUNCTION pg_catalog.worker_partition_query_result(
    result_prefix text,
    query text,
    partition_column_index int,
    partition_method citus.distribution_type,
    partition_min_values text[],
    partition_max_values text[],
    binaryCopy boolean,
    OUT partition_index int,
    OUT rows_written bigint,
    OUT bytes_written bigint)
RETURNS SETOF record
LANGUAGE C STRICT VOLATILE
AS 'MODULE_PATHNAME', $$worker_partition_query_result$$;
COMMENT ON FUNCTION pg_catalog.worker_partition_query_result(text, text, int, citus.distribution_type, text[], text[], boolean)
IS 'execute a query and partitions its results in set of local result files';
ALTER TABLE pg_catalog.pg_dist_colocation ADD distributioncolumncollation oid;
UPDATE pg_catalog.pg_dist_colocation dc SET distributioncolumncollation = t.typcollation
 FROM pg_catalog.pg_type t WHERE t.oid = dc.distributioncolumntype;
UPDATE pg_catalog.pg_dist_colocation dc SET distributioncolumncollation = 0 WHERE distributioncolumncollation IS NULL;
ALTER TABLE pg_catalog.pg_dist_colocation ALTER COLUMN distributioncolumncollation SET NOT NULL;
DROP INDEX pg_dist_colocation_configuration_index;
-- distributioncolumntype should be listed first so that this index can be used for looking up reference tables' colocation id
CREATE INDEX pg_dist_colocation_configuration_index
ON pg_dist_colocation USING btree(distributioncolumntype, shardcount, replicationfactor, distributioncolumncollation);
CREATE TABLE citus.pg_dist_rebalance_strategy(
    name name NOT NULL,
    default_strategy boolean NOT NULL DEFAULT false,
    shard_cost_function regproc NOT NULL,
    node_capacity_function regproc NOT NULL,
    shard_allowed_on_node_function regproc NOT NULL,
    default_threshold float4 NOT NULL,
    minimum_threshold float4 NOT NULL DEFAULT 0,
    UNIQUE(name)
);
ALTER TABLE citus.pg_dist_rebalance_strategy SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.pg_dist_rebalance_strategy TO public;
CREATE OR REPLACE FUNCTION pg_catalog.citus_validate_rebalance_strategy_functions(
    shard_cost_function regproc,
    node_capacity_function regproc,
    shard_allowed_on_node_function regproc
)
    RETURNS VOID
    AS 'MODULE_PATHNAME'
    LANGUAGE C STRICT VOLATILE;
COMMENT ON FUNCTION pg_catalog.citus_validate_rebalance_strategy_functions(regproc,regproc,regproc)
  IS 'internal function used by citus to validate signatures of functions used in rebalance strategy';
-- Ensures that only a single default strategy is possible
CREATE OR REPLACE FUNCTION citus_internal.pg_dist_rebalance_strategy_trigger_func()
RETURNS TRIGGER AS $$
  BEGIN
    -- citus_add_rebalance_strategy also takes out a ShareRowExclusiveLock
    LOCK TABLE pg_dist_rebalance_strategy IN SHARE ROW EXCLUSIVE MODE;
    PERFORM citus_validate_rebalance_strategy_functions(
        NEW.shard_cost_function,
        NEW.node_capacity_function,
        NEW.shard_allowed_on_node_function);
    IF NEW.default_threshold < NEW.minimum_threshold THEN
      RAISE EXCEPTION 'default_threshold cannot be smaller than minimum_threshold';
    END IF;
    IF NOT NEW.default_strategy THEN
      RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.default_strategy = OLD.default_strategy THEN
        return NEW;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_dist_rebalance_strategy WHERE default_strategy) THEN
      RAISE EXCEPTION 'there cannot be two default strategies';
    END IF;
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER pg_dist_rebalance_strategy_validation_trigger
  BEFORE INSERT OR UPDATE ON pg_dist_rebalance_strategy
  FOR EACH ROW EXECUTE PROCEDURE citus_internal.pg_dist_rebalance_strategy_trigger_func();
CREATE OR REPLACE FUNCTION pg_catalog.citus_add_rebalance_strategy(
    name name,
    shard_cost_function regproc,
    node_capacity_function regproc,
    shard_allowed_on_node_function regproc,
    default_threshold float4,
    minimum_threshold float4 DEFAULT 0
)
    RETURNS VOID AS $$
    INSERT INTO
        pg_catalog.pg_dist_rebalance_strategy(
            name,
            shard_cost_function,
            node_capacity_function,
            shard_allowed_on_node_function,
            default_threshold,
            minimum_threshold
        ) VALUES (
            name,
            shard_cost_function,
            node_capacity_function,
            shard_allowed_on_node_function,
            default_threshold,
            minimum_threshold
        );
    $$ LANGUAGE sql;
COMMENT ON FUNCTION pg_catalog.citus_add_rebalance_strategy(name,regproc,regproc,regproc,float4, float4)
  IS 'adds a new rebalance strategy which can be used when rebalancing shards or draining nodes';
CREATE OR REPLACE FUNCTION pg_catalog.citus_set_default_rebalance_strategy(
    name text
)
    RETURNS VOID
    STRICT
AS $$
  BEGIN
    LOCK TABLE pg_dist_rebalance_strategy IN SHARE ROW EXCLUSIVE MODE;
    IF NOT EXISTS (SELECT 1 FROM pg_dist_rebalance_strategy t WHERE t.name = $1) THEN
      RAISE EXCEPTION 'strategy with specified name does not exist';
    END IF;
    UPDATE pg_dist_rebalance_strategy SET default_strategy = false WHERE default_strategy = true;
    UPDATE pg_dist_rebalance_strategy t SET default_strategy = true WHERE t.name = $1;
  END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION pg_catalog.citus_set_default_rebalance_strategy(text)
  IS 'changes the default rebalance strategy to the one with the specified name';
CREATE OR REPLACE FUNCTION pg_catalog.citus_shard_cost_1(bigint)
    RETURNS float4 AS $$ SELECT 1.0::float4 $$ LANGUAGE sql;
COMMENT ON FUNCTION pg_catalog.citus_shard_cost_1(bigint)
  IS 'a shard cost function for use by the rebalance algorithm that always returns 1';
CREATE OR REPLACE FUNCTION pg_catalog.citus_shard_cost_by_disk_size(bigint)
    RETURNS float4
    AS 'MODULE_PATHNAME'
    LANGUAGE C STRICT VOLATILE;
COMMENT ON FUNCTION pg_catalog.citus_shard_cost_by_disk_size(bigint)
  IS 'a shard cost function for use by the rebalance algorithm that returns the disk size in bytes for the specified shard and the shards that are colocated with it';
CREATE OR REPLACE FUNCTION pg_catalog.citus_node_capacity_1(int)
    RETURNS float4 AS $$ SELECT 1.0::float4 $$ LANGUAGE sql;
COMMENT ON FUNCTION pg_catalog.citus_node_capacity_1(int)
  IS 'a node capacity function for use by the rebalance algorithm that always returns 1';
CREATE OR REPLACE FUNCTION pg_catalog.citus_shard_allowed_on_node_true(bigint, int)
    RETURNS boolean AS $$ SELECT true $$ LANGUAGE sql;
COMMENT ON FUNCTION pg_catalog.citus_shard_allowed_on_node_true(bigint,int)
  IS 'a shard_allowed_on_node_function for use by the rebalance algorithm that always returns true';
INSERT INTO
    pg_catalog.pg_dist_rebalance_strategy(
        name,
        default_strategy,
        shard_cost_function,
        node_capacity_function,
        shard_allowed_on_node_function,
        default_threshold,
        minimum_threshold
    ) VALUES (
        'by_shard_count',
        true,
        'citus_shard_cost_1',
        'citus_node_capacity_1',
        'citus_shard_allowed_on_node_true',
        0,
        0
    ), (
        'by_disk_size',
        false,
        'citus_shard_cost_by_disk_size',
        'citus_node_capacity_1',
        'citus_shard_allowed_on_node_true',
        0.1,
        0.01
    );
CREATE FUNCTION citus_internal.pg_dist_rebalance_strategy_enterprise_check()
  RETURNS TRIGGER
  LANGUAGE C
  AS 'MODULE_PATHNAME';
CREATE TRIGGER pg_dist_rebalance_strategy_enterprise_check_trigger
  BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON pg_dist_rebalance_strategy
  FOR EACH STATEMENT EXECUTE FUNCTION citus_internal.pg_dist_rebalance_strategy_enterprise_check();
DROP FUNCTION pg_catalog.master_drain_node;
CREATE FUNCTION pg_catalog.master_drain_node(
    nodename text,
    nodeport integer,
    shard_transfer_mode citus.shard_transfer_mode default 'auto',
    rebalance_strategy name default NULL
  )
  RETURNS VOID
  LANGUAGE C
  AS 'MODULE_PATHNAME', $$master_drain_node$$;
COMMENT ON FUNCTION pg_catalog.master_drain_node(text,int,citus.shard_transfer_mode,name)
  IS 'mark a node to be drained of data and actually drain it as well';
REVOKE ALL ON FUNCTION pg_catalog.master_drain_node(text,int,citus.shard_transfer_mode,name) FROM PUBLIC;
-- rebalance_table_shards uses the shard rebalancer's C UDF functions to rebalance
-- shards of the given relation.
--
DROP FUNCTION pg_catalog.rebalance_table_shards;
CREATE OR REPLACE FUNCTION pg_catalog.rebalance_table_shards(
        relation regclass default NULL,
        threshold float4 default NULL,
        max_shard_moves int default 1000000,
        excluded_shard_list bigint[] default '{}',
        shard_transfer_mode citus.shard_transfer_mode default 'auto',
        drain_only boolean default false,
        rebalance_strategy name default NULL
    )
    RETURNS VOID
    AS 'MODULE_PATHNAME'
    LANGUAGE C VOLATILE;
COMMENT ON FUNCTION pg_catalog.rebalance_table_shards(regclass, float4, int, bigint[], citus.shard_transfer_mode, boolean, name)
    IS 'rebalance the shards of the given table across the worker nodes (including colocated shards of other tables)';
-- get_rebalance_table_shards_plan shows the actual events that will be performed
-- if a rebalance operation will be performed with the same arguments, which allows users
-- to understand the impact of the change overall availability of the application and
-- network trafic.
--
DROP FUNCTION pg_catalog.get_rebalance_table_shards_plan;
CREATE OR REPLACE FUNCTION pg_catalog.get_rebalance_table_shards_plan(
        relation regclass default NULL,
        threshold float4 default NULL,
        max_shard_moves int default 1000000,
        excluded_shard_list bigint[] default '{}',
        drain_only boolean default false,
        rebalance_strategy name default NULL
    )
    RETURNS TABLE (table_name regclass,
                   shardid bigint,
                   shard_size bigint,
                   sourcename text,
                   sourceport int,
                   targetname text,
                   targetport int)
    AS 'MODULE_PATHNAME'
    LANGUAGE C VOLATILE;
COMMENT ON FUNCTION pg_catalog.get_rebalance_table_shards_plan(regclass, float4, int, bigint[], boolean, name)
    IS 'returns the list of shard placement moves to be done on a rebalance operation';
CREATE OR REPLACE FUNCTION pg_catalog.citus_prepare_pg_upgrade()
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = pg_catalog
    AS $cppu$
BEGIN
    --
    -- backup citus catalog tables
    --
    CREATE TABLE public.pg_dist_partition AS SELECT * FROM pg_catalog.pg_dist_partition;
    CREATE TABLE public.pg_dist_shard AS SELECT * FROM pg_catalog.pg_dist_shard;
    CREATE TABLE public.pg_dist_placement AS SELECT * FROM pg_catalog.pg_dist_placement;
    CREATE TABLE public.pg_dist_node_metadata AS SELECT * FROM pg_catalog.pg_dist_node_metadata;
    CREATE TABLE public.pg_dist_node AS SELECT * FROM pg_catalog.pg_dist_node;
    CREATE TABLE public.pg_dist_local_group AS SELECT * FROM pg_catalog.pg_dist_local_group;
    CREATE TABLE public.pg_dist_transaction AS SELECT * FROM pg_catalog.pg_dist_transaction;
    CREATE TABLE public.pg_dist_colocation AS SELECT * FROM pg_catalog.pg_dist_colocation;
    -- enterprise catalog tables
    CREATE TABLE public.pg_dist_authinfo AS SELECT * FROM pg_catalog.pg_dist_authinfo;
    CREATE TABLE public.pg_dist_poolinfo AS SELECT * FROM pg_catalog.pg_dist_poolinfo;
    CREATE TABLE public.pg_dist_rebalance_strategy AS SELECT
        name,
        default_strategy,
        shard_cost_function::regprocedure::text,
        node_capacity_function::regprocedure::text,
        shard_allowed_on_node_function::regprocedure::text,
        default_threshold,
        minimum_threshold
    FROM pg_catalog.pg_dist_rebalance_strategy;
    -- store upgrade stable identifiers on pg_dist_object catalog
    UPDATE citus.pg_dist_object
       SET (type, object_names, object_args) = (SELECT * FROM pg_identify_object_as_address(classid, objid, objsubid));
END;
$cppu$;
COMMENT ON FUNCTION pg_catalog.citus_prepare_pg_upgrade()
    IS 'perform tasks to copy citus settings to a location that could later be restored after pg_upgrade is done';
CREATE OR REPLACE FUNCTION pg_catalog.citus_finish_pg_upgrade()
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = pg_catalog
    AS $cppu$
DECLARE
    table_name regclass;
    command text;
    trigger_name text;
BEGIN
    --
    -- restore citus catalog tables
    --
    INSERT INTO pg_catalog.pg_dist_partition SELECT * FROM public.pg_dist_partition;
    INSERT INTO pg_catalog.pg_dist_shard SELECT * FROM public.pg_dist_shard;
    INSERT INTO pg_catalog.pg_dist_placement SELECT * FROM public.pg_dist_placement;
    INSERT INTO pg_catalog.pg_dist_node_metadata SELECT * FROM public.pg_dist_node_metadata;
    INSERT INTO pg_catalog.pg_dist_node SELECT * FROM public.pg_dist_node;
    INSERT INTO pg_catalog.pg_dist_local_group SELECT * FROM public.pg_dist_local_group;
    INSERT INTO pg_catalog.pg_dist_transaction SELECT * FROM public.pg_dist_transaction;
    INSERT INTO pg_catalog.pg_dist_colocation SELECT * FROM public.pg_dist_colocation;
    -- enterprise catalog tables
    INSERT INTO pg_catalog.pg_dist_authinfo SELECT * FROM public.pg_dist_authinfo;
    INSERT INTO pg_catalog.pg_dist_poolinfo SELECT * FROM public.pg_dist_poolinfo;
    ALTER TABLE pg_catalog.pg_dist_rebalance_strategy DISABLE TRIGGER pg_dist_rebalance_strategy_enterprise_check_trigger;
    INSERT INTO pg_catalog.pg_dist_rebalance_strategy SELECT
        name,
        default_strategy,
        shard_cost_function::regprocedure::regproc,
        node_capacity_function::regprocedure::regproc,
        shard_allowed_on_node_function::regprocedure::regproc,
        default_threshold,
        minimum_threshold
    FROM public.pg_dist_rebalance_strategy;
    ALTER TABLE pg_catalog.pg_dist_rebalance_strategy ENABLE TRIGGER pg_dist_rebalance_strategy_enterprise_check_trigger;
    --
    -- drop backup tables
    --
    DROP TABLE public.pg_dist_authinfo;
    DROP TABLE public.pg_dist_colocation;
    DROP TABLE public.pg_dist_local_group;
    DROP TABLE public.pg_dist_node;
    DROP TABLE public.pg_dist_node_metadata;
    DROP TABLE public.pg_dist_partition;
    DROP TABLE public.pg_dist_placement;
    DROP TABLE public.pg_dist_poolinfo;
    DROP TABLE public.pg_dist_shard;
    DROP TABLE public.pg_dist_transaction;
    --
    -- reset sequences
    --
    PERFORM setval('pg_catalog.pg_dist_shardid_seq', (SELECT MAX(shardid)+1 AS max_shard_id FROM pg_dist_shard), false);
    PERFORM setval('pg_catalog.pg_dist_placement_placementid_seq', (SELECT MAX(placementid)+1 AS max_placement_id FROM pg_dist_placement), false);
    PERFORM setval('pg_catalog.pg_dist_groupid_seq', (SELECT MAX(groupid)+1 AS max_group_id FROM pg_dist_node), false);
    PERFORM setval('pg_catalog.pg_dist_node_nodeid_seq', (SELECT MAX(nodeid)+1 AS max_node_id FROM pg_dist_node), false);
    PERFORM setval('pg_catalog.pg_dist_colocationid_seq', (SELECT MAX(colocationid)+1 AS max_colocation_id FROM pg_dist_colocation), false);
    --
    -- register triggers
    --
    FOR table_name IN SELECT logicalrelid FROM pg_catalog.pg_dist_partition
    LOOP
        trigger_name := 'truncate_trigger_' || table_name::oid;
        command := 'create trigger ' || trigger_name || ' after truncate on ' || table_name || ' execute procedure pg_catalog.citus_truncate_trigger()';
        EXECUTE command;
        command := 'update pg_trigger set tgisinternal = true where tgname = ' || quote_literal(trigger_name);
        EXECUTE command;
    END LOOP;
    --
    -- set dependencies
    --
    INSERT INTO pg_depend
    SELECT
        'pg_class'::regclass::oid as classid,
        p.logicalrelid::regclass::oid as objid,
        0 as objsubid,
        'pg_extension'::regclass::oid as refclassid,
        (select oid from pg_extension where extname = 'citus') as refobjid,
        0 as refobjsubid ,
        'n' as deptype
    FROM pg_catalog.pg_dist_partition p;
    -- restore pg_dist_object from the stable identifiers
    -- DELETE/INSERT to avoid primary key violations
    WITH old_records AS (
        DELETE FROM
            citus.pg_dist_object
        RETURNING
            type,
            object_names,
            object_args,
            distribution_argument_index,
            colocationid
    )
    INSERT INTO citus.pg_dist_object (classid, objid, objsubid, distribution_argument_index, colocationid)
    SELECT
        address.classid,
        address.objid,
        address.objsubid,
        naming.distribution_argument_index,
        naming.colocationid
    FROM
        old_records naming,
        pg_get_object_address(naming.type, naming.object_names, naming.object_args) address;
END;
$cppu$;
COMMENT ON FUNCTION pg_catalog.citus_finish_pg_upgrade()
    IS 'perform tasks to restore citus settings from a location that has been prepared before pg_upgrade';
