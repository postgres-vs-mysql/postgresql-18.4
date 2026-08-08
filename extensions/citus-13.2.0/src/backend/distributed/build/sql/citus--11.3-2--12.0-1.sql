-- citus--11.3-1--12.0-1
-- bump version to 12.0-1
CREATE TABLE citus.pg_dist_schema (
    schemaid oid NOT NULL,
    colocationid int NOT NULL,
    CONSTRAINT pg_dist_schema_pkey PRIMARY KEY (schemaid),
    CONSTRAINT pg_dist_schema_unique_colocationid_index UNIQUE (colocationid)
);
ALTER TABLE citus.pg_dist_schema SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.pg_dist_schema TO public;
-- udfs used to modify pg_dist_schema on workers, to sync metadata
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_tenant_schema(schema_id Oid, colocation_id int)
    RETURNS void
    LANGUAGE C
    VOLATILE
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_add_tenant_schema(Oid, int) IS
    'insert given tenant schema into pg_dist_schema with given colocation id';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_delete_tenant_schema(schema_id Oid)
    RETURNS void
    LANGUAGE C
    VOLATILE
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_delete_tenant_schema(Oid) IS
    'delete given tenant schema from pg_dist_schema';
CREATE OR REPLACE FUNCTION pg_catalog.citus_prepare_pg_upgrade()
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = pg_catalog
    AS $cppu$
BEGIN
    DELETE FROM pg_depend WHERE
        objid IN (SELECT oid FROM pg_proc WHERE proname = 'array_cat_agg') AND
        refobjid IN (select oid from pg_extension where extname = 'citus');
    --
    -- We are dropping the aggregates because postgres 14 changed
    -- array_cat type from anyarray to anycompatiblearray. When
    -- upgrading to pg14, specifically when running pg_restore on
    -- array_cat_agg we would get an error. So we drop the aggregate
    -- and create the right one on citus_finish_pg_upgrade.
    DROP AGGREGATE IF EXISTS array_cat_agg(anyarray);
    DROP AGGREGATE IF EXISTS array_cat_agg(anycompatiblearray);
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
    DROP TABLE IF EXISTS public.pg_dist_cleanup;
    DROP TABLE IF EXISTS public.pg_dist_schema;
    DROP TABLE IF EXISTS public.pg_dist_clock_logical_seq;
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
    CREATE TABLE public.pg_dist_cleanup AS SELECT * FROM pg_catalog.pg_dist_cleanup;
    -- save names of the tenant schemas instead of their oids because the oids might change after pg upgrade
    CREATE TABLE public.pg_dist_schema AS SELECT schemaid::regnamespace::text AS schemaname, colocationid FROM pg_catalog.pg_dist_schema;
    -- enterprise catalog tables
    CREATE TABLE public.pg_dist_authinfo AS SELECT * FROM pg_catalog.pg_dist_authinfo;
    CREATE TABLE public.pg_dist_poolinfo AS SELECT * FROM pg_catalog.pg_dist_poolinfo;
    -- sequences
    CREATE TABLE public.pg_dist_clock_logical_seq AS SELECT last_value FROM pg_catalog.pg_dist_clock_logical_seq;
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
    FROM pg_catalog.pg_dist_object objects,
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
    IF substring(current_Setting('server_version'), '\d+')::int >= 14 THEN
    EXECUTE $cmd$
        -- disable propagation to prevent EnsureCoordinator errors
        -- the aggregate created here does not depend on Citus extension (yet)
        -- since we add the dependency with the next command
        SET citus.enable_ddl_propagation TO OFF;
        CREATE AGGREGATE array_cat_agg(anycompatiblearray) (SFUNC = array_cat, STYPE = anycompatiblearray);
        COMMENT ON AGGREGATE array_cat_agg(anycompatiblearray)
        IS 'concatenate input arrays into a single array';
        RESET citus.enable_ddl_propagation;
    $cmd$;
    ELSE
    EXECUTE $cmd$
        SET citus.enable_ddl_propagation TO OFF;
        CREATE AGGREGATE array_cat_agg(anyarray) (SFUNC = array_cat, STYPE = anyarray);
        COMMENT ON AGGREGATE array_cat_agg(anyarray)
        IS 'concatenate input arrays into a single array';
        RESET citus.enable_ddl_propagation;
    $cmd$;
    END IF;
    --
    -- Citus creates the array_cat_agg but because of a compatibility
    -- issue between pg13-pg14, we drop and create it during upgrade.
    -- And as Citus creates it, there needs to be a dependency to the
    -- Citus extension, so we create that dependency here.
    -- We are not using:
    -- ALTER EXENSION citus DROP/CREATE AGGREGATE array_cat_agg
    -- because we don't have an easy way to check if the aggregate
    -- exists with anyarray type or anycompatiblearray type.
    INSERT INTO pg_depend
    SELECT
        'pg_proc'::regclass::oid as classid,
        (SELECT oid FROM pg_proc WHERE proname = 'array_cat_agg') as objid,
        0 as objsubid,
        'pg_extension'::regclass::oid as refclassid,
        (select oid from pg_extension where extname = 'citus') as refobjid,
        0 as refobjsubid ,
        'e' as deptype;
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
    INSERT INTO pg_catalog.pg_dist_cleanup SELECT * FROM public.pg_dist_cleanup;
    INSERT INTO pg_catalog.pg_dist_schema SELECT schemaname::regnamespace, colocationid FROM public.pg_dist_schema;
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
    DROP TABLE public.pg_dist_cleanup;
    DROP TABLE public.pg_dist_schema;
    --
    -- reset sequences
    --
    PERFORM setval('pg_catalog.pg_dist_shardid_seq', (SELECT MAX(shardid)+1 AS max_shard_id FROM pg_dist_shard), false);
    PERFORM setval('pg_catalog.pg_dist_placement_placementid_seq', (SELECT MAX(placementid)+1 AS max_placement_id FROM pg_dist_placement), false);
    PERFORM setval('pg_catalog.pg_dist_groupid_seq', (SELECT MAX(groupid)+1 AS max_group_id FROM pg_dist_node), false);
    PERFORM setval('pg_catalog.pg_dist_node_nodeid_seq', (SELECT MAX(nodeid)+1 AS max_node_id FROM pg_dist_node), false);
    PERFORM setval('pg_catalog.pg_dist_colocationid_seq', (SELECT MAX(colocationid)+1 AS max_colocation_id FROM pg_dist_colocation), false);
    PERFORM setval('pg_catalog.pg_dist_operationid_seq', (SELECT MAX(operation_id)+1 AS max_operation_id FROM pg_dist_cleanup), false);
    PERFORM setval('pg_catalog.pg_dist_cleanup_recordid_seq', (SELECT MAX(record_id)+1 AS max_record_id FROM pg_dist_cleanup), false);
    PERFORM setval('pg_catalog.pg_dist_clock_logical_seq', (SELECT last_value FROM public.pg_dist_clock_logical_seq), false);
    DROP TABLE public.pg_dist_clock_logical_seq;
    --
    -- register triggers
    --
    FOR table_name IN SELECT logicalrelid FROM pg_catalog.pg_dist_partition JOIN pg_class ON (logicalrelid = oid) WHERE relkind <> 'f'
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
    -- set dependencies for columnar table access method
    PERFORM columnar_internal.columnar_ensure_am_depends_catalog();
    -- restore pg_dist_object from the stable identifiers
    TRUNCATE pg_catalog.pg_dist_object;
    INSERT INTO pg_catalog.pg_dist_object (classid, objid, objsubid, distribution_argument_index, colocationid)
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
-- udfs used to modify pg_dist_schema globally via drop trigger
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_unregister_tenant_schema_globally(schema_id Oid, schema_name text)
    RETURNS void
    LANGUAGE C
    VOLATILE
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_unregister_tenant_schema_globally(schema_id Oid, schema_name text) IS
    'Delete a tenant schema and the corresponding colocation group from metadata tables.';
CREATE OR REPLACE FUNCTION pg_catalog.citus_drop_trigger()
    RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path = pg_catalog
    AS $cdbdt$
DECLARE
    constraint_event_count INTEGER;
    v_obj record;
    dropped_table_is_a_partition boolean := false;
BEGIN
    FOR v_obj IN SELECT * FROM pg_event_trigger_dropped_objects()
                 WHERE object_type IN ('table', 'foreign table')
    LOOP
        -- first drop the table and metadata on the workers
        -- then drop all the shards on the workers
        -- finally remove the pg_dist_partition entry on the coordinator
        PERFORM master_remove_distributed_table_metadata_from_workers(v_obj.objid, v_obj.schema_name, v_obj.object_name);
        -- If both original and normal values are false, the dropped table was a partition
        -- that was dropped as a result of its parent being dropped
        -- NOTE: the other way around is not true:
        -- the table being a partition doesn't imply both original and normal values are false
        SELECT (v_obj.original = false AND v_obj.normal = false) INTO dropped_table_is_a_partition;
        -- The partition's shards will be dropped when dropping the parent's shards, so we can skip:
        -- i.e. we call citus_drop_all_shards with drop_shards_metadata_only parameter set to true
        IF dropped_table_is_a_partition
        THEN
            PERFORM citus_drop_all_shards(v_obj.objid, v_obj.schema_name, v_obj.object_name, drop_shards_metadata_only := true);
        ELSE
            PERFORM citus_drop_all_shards(v_obj.objid, v_obj.schema_name, v_obj.object_name, drop_shards_metadata_only := false);
        END IF;
        PERFORM master_remove_partition_metadata(v_obj.objid, v_obj.schema_name, v_obj.object_name);
    END LOOP;
    FOR v_obj IN SELECT * FROM pg_event_trigger_dropped_objects()
    LOOP
        -- Remove entries from pg_catalog.pg_dist_schema for all dropped tenant schemas.
        -- Also delete the corresponding colocation group from pg_catalog.pg_dist_colocation.
        --
        -- Although normally we automatically delete the colocation groups when they become empty,
        -- we don't do so for the colocation groups that are created for tenant schemas. For this
        -- reason, here we need to delete the colocation group when the tenant schema is dropped.
        IF v_obj.object_type = 'schema' AND EXISTS (SELECT 1 FROM pg_catalog.pg_dist_schema WHERE schemaid = v_obj.objid)
        THEN
            PERFORM pg_catalog.citus_internal_unregister_tenant_schema_globally(v_obj.objid, v_obj.object_name);
        END IF;
        -- remove entries from citus.pg_dist_object for all dropped root (objsubid = 0) objects
        PERFORM master_unmark_object_distributed(v_obj.classid, v_obj.objid, v_obj.objsubid);
    END LOOP;
    SELECT COUNT(*) INTO constraint_event_count
    FROM pg_event_trigger_dropped_objects()
    WHERE object_type IN ('table constraint');
    IF constraint_event_count > 0
    THEN
        -- Tell utility hook that a table constraint is dropped so we might
        -- need to undistribute some of the citus local tables that are not
        -- connected to any reference tables.
        PERFORM notify_constraint_dropped();
    END IF;
END;
$cdbdt$;
COMMENT ON FUNCTION pg_catalog.citus_drop_trigger()
    IS 'perform checks and actions at the end of DROP actions';
DO $$
declare
citus_tables_create_query text;
BEGIN
citus_tables_create_query=$CTCQ$
    CREATE OR REPLACE VIEW %I.citus_tables AS
    SELECT
        logicalrelid AS table_name,
        CASE WHEN colocationid IN (SELECT colocationid FROM pg_dist_schema) THEN 'schema'
            WHEN partkey IS NOT NULL THEN 'distributed'
            WHEN repmodel = 't' THEN 'reference'
            WHEN colocationid = 0 THEN 'local'
            ELSE 'distributed'
        END AS citus_table_type,
        coalesce(column_to_column_name(logicalrelid, partkey), '<none>') AS distribution_column,
        colocationid AS colocation_id,
        pg_size_pretty(table_sizes.table_size) AS table_size,
        (select count(*) from pg_dist_shard where logicalrelid = p.logicalrelid) AS shard_count,
        pg_get_userbyid(relowner) AS table_owner,
        amname AS access_method
    FROM
        pg_dist_partition p
    JOIN
        pg_class c ON (p.logicalrelid = c.oid)
    LEFT JOIN
        pg_am a ON (a.oid = c.relam)
    JOIN
        (
            SELECT ds.logicalrelid AS table_id, SUM(css.size) AS table_size
            FROM citus_shard_sizes() css, pg_dist_shard ds
            WHERE css.shard_id = ds.shardid
            GROUP BY ds.logicalrelid
        ) table_sizes ON (table_sizes.table_id = p.logicalrelid)
    WHERE
        -- filter out tables owned by extensions
        logicalrelid NOT IN (
            SELECT
                objid
            FROM
                pg_depend
            WHERE
                classid = 'pg_class'::regclass AND refclassid = 'pg_extension'::regclass AND deptype = 'e'
        )
    ORDER BY
        logicalrelid::text;
$CTCQ$;
IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'public') THEN
    EXECUTE format(citus_tables_create_query, 'public');
    GRANT SELECT ON public.citus_tables TO public;
ELSE
    EXECUTE format(citus_tables_create_query, 'citus');
    ALTER VIEW citus.citus_tables SET SCHEMA pg_catalog;
    GRANT SELECT ON pg_catalog.citus_tables TO public;
END IF;
END;
$$;
DROP VIEW citus_shards;
CREATE OR REPLACE VIEW citus.citus_shards AS
SELECT
     pg_dist_shard.logicalrelid AS table_name,
     pg_dist_shard.shardid,
     shard_name(pg_dist_shard.logicalrelid, pg_dist_shard.shardid) as shard_name,
     CASE WHEN colocationid IN (SELECT colocationid FROM pg_dist_schema) THEN 'schema'
      WHEN partkey IS NOT NULL THEN 'distributed'
      WHEN repmodel = 't' THEN 'reference'
      WHEN colocationid = 0 THEN 'local'
      ELSE 'distributed' END AS citus_table_type,
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
   (SELECT shard_id, max(size) as size from citus_shard_sizes() GROUP BY shard_id) as shard_sizes
ON
    pg_dist_shard.shardid = shard_sizes.shard_id
WHERE
   pg_dist_placement.shardstate = 1
AND
   -- filter out tables owned by extensions
   pg_dist_partition.logicalrelid NOT IN (
      SELECT
         objid
      FROM
         pg_depend
      WHERE
         classid = 'pg_class'::regclass AND refclassid = 'pg_extension'::regclass AND deptype = 'e'
   )
ORDER BY
   pg_dist_shard.logicalrelid::text, shardid
;
ALTER VIEW citus.citus_shards SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_shards TO public;
DO $$
declare
citus_schemas_create_query text;
BEGIN
citus_schemas_create_query=$CSCQ$
    CREATE OR REPLACE VIEW %I.citus_schemas AS
    SELECT
        ts.schemaid::regnamespace AS schema_name,
        ts.colocationid AS colocation_id,
        CASE
            WHEN pg_catalog.has_schema_privilege(CURRENT_USER, ts.schemaid::regnamespace, 'USAGE')
            THEN pg_size_pretty(coalesce(schema_sizes.schema_size, 0))
            ELSE NULL
        END AS schema_size,
        pg_get_userbyid(n.nspowner) AS schema_owner
    FROM
        pg_dist_schema ts
    JOIN
        pg_namespace n ON (ts.schemaid = n.oid)
    LEFT JOIN (
        SELECT c.relnamespace::regnamespace schema_id, SUM(size) AS schema_size
        FROM citus_shard_sizes() css, pg_dist_shard ds, pg_class c
        WHERE css.shard_id = ds.shardid AND ds.logicalrelid = c.oid
        GROUP BY schema_id
    ) schema_sizes ON schema_sizes.schema_id = ts.schemaid
    ORDER BY
        schema_name;
$CSCQ$;
IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'public') THEN
    EXECUTE format(citus_schemas_create_query, 'public');
    REVOKE ALL ON public.citus_schemas FROM public;
    GRANT SELECT ON public.citus_schemas TO public;
ELSE
    EXECUTE format(citus_schemas_create_query, 'citus');
    ALTER VIEW citus.citus_schemas SET SCHEMA pg_catalog;
    REVOKE ALL ON pg_catalog.citus_schemas FROM public;
    GRANT SELECT ON pg_catalog.citus_schemas TO public;
END IF;
END;
$$;
-- udfs used to include schema-based tenants in tenant monitoring
CREATE OR REPLACE FUNCTION pg_catalog.citus_stat_tenants_local_internal(
    return_all_tenants BOOLEAN DEFAULT FALSE,
    OUT colocation_id INT,
    OUT tenant_attribute TEXT,
    OUT read_count_in_this_period INT,
    OUT read_count_in_last_period INT,
    OUT query_count_in_this_period INT,
    OUT query_count_in_last_period INT,
    OUT cpu_usage_in_this_period DOUBLE PRECISION,
    OUT cpu_usage_in_last_period DOUBLE PRECISION,
    OUT score BIGINT)
RETURNS SETOF RECORD
LANGUAGE C
AS 'citus', $$citus_stat_tenants_local$$;
CREATE OR REPLACE FUNCTION pg_catalog.citus_stat_tenants_local(
    return_all_tenants BOOLEAN DEFAULT FALSE,
    OUT colocation_id INT,
    OUT tenant_attribute TEXT,
    OUT read_count_in_this_period INT,
    OUT read_count_in_last_period INT,
    OUT query_count_in_this_period INT,
    OUT query_count_in_last_period INT,
    OUT cpu_usage_in_this_period DOUBLE PRECISION,
    OUT cpu_usage_in_last_period DOUBLE PRECISION,
    OUT score BIGINT)
RETURNS SETOF RECORD
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        L.colocation_id,
        CASE WHEN L.tenant_attribute IS NULL THEN N.nspname ELSE L.tenant_attribute END COLLATE "default" as tenant_attribute,
        L.read_count_in_this_period,
        L.read_count_in_last_period,
        L.query_count_in_this_period,
        L.query_count_in_last_period,
        L.cpu_usage_in_this_period,
        L.cpu_usage_in_last_period,
        L.score
    FROM pg_catalog.citus_stat_tenants_local_internal(return_all_tenants) L
    LEFT JOIN pg_dist_schema S ON L.tenant_attribute IS NULL AND L.colocation_id = S.colocationid
    LEFT JOIN pg_namespace N ON N.oid = S.schemaid
    ORDER BY L.score DESC;
END;
$function$;
CREATE OR REPLACE VIEW pg_catalog.citus_stat_tenants_local AS
SELECT
    colocation_id,
    tenant_attribute,
    read_count_in_this_period,
    read_count_in_last_period,
    query_count_in_this_period,
    query_count_in_last_period,
    cpu_usage_in_this_period,
    cpu_usage_in_last_period
FROM pg_catalog.citus_stat_tenants_local()
ORDER BY score DESC;
REVOKE ALL ON FUNCTION pg_catalog.citus_stat_tenants_local_internal(BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_catalog.citus_stat_tenants_local_internal(BOOLEAN) TO pg_monitor;
REVOKE ALL ON FUNCTION pg_catalog.citus_stat_tenants_local(BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_catalog.citus_stat_tenants_local(BOOLEAN) TO pg_monitor;
REVOKE ALL ON pg_catalog.citus_stat_tenants_local FROM PUBLIC;
GRANT SELECT ON pg_catalog.citus_stat_tenants_local TO pg_monitor;
-- udfs to convert a regular/tenant schema to a tenant/regular schema
CREATE OR REPLACE FUNCTION pg_catalog.citus_schema_distribute(schemaname regnamespace)
 RETURNS void
 LANGUAGE C STRICT
 AS 'MODULE_PATHNAME', $$citus_schema_distribute$$;
COMMENT ON FUNCTION pg_catalog.citus_schema_distribute(schemaname regnamespace)
 IS 'distributes a schema, allowing it to move between nodes';
CREATE OR REPLACE FUNCTION pg_catalog.citus_schema_undistribute(schemaname regnamespace)
 RETURNS void
 LANGUAGE C STRICT
 AS 'MODULE_PATHNAME', $$citus_schema_undistribute$$;
COMMENT ON FUNCTION pg_catalog.citus_schema_undistribute(schemaname regnamespace)
 IS 'reverts schema distribution, moving it back to the coordinator';
CREATE OR REPLACE PROCEDURE pg_catalog.drop_old_time_partitions(
    table_name regclass,
    older_than timestamptz)
LANGUAGE plpgsql
AS $$
DECLARE
    -- properties of the partitioned table
    number_of_partition_columns int;
    partition_column_index int;
    partition_column_type regtype;
    -- used to support dynamic type casting between the partition column type and timestamptz
    custom_cast text;
    is_partition_column_castable boolean;
    older_partitions_query text;
    r record;
BEGIN
    -- check whether the table is time partitioned table, if not error out
    SELECT partnatts, partattrs[0]
    INTO number_of_partition_columns, partition_column_index
    FROM pg_catalog.pg_partitioned_table
    WHERE partrelid = table_name;
    IF NOT FOUND THEN
        RAISE '% is not partitioned', table_name::text;
    ELSIF number_of_partition_columns <> 1 THEN
        RAISE 'partitioned tables with multiple partition columns are not supported';
    END IF;
    -- get datatype here to check interval-table type
    SELECT atttypid
    INTO partition_column_type
    FROM pg_attribute
    WHERE attrelid = table_name::oid
    AND attnum = partition_column_index;
    -- we currently only support partitioning by date, timestamp, and timestamptz
    custom_cast = '';
    IF partition_column_type <> 'date'::regtype
    AND partition_column_type <> 'timestamp'::regtype
    AND partition_column_type <> 'timestamptz'::regtype THEN
      SELECT EXISTS(SELECT OID FROM pg_cast WHERE castsource = partition_column_type AND casttarget = 'timestamptz'::regtype) AND
             EXISTS(SELECT OID FROM pg_cast WHERE castsource = 'timestamptz'::regtype AND casttarget = partition_column_type)
      INTO is_partition_column_castable;
      IF not is_partition_column_castable THEN
        RAISE 'type of the partition column of the table % must be date, timestamp or timestamptz', table_name;
      END IF;
      custom_cast = format('::%s', partition_column_type);
    END IF;
    older_partitions_query = format('SELECT partition, nspname AS schema_name, relname AS table_name, from_value, to_value
        FROM pg_catalog.time_partitions, pg_catalog.pg_class c, pg_catalog.pg_namespace n
        WHERE parent_table = $1 AND partition = c.oid AND c.relnamespace = n.oid
        AND to_value IS NOT NULL
        AND to_value%1$s::timestamptz <= $2
        ORDER BY to_value%1$s::timestamptz', custom_cast);
    FOR r IN EXECUTE older_partitions_query USING table_name, older_than
    LOOP
        RAISE NOTICE 'dropping % with start time % and end time %', r.partition, r.from_value, r.to_value;
        EXECUTE format('DROP TABLE %I.%I', r.schema_name, r.table_name);
    END LOOP;
END;
$$;
COMMENT ON PROCEDURE pg_catalog.drop_old_time_partitions(
    table_name regclass,
    older_than timestamptz)
IS 'drop old partitions of a time-partitioned table';
CREATE OR REPLACE FUNCTION pg_catalog.get_missing_time_partition_ranges(
    table_name regclass,
    partition_interval INTERVAL,
    to_value timestamptz,
    from_value timestamptz DEFAULT now())
returns table(
    partition_name text,
    range_from_value text,
    range_to_value text)
LANGUAGE plpgsql
AS $$
DECLARE
    -- properties of the partitioned table
    table_name_text text;
    table_schema_text text;
    number_of_partition_columns int;
    partition_column_index int;
    partition_column_type regtype;
    -- used for generating time ranges
    current_range_from_value timestamptz := NULL;
    current_range_to_value timestamptz := NULL;
    current_range_from_value_text text;
    current_range_to_value_text text;
    -- used to check whether there are misaligned (manually created) partitions
    manual_partition regclass;
    manual_partition_from_value_text text;
    manual_partition_to_value_text text;
    -- used for partition naming
    partition_name_format text;
    max_table_name_length int := current_setting('max_identifier_length');
    -- used to determine whether the partition_interval is a day multiple
    is_day_multiple boolean;
    -- used to support dynamic type casting between the partition column type and timestamptz
    custom_cast text;
    is_partition_column_castable boolean;
    partition regclass;
    partition_covers_query text;
    partition_exist_query text;
BEGIN
    -- check whether the table is time partitioned table, if not error out
    SELECT relname, nspname, partnatts, partattrs[0]
    INTO table_name_text, table_schema_text, number_of_partition_columns, partition_column_index
    FROM pg_catalog.pg_partitioned_table, pg_catalog.pg_class c, pg_catalog.pg_namespace n
    WHERE partrelid = c.oid AND c.oid = table_name
    AND c.relnamespace = n.oid;
    IF NOT FOUND THEN
        RAISE '% is not partitioned', table_name;
    ELSIF number_of_partition_columns <> 1 THEN
        RAISE 'partitioned tables with multiple partition columns are not supported';
    END IF;
    -- to not to have partitions to be created in parallel
    EXECUTE format('LOCK TABLE %I.%I IN SHARE UPDATE EXCLUSIVE MODE', table_schema_text, table_name_text);
    -- get datatype here to check interval-table type alignment and generate range values in the right data format
    SELECT atttypid
    INTO partition_column_type
    FROM pg_attribute
    WHERE attrelid = table_name::oid
    AND attnum = partition_column_index;
    -- we currently only support partitioning by date, timestamp, and timestamptz
    custom_cast = '';
    IF partition_column_type <> 'date'::regtype
    AND partition_column_type <> 'timestamp'::regtype
    AND partition_column_type <> 'timestamptz'::regtype THEN
      SELECT EXISTS(SELECT OID FROM pg_cast WHERE castsource = partition_column_type AND casttarget = 'timestamptz'::regtype) AND
             EXISTS(SELECT OID FROM pg_cast WHERE castsource = 'timestamptz'::regtype AND casttarget = partition_column_type)
      INTO is_partition_column_castable;
      IF not is_partition_column_castable THEN
        RAISE 'type of the partition column of the table % must be date, timestamp or timestamptz', table_name;
      END IF;
      custom_cast = format('::%s', partition_column_type);
    END IF;
    IF partition_column_type = 'date'::regtype AND partition_interval IS NOT NULL THEN
        SELECT date_trunc('day', partition_interval) = partition_interval
        INTO is_day_multiple;
        IF NOT is_day_multiple THEN
            RAISE 'partition interval of date partitioned table must be day or multiple days';
        END IF;
    END IF;
    -- If no partition exists, truncate from_value to find intuitive initial value.
    -- If any partition exist, use the initial partition as the pivot partition.
    -- tp.to_value and tp.from_value are equal to '', if default partition exists.
    EXECUTE format('SELECT tp.from_value%1$s::timestamptz, tp.to_value%1$s::timestamptz
        FROM pg_catalog.time_partitions tp
        WHERE parent_table = $1 AND tp.to_value <> '' AND tp.from_value <> ''
        ORDER BY tp.from_value%1$s::timestamptz ASC
        LIMIT 1', custom_cast)
    INTO current_range_from_value, current_range_to_value
    USING table_name;
    IF current_range_from_value is NULL THEN
        -- Decide on the current_range_from_value of the initial partition according to interval of the table.
        -- Since we will create all other partitions by adding intervals, truncating given start time will provide
        -- more intuitive interval ranges, instead of starting from from_value directly.
        IF partition_interval < INTERVAL '1 hour' THEN
            current_range_from_value = date_trunc('minute', from_value);
        ELSIF partition_interval < INTERVAL '1 day' THEN
            current_range_from_value = date_trunc('hour', from_value);
        ELSIF partition_interval < INTERVAL '1 week' THEN
            current_range_from_value = date_trunc('day', from_value);
        ELSIF partition_interval < INTERVAL '1 month' THEN
            current_range_from_value = date_trunc('week', from_value);
        ELSIF partition_interval = INTERVAL '3 months' THEN
            current_range_from_value = date_trunc('quarter', from_value);
        ELSIF partition_interval < INTERVAL '1 year' THEN
            current_range_from_value = date_trunc('month', from_value);
        ELSE
            current_range_from_value = date_trunc('year', from_value);
        END IF;
        current_range_to_value := current_range_from_value + partition_interval;
    ELSE
        -- if from_value is newer than pivot's from value, go forward, else go backward
        IF from_value >= current_range_from_value THEN
            WHILE current_range_from_value < from_value LOOP
                    current_range_from_value := current_range_from_value + partition_interval;
            END LOOP;
        ELSE
            WHILE current_range_from_value > from_value LOOP
                    current_range_from_value := current_range_from_value - partition_interval;
            END LOOP;
        END IF;
        current_range_to_value := current_range_from_value + partition_interval;
    END IF;
    -- reuse pg_partman naming scheme for back-and-forth migration
    IF partition_interval = INTERVAL '3 months' THEN
        -- include quarter in partition name
        partition_name_format = 'YYYY"q"Q';
    ELSIF partition_interval = INTERVAL '1 week' THEN
        -- include week number in partition name
        partition_name_format := 'IYYY"w"IW';
    ELSE
        -- always start with the year
        partition_name_format := 'YYYY';
        IF partition_interval < INTERVAL '1 year' THEN
            -- include month in partition name
            partition_name_format := partition_name_format || '_MM';
        END IF;
        IF partition_interval < INTERVAL '1 month' THEN
            -- include day of month in partition name
            partition_name_format := partition_name_format || '_DD';
        END IF;
        IF partition_interval < INTERVAL '1 day' THEN
            -- include time of day in partition name
            partition_name_format := partition_name_format || '_HH24MI';
        END IF;
        IF partition_interval < INTERVAL '1 minute' THEN
             -- include seconds in time of day in partition name
             partition_name_format := partition_name_format || 'SS';
        END IF;
    END IF;
    partition_exist_query = format('SELECT partition FROM pg_catalog.time_partitions tp
        WHERE tp.from_value%1$s::timestamptz = $1 AND tp.to_value%1$s::timestamptz = $2 AND parent_table = $3',
        custom_cast);
    partition_covers_query = format('SELECT partition, tp.from_value, tp.to_value
        FROM pg_catalog.time_partitions tp
        WHERE
            (($1 >= tp.from_value%1$s::timestamptz AND $1 < tp.to_value%1$s::timestamptz) OR
            ($2 > tp.from_value%1$s::timestamptz AND $2 < tp.to_value%1$s::timestamptz)) AND
            parent_table = $3',
        custom_cast);
    WHILE current_range_from_value < to_value LOOP
        -- Check whether partition with given range has already been created
        -- Since partition interval can be given with different types, we are converting
        -- all variables to timestamptz to make sure that we are comparing same type of parameters
        EXECUTE partition_exist_query into partition using current_range_from_value, current_range_to_value, table_name;
        IF partition is not NULL THEN
            current_range_from_value := current_range_to_value;
            current_range_to_value := current_range_to_value + partition_interval;
            CONTINUE;
        END IF;
        -- Check whether any other partition covers from_value or to_value
        -- That means some partitions doesn't align with the initial partition.
        -- In other words, gap(s) exist between partitions which is not multiple of intervals.
        EXECUTE partition_covers_query
        INTO manual_partition, manual_partition_from_value_text, manual_partition_to_value_text
        using current_range_from_value, current_range_to_value, table_name;
        IF manual_partition is not NULL THEN
            RAISE 'partition % with the range from % to % does not align with the initial partition given the partition interval',
            manual_partition::text,
            manual_partition_from_value_text,
            manual_partition_to_value_text
            USING HINT = 'Only use partitions of the same size, without gaps between partitions.';
        END IF;
        IF partition_column_type = 'date'::regtype THEN
            SELECT current_range_from_value::date::text INTO current_range_from_value_text;
            SELECT current_range_to_value::date::text INTO current_range_to_value_text;
        ELSIF partition_column_type = 'timestamp without time zone'::regtype THEN
            SELECT current_range_from_value::timestamp::text INTO current_range_from_value_text;
            SELECT current_range_to_value::timestamp::text INTO current_range_to_value_text;
        ELSIF partition_column_type = 'timestamp with time zone'::regtype THEN
            SELECT current_range_from_value::timestamptz::text INTO current_range_from_value_text;
            SELECT current_range_to_value::timestamptz::text INTO current_range_to_value_text;
        ELSE
            EXECUTE format('SELECT $1%s::text', custom_cast) INTO current_range_from_value_text using current_range_from_value;
            EXECUTE format('SELECT $1%s::text', custom_cast) INTO current_range_to_value_text using current_range_to_value;
        END IF;
        -- use range values within the name of partition to have unique partition names
        RETURN QUERY
        SELECT
            substring(table_name_text, 0, max_table_name_length - length(to_char(current_range_from_value, partition_name_format)) - 1) || '_p' ||
            to_char(current_range_from_value, partition_name_format),
            current_range_from_value_text,
            current_range_to_value_text;
        current_range_from_value := current_range_to_value;
        current_range_to_value := current_range_to_value + partition_interval;
    END LOOP;
    RETURN;
END;
$$;
COMMENT ON FUNCTION pg_catalog.get_missing_time_partition_ranges(
    table_name regclass,
    partition_interval INTERVAL,
    to_value timestamptz,
    from_value timestamptz)
IS 'get missing partitions ranges for table within the range using the given interval';
-- Update the default rebalance strategy to 'by_disk_size', but only if the
-- default is currently 'by_shard_count'
SELECT citus_set_default_rebalance_strategy(name)
FROM pg_dist_rebalance_strategy
WHERE name = 'by_disk_size'
    AND (SELECT default_strategy FROM pg_dist_rebalance_strategy WHERE name = 'by_shard_count');
