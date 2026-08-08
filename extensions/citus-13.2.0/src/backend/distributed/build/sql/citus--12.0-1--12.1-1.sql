-- citus--12.0-1--12.1-1
-- bump version to 12.1-1
CREATE FUNCTION pg_catalog.citus_pause_node_within_txn(node_id int,
                                              force bool DEFAULT false,
                                              lock_cooldown int DEFAULT 10000)
  RETURNS void
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$citus_pause_node_within_txn$$;
COMMENT ON FUNCTION pg_catalog.citus_pause_node_within_txn(node_id int,
                                              force bool ,
                                              lock_cooldown int )
  IS 'pauses node with given id which leads to add lock in tables and prevent any queries to be executed on that node';
REVOKE ALL ON FUNCTION pg_catalog.citus_pause_node_within_txn(int,bool,int) FROM PUBLIC;
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
    -- We should drop any_value because PG16 has its own any_value function
    -- We can remove this part when we drop support for PG16
    DELETE FROM pg_depend WHERE
        objid IN (SELECT oid FROM pg_proc WHERE proname = 'any_value' OR proname = 'any_value_agg') AND
        refobjid IN (select oid from pg_extension where extname = 'citus');
    DROP AGGREGATE IF EXISTS pg_catalog.any_value(anyelement);
    DROP FUNCTION IF EXISTS pg_catalog.any_value_agg(anyelement, anyelement);
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
    -- if we are upgrading from PG14/PG15 to PG16+,
    -- we will need to regenerate the partkeys because they will include varnullingrels as well.
    -- so we save the partkeys as column names here
    CREATE TABLE IF NOT EXISTS public.pg_dist_partkeys_pre_16_upgrade AS
    SELECT logicalrelid, column_to_column_name(logicalrelid, partkey) as col_name
    FROM pg_catalog.pg_dist_partition WHERE partkey IS NOT NULL AND partkey NOT ILIKE '%varnullingrels%';
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
    -- PG16 has its own any_value, so only create it pre PG16.
    -- We can remove this part when we drop support for PG16
    IF substring(current_Setting('server_version'), '\d+')::int < 16 THEN
    EXECUTE $cmd$
        -- disable propagation to prevent EnsureCoordinator errors
        -- the aggregate created here does not depend on Citus extension (yet)
        -- since we add the dependency with the next command
        SET citus.enable_ddl_propagation TO OFF;
        CREATE OR REPLACE FUNCTION pg_catalog.any_value_agg ( anyelement, anyelement )
        RETURNS anyelement AS $$
                SELECT CASE WHEN $1 IS NULL THEN $2 ELSE $1 END;
        $$ LANGUAGE SQL STABLE;
        CREATE AGGREGATE pg_catalog.any_value (
                sfunc = pg_catalog.any_value_agg,
                combinefunc = pg_catalog.any_value_agg,
                basetype = anyelement,
                stype = anyelement
        );
        COMMENT ON AGGREGATE pg_catalog.any_value(anyelement) IS
            'Returns the value of any row in the group. It is mostly useful when you know there will be only 1 element.';
        RESET citus.enable_ddl_propagation;
        --
        -- Citus creates the any_value aggregate but because of a compatibility
        -- issue between pg15-pg16 -- any_value is created in PG16, we drop
        -- and create it during upgrade IF upgraded version is less than 16.
        -- And as Citus creates it, there needs to be a dependency to the
        -- Citus extension, so we create that dependency here.
        INSERT INTO pg_depend
        SELECT
            'pg_proc'::regclass::oid as classid,
            (SELECT oid FROM pg_proc WHERE proname = 'any_value_agg') as objid,
            0 as objsubid,
            'pg_extension'::regclass::oid as refclassid,
            (select oid from pg_extension where extname = 'citus') as refobjid,
            0 as refobjsubid ,
            'e' as deptype;
        INSERT INTO pg_depend
        SELECT
            'pg_proc'::regclass::oid as classid,
            (SELECT oid FROM pg_proc WHERE proname = 'any_value') as objid,
            0 as objsubid,
            'pg_extension'::regclass::oid as refclassid,
            (select oid from pg_extension where extname = 'citus') as refobjid,
            0 as refobjsubid ,
            'e' as deptype;
    $cmd$;
    END IF;
    --
    -- restore citus catalog tables
    --
    INSERT INTO pg_catalog.pg_dist_partition SELECT * FROM public.pg_dist_partition;
    -- if we are upgrading from PG14/PG15 to PG16+,
    -- we need to regenerate the partkeys because they will include varnullingrels as well.
    UPDATE pg_catalog.pg_dist_partition
    SET partkey = column_name_to_column(pg_dist_partkeys_pre_16_upgrade.logicalrelid, col_name)
    FROM public.pg_dist_partkeys_pre_16_upgrade
    WHERE pg_dist_partkeys_pre_16_upgrade.logicalrelid = pg_dist_partition.logicalrelid;
    DROP TABLE public.pg_dist_partkeys_pre_16_upgrade;
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
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_update_none_dist_table_metadata(
    relation_id oid,
    replication_model "char",
    colocation_id bigint,
    auto_converted boolean)
RETURNS void
LANGUAGE C
VOLATILE
AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_update_none_dist_table_metadata(oid, "char", bigint, boolean)
    IS 'Update pg_dist_partition metadata table for given none-distributed table, to convert it to another type of none-distributed table.';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_delete_placement_metadata(
    placement_id bigint)
RETURNS void
LANGUAGE C
VOLATILE
AS 'MODULE_PATHNAME',
$$citus_internal_delete_placement_metadata$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_delete_placement_metadata(bigint)
    IS 'Delete placement with given id from pg_dist_placement metadata table.';
-- citus_schema_move, using target node name and node port
CREATE OR REPLACE FUNCTION pg_catalog.citus_schema_move(
 schema_id regnamespace,
 target_node_name text,
 target_node_port integer,
 shard_transfer_mode citus.shard_transfer_mode default 'auto')
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_schema_move$$;
COMMENT ON FUNCTION pg_catalog.citus_schema_move(
 schema_id regnamespace,
 target_node_name text,
 target_node_port integer,
 shard_transfer_mode citus.shard_transfer_mode)
IS 'move a distributed schema to given node';
-- citus_schema_move, using target node id
CREATE OR REPLACE FUNCTION pg_catalog.citus_schema_move(
 schema_id regnamespace,
 target_node_id integer,
 shard_transfer_mode citus.shard_transfer_mode default 'auto')
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_schema_move_with_nodeid$$;
COMMENT ON FUNCTION pg_catalog.citus_schema_move(
 schema_id regnamespace,
 target_node_id integer,
 shard_transfer_mode citus.shard_transfer_mode)
IS 'move a distributed schema to given node';
