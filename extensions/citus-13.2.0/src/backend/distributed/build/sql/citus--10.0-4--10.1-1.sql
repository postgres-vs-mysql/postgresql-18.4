-- citus--10.0-4--10.1-1
-- add the current database to the distributed objects if not already in there.
-- this is to reliably propagate some of the alter database commands that might be
-- supported.
INSERT INTO citus.pg_dist_object SELECT
  'pg_catalog.pg_database'::regclass::oid AS oid,
  (SELECT oid FROM pg_database WHERE datname = current_database()) as objid,
  0 as objsubid
ON CONFLICT DO NOTHING;
--#include "../../columnar/sql/columnar--10.0-3--10.1-1.sql"
DO $check_columnar$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension AS e
             INNER JOIN pg_catalog.pg_depend AS d ON (d.refobjid = e.oid)
             INNER JOIN pg_catalog.pg_proc AS p ON (p.oid = d.objid)
             WHERE e.extname='citus_columnar' and p.proname = 'columnar_handler'
  ) THEN
-- columnar--10.0-3--10.1-1.sql
-- Drop foreign keys between columnar metadata tables.
-- Postgres assigns different names to those foreign keys in PG11, so act accordingly.
DO $proc$
BEGIN
IF substring(current_Setting('server_version'), '\d+')::int >= 12 THEN
  EXECUTE $$
ALTER TABLE columnar.chunk DROP CONSTRAINT chunk_storage_id_stripe_num_chunk_group_num_fkey;
ALTER TABLE columnar.chunk_group DROP CONSTRAINT chunk_group_storage_id_stripe_num_fkey;
  $$;
ELSE
  EXECUTE $$
ALTER TABLE columnar.chunk DROP CONSTRAINT chunk_storage_id_fkey;
ALTER TABLE columnar.chunk_group DROP CONSTRAINT chunk_group_storage_id_fkey;
  $$;
END IF;
END$proc$;
-- since we dropped pg11 support, we don't need to worry about missing
-- columnar objects when upgrading postgres
DROP FUNCTION citus_internal.columnar_ensure_objects_exist();
  END IF;
END;
$check_columnar$;
DROP FUNCTION create_distributed_table(regclass, text, citus.distribution_type, text);
CREATE OR REPLACE FUNCTION create_distributed_table(table_name regclass,
                                                    distribution_column text,
                                                    distribution_type citus.distribution_type DEFAULT 'hash',
                                                    colocate_with text DEFAULT 'default',
                                                    shard_count int DEFAULT NULL)
    RETURNS void
    LANGUAGE C
    AS 'MODULE_PATHNAME', $$create_distributed_table$$;
COMMENT ON FUNCTION create_distributed_table(table_name regclass,
            distribution_column text,
            distribution_type citus.distribution_type,
            colocate_with text,
                                             shard_count int)
    IS 'creates a distributed table';
CREATE OR REPLACE FUNCTION worker_partitioned_relation_total_size(relation regclass)
RETURNS bigint AS $$
    SELECT sum(pg_total_relation_size(relid))::bigint
       FROM (SELECT relid from pg_partition_tree(relation)) partition_tree;
$$ LANGUAGE SQL;
COMMENT ON FUNCTION worker_partitioned_relation_total_size(regclass)
 IS 'Calculates and returns the total size of a partitioned relation';
CREATE OR REPLACE FUNCTION worker_partitioned_relation_size(relation regclass)
RETURNS bigint AS $$
    SELECT sum(pg_relation_size(relid))::bigint
       FROM (SELECT relid from pg_partition_tree(relation)) partition_tree;
$$ LANGUAGE SQL;
COMMENT ON FUNCTION pg_catalog.worker_partitioned_relation_size(regclass)
    IS 'Calculates and returns the size of a partitioned relation';
CREATE OR REPLACE FUNCTION worker_partitioned_table_size(relation regclass)
RETURNS bigint AS $$
    SELECT sum(pg_table_size(relid))::bigint
       FROM (SELECT relid from pg_partition_tree(relation)) partition_tree;
$$ LANGUAGE SQL;
COMMENT ON FUNCTION pg_catalog.worker_partitioned_table_size(regclass)
    IS 'Calculates and returns the size of a partitioned table';
CREATE OR REPLACE FUNCTION pg_catalog.citus_prepare_pg_upgrade()
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = pg_catalog
    AS $cppu$
BEGIN
    --
    -- Drop existing backup tables
    --
    DROP TABLE IF EXISTS public.pg_dist_partition;
    DROP TABLE IF EXISTS public.pg_dist_shard;
    DROP TABLE IF EXISTS public.pg_dist_placement;
    DROP TABLE IF EXISTS public.pg_dist_node_metadata;
    DROP TABLE IF EXISTS public.pg_dist_node;
    DROP TABLE IF EXISTS public.pg_dist_local_group;
    DROP TABLE IF EXISTS public.pg_dist_transaction;
    DROP TABLE IF EXISTS public.pg_dist_colocation;
    DROP TABLE IF EXISTS public.pg_dist_authinfo;
    DROP TABLE IF EXISTS public.pg_dist_poolinfo;
    DROP TABLE IF EXISTS public.pg_dist_rebalance_strategy;
    DROP TABLE IF EXISTS public.pg_dist_object;
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
        minimum_threshold,
        improvement_threshold
    FROM pg_catalog.pg_dist_rebalance_strategy;
    -- store upgrade stable identifiers on pg_dist_object catalog
    CREATE TABLE public.pg_dist_object AS SELECT
       address.type,
       address.object_names,
       address.object_args,
       objects.distribution_argument_index,
       objects.colocationid
    FROM citus.pg_dist_object objects,
         pg_catalog.pg_identify_object_as_address(objects.classid, objects.objid, objects.objsubid) address;
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
    INSERT INTO pg_catalog.pg_dist_rebalance_strategy SELECT
        name,
        default_strategy,
        shard_cost_function::regprocedure::regproc,
        node_capacity_function::regprocedure::regproc,
        shard_allowed_on_node_function::regprocedure::regproc,
        default_threshold,
        minimum_threshold,
        improvement_threshold
    FROM public.pg_dist_rebalance_strategy;
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
    DROP TABLE public.pg_dist_rebalance_strategy;
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
    TRUNCATE citus.pg_dist_object;
    INSERT INTO citus.pg_dist_object (classid, objid, objsubid, distribution_argument_index, colocationid)
    SELECT
        address.classid,
        address.objid,
        address.objsubid,
        naming.distribution_argument_index,
        naming.colocationid
    FROM
        public.pg_dist_object naming,
        pg_catalog.pg_get_object_address(naming.type, naming.object_names, naming.object_args) address;
    DROP TABLE public.pg_dist_object;
END;
$cppu$;
COMMENT ON FUNCTION pg_catalog.citus_finish_pg_upgrade()
    IS 'perform tasks to restore citus settings from a location that has been prepared before pg_upgrade';
CREATE OR REPLACE FUNCTION pg_catalog.citus_local_disk_space_stats(
  OUT available_disk_size bigint,
  OUT total_disk_size bigint)
RETURNS record
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_local_disk_space_stats$$;
COMMENT ON FUNCTION pg_catalog.citus_local_disk_space_stats()
IS 'returns statistics on available disk space on the local node';
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
        rebalance_strategy name default NULL,
        improvement_threshold float4 DEFAULT NULL
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
COMMENT ON FUNCTION pg_catalog.get_rebalance_table_shards_plan(regclass, float4, int, bigint[], boolean, name, float4)
    IS 'returns the list of shard placement moves to be done on a rebalance operation';
DROP FUNCTION pg_catalog.citus_add_rebalance_strategy;
CREATE OR REPLACE FUNCTION pg_catalog.citus_add_rebalance_strategy(
    name name,
    shard_cost_function regproc,
    node_capacity_function regproc,
    shard_allowed_on_node_function regproc,
    default_threshold float4,
    minimum_threshold float4 DEFAULT 0,
    improvement_threshold float4 DEFAULT 0
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
COMMENT ON FUNCTION pg_catalog.citus_add_rebalance_strategy(name,regproc,regproc,regproc,float4, float4, float4)
  IS 'adds a new rebalance strategy which can be used when rebalancing shards or draining nodes';
ALTER TABLE pg_catalog.pg_dist_rebalance_strategy ADD COLUMN improvement_threshold float4 NOT NULL default 0;
UPDATE pg_catalog.pg_dist_rebalance_strategy SET improvement_threshold = 0.5 WHERE name = 'by_disk_size';
DROP FUNCTION pg_catalog.get_rebalance_progress();
CREATE OR REPLACE FUNCTION pg_catalog.get_rebalance_progress()
  RETURNS TABLE(sessionid integer,
                table_name regclass,
                shardid bigint,
                shard_size bigint,
                sourcename text,
                sourceport int,
                targetname text,
                targetport int,
                progress bigint,
                source_shard_size bigint,
                target_shard_size bigint)
  AS 'MODULE_PATHNAME'
  LANGUAGE C STRICT;
COMMENT ON FUNCTION pg_catalog.get_rebalance_progress()
    IS 'provides progress information about the ongoing rebalance operations';
-- use streaming replication when replication factor = 1
WITH replicated_shards AS (
    SELECT shardid
    FROM pg_dist_placement
    WHERE shardstate = 1 OR shardstate = 3
    GROUP BY shardid
    HAVING count(*) <> 1 ),
replicated_relations AS (
    SELECT DISTINCT logicalrelid
    FROM pg_dist_shard
    JOIN replicated_shards
    USING (shardid)
)
UPDATE pg_dist_partition
SET repmodel = 's'
WHERE repmodel = 'c'
    AND partmethod = 'h'
    AND logicalrelid NOT IN (SELECT * FROM replicated_relations);
CREATE OR REPLACE VIEW pg_catalog.citus_shards AS
SELECT
     pg_dist_shard.logicalrelid AS table_name,
     pg_dist_shard.shardid,
     shard_name(pg_dist_shard.logicalrelid, pg_dist_shard.shardid) as shard_name,
     CASE WHEN partkey IS NOT NULL THEN 'distributed' WHEN repmodel = 't' THEN 'reference' ELSE 'local' END AS citus_table_type,
     colocationid AS colocation_id,
     pg_dist_node.nodename,
     pg_dist_node.nodeport,
     size as shard_size
FROM
   pg_dist_shard
JOIN
   pg_dist_placement
ON
   pg_dist_shard.shardid = pg_dist_placement.shardid
JOIN
   pg_dist_node
ON
   pg_dist_placement.groupid = pg_dist_node.groupid
JOIN
   pg_dist_partition
ON
   pg_dist_partition.logicalrelid = pg_dist_shard.logicalrelid
LEFT JOIN
   (SELECT (regexp_matches(table_name,'_(\d+)$'))[1]::int as shard_id, max(size) as size from citus_shard_sizes() GROUP BY shard_id) as shard_sizes
ON
    pg_dist_shard.shardid = shard_sizes.shard_id
WHERE
   pg_dist_placement.shardstate = 1
ORDER BY
   pg_dist_shard.logicalrelid::text, shardid
;
GRANT SELECT ON pg_catalog.citus_shards TO public;
DROP TRIGGER pg_dist_rebalance_strategy_enterprise_check_trigger ON pg_catalog.pg_dist_rebalance_strategy;
DROP FUNCTION citus_internal.pg_dist_rebalance_strategy_enterprise_check();
CREATE OR REPLACE PROCEDURE pg_catalog.citus_cleanup_orphaned_shards()
    LANGUAGE C
    AS 'citus', $$citus_cleanup_orphaned_shards$$;
COMMENT ON PROCEDURE pg_catalog.citus_cleanup_orphaned_shards()
    IS 'cleanup orphaned shards';
