-- citus--10.1-1--10.2-1
-- bump version to 10.2-1
DROP FUNCTION IF EXISTS pg_catalog.stop_metadata_sync_to_node(text, integer);
GRANT ALL ON FUNCTION pg_catalog.worker_record_sequence_dependency(regclass,regclass,name) TO PUBLIC;
-- the same shard cannot have placements on different nodes
ALTER TABLE pg_catalog.pg_dist_placement ADD CONSTRAINT placement_shardid_groupid_unique_index UNIQUE (shardid, groupid);
CREATE FUNCTION pg_catalog.stop_metadata_sync_to_node(nodename text, nodeport integer, clear_metadata bool DEFAULT true)
 RETURNS VOID
 LANGUAGE C STRICT
 AS 'MODULE_PATHNAME', $$stop_metadata_sync_to_node$$;
COMMENT ON FUNCTION pg_catalog.stop_metadata_sync_to_node(nodename text, nodeport integer, clear_metadata bool)
    IS 'stop metadata sync to node';
--#include "../../columnar/sql/columnar--10.1-1--10.2-1.sql"
DO $check_columnar$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension AS e
             INNER JOIN pg_catalog.pg_depend AS d ON (d.refobjid = e.oid)
             INNER JOIN pg_catalog.pg_proc AS p ON (p.oid = d.objid)
             WHERE e.extname='citus_columnar' and p.proname = 'columnar_handler'
  ) THEN
-- columnar--10.1-1--10.2-1.sql
-- For a proper mapping between tid & (stripe, row_num), add a new column to
-- columnar.stripe and define a BTREE index on this column.
-- Also include storage_id column for per-relation scans.
ALTER TABLE columnar.stripe ADD COLUMN first_row_number bigint;
CREATE INDEX stripe_first_row_number_idx ON columnar.stripe USING BTREE(storage_id, first_row_number);
-- Populate first_row_number column of columnar.stripe table.
--
-- For simplicity, we calculate MAX(row_count) value across all the stripes
-- of all the columanar tables and then use it to populate first_row_number
-- column. This would introduce some gaps however we are okay with that since
-- it's already the case with regular INSERT/COPY's.
DO $$
DECLARE
  max_row_count bigint;
  -- this should be equal to columnar_storage.h/COLUMNAR_FIRST_ROW_NUMBER
  COLUMNAR_FIRST_ROW_NUMBER constant bigint := 1;
BEGIN
  SELECT MAX(row_count) INTO max_row_count FROM columnar.stripe;
  UPDATE columnar.stripe SET first_row_number = COLUMNAR_FIRST_ROW_NUMBER +
                                                (stripe_num - 1) * max_row_count;
END;
$$;
CREATE OR REPLACE FUNCTION citus_internal.upgrade_columnar_storage(rel regclass)
  RETURNS VOID
  STRICT
  LANGUAGE c AS 'MODULE_PATHNAME', $$upgrade_columnar_storage$$;
COMMENT ON FUNCTION citus_internal.upgrade_columnar_storage(regclass)
  IS 'function to upgrade the columnar storage, if necessary';
CREATE OR REPLACE FUNCTION citus_internal.downgrade_columnar_storage(rel regclass)
  RETURNS VOID
  STRICT
  LANGUAGE c AS 'MODULE_PATHNAME', $$downgrade_columnar_storage$$;
COMMENT ON FUNCTION citus_internal.downgrade_columnar_storage(regclass)
  IS 'function to downgrade the columnar storage, if necessary';
-- upgrade storage for all columnar relations
PERFORM citus_internal.upgrade_columnar_storage(c.oid) FROM pg_class c, pg_am a
  WHERE c.relam = a.oid AND amname = 'columnar';
  END IF;
END;
$check_columnar$;
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_partition_metadata(
       relation_id regclass, distribution_method "char",
       distribution_column text, colocation_id integer,
       replication_model "char")
    RETURNS void
    LANGUAGE C
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_add_partition_metadata(regclass, "char", text, integer, "char") IS
    'Inserts into pg_dist_partition with user checks';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_shard_metadata(
       relation_id regclass, shard_id bigint,
       storage_type "char", shard_min_value text,
       shard_max_value text
       )
    RETURNS void
    LANGUAGE C
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_add_shard_metadata(regclass, bigint, "char", text, text) IS
    'Inserts into pg_dist_shard with user checks';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_placement_metadata(
       shard_id bigint, shard_state integer,
       shard_length bigint, group_id integer,
       placement_id bigint)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_add_placement_metadata(bigint, integer, bigint, integer, bigint) IS
    'Inserts into pg_dist_shard_placement with user checks';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_update_placement_metadata(
       shard_id bigint, source_group_id integer,
       target_group_id integer)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_update_placement_metadata(bigint, integer, integer) IS
    'Updates into pg_dist_placement with user checks';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_delete_shard_metadata(shard_id bigint)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_delete_shard_metadata(bigint) IS
    'Deletes rows from pg_dist_shard and pg_dist_shard_placement with user checks';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_update_relation_colocation(relation_id Oid, target_colocation_id int)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_update_relation_colocation(oid, int) IS
    'Updates colocationId field of pg_dist_partition for the relation_id';
CREATE OR REPLACE FUNCTION pg_catalog.create_time_partitions(
    table_name regclass,
    partition_interval INTERVAL,
    end_at timestamptz,
    start_from timestamptz DEFAULT now())
returns boolean
LANGUAGE plpgsql
AS $$
DECLARE
    -- partitioned table name
    schema_name_text name;
    table_name_text name;
    -- record for to-be-created partition
    missing_partition_record record;
    -- result indiciates whether any partitions were created
    partition_created bool := false;
BEGIN
    IF start_from >= end_at THEN
        RAISE 'start_from (%) must be older than end_at (%)', start_from, end_at;
    END IF;
    SELECT nspname, relname
    INTO schema_name_text, table_name_text
    FROM pg_class JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
    WHERE pg_class.oid = table_name::oid;
    -- Get missing partition range info using the get_missing_partition_ranges
    -- and create partitions using that info.
    FOR missing_partition_record IN
        SELECT *
        FROM get_missing_time_partition_ranges(table_name, partition_interval, end_at, start_from)
    LOOP
        EXECUTE format('CREATE TABLE %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
        schema_name_text,
        missing_partition_record.partition_name,
        schema_name_text,
        table_name_text,
        missing_partition_record.range_from_value,
        missing_partition_record.range_to_value);
        partition_created := true;
    END LOOP;
    RETURN partition_created;
END;
$$;
COMMENT ON FUNCTION pg_catalog.create_time_partitions(
    table_name regclass,
    partition_interval INTERVAL,
    end_at timestamptz,
    start_from timestamptz)
IS 'create time partitions for the given range';
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
    IF partition_column_type <> 'date'::regtype
    AND partition_column_type <> 'timestamp'::regtype
    AND partition_column_type <> 'timestamptz'::regtype THEN
        RAISE 'type of the partition column of the table % must be date, timestamp or timestamptz', table_name;
    END IF;
    FOR r IN
  SELECT partition, nspname AS schema_name, relname AS table_name, from_value, to_value
  FROM pg_catalog.time_partitions, pg_catalog.pg_class c, pg_catalog.pg_namespace n
  WHERE parent_table = table_name AND partition = c.oid AND c.relnamespace = n.oid
  AND to_value IS NOT NULL
  AND to_value::timestamptz <= older_than
  ORDER BY to_value::timestamptz
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
    IF partition_column_type <> 'date'::regtype
    AND partition_column_type <> 'timestamp'::regtype
    AND partition_column_type <> 'timestamptz'::regtype THEN
        RAISE 'type of the partition column of the table % must be date, timestamp or timestamptz', table_name;
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
    SELECT tp.from_value::timestamptz, tp.to_value::timestamptz
    INTO current_range_from_value, current_range_to_value
    FROM pg_catalog.time_partitions tp
    WHERE parent_table = table_name AND tp.to_value <> '' AND tp.from_value <> ''
    ORDER BY tp.from_value::timestamptz ASC
    LIMIT 1;
    IF NOT FOUND THEN
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
    WHILE current_range_from_value < to_value LOOP
        -- Check whether partition with given range has already been created
        -- Since partition interval can be given with different types, we are converting
        -- all variables to timestamptz to make sure that we are comparing same type of parameters
        PERFORM * FROM pg_catalog.time_partitions tp
        WHERE
            tp.from_value::timestamptz = current_range_from_value::timestamptz AND
            tp.to_value::timestamptz = current_range_to_value::timestamptz AND
            parent_table = table_name;
        IF found THEN
            current_range_from_value := current_range_to_value;
            current_range_to_value := current_range_to_value + partition_interval;
            CONTINUE;
        END IF;
        -- Check whether any other partition covers from_value or to_value
        -- That means some partitions doesn't align with the initial partition.
        -- In other words, gap(s) exist between partitions which is not multiple of intervals.
        SELECT partition, tp.from_value::text, tp.to_value::text
        INTO manual_partition, manual_partition_from_value_text, manual_partition_to_value_text
        FROM pg_catalog.time_partitions tp
        WHERE
            ((current_range_from_value::timestamptz >= tp.from_value::timestamptz AND current_range_from_value < tp.to_value::timestamptz) OR
            (current_range_to_value::timestamptz > tp.from_value::timestamptz AND current_range_to_value::timestamptz < tp.to_value::timestamptz)) AND
            parent_table = table_name;
        IF found THEN
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
            RAISE 'type of the partition column of the table % must be date, timestamp or timestamptz', table_name;
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
CREATE FUNCTION pg_catalog.worker_nextval(sequence regclass)
    RETURNS int
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_nextval$$;
COMMENT ON FUNCTION pg_catalog.worker_nextval(regclass)
    IS 'calculates nextval() for column defaults of type int or smallint';
DROP FUNCTION pg_catalog.citus_drop_all_shards(regclass, text, text);
CREATE FUNCTION pg_catalog.citus_drop_all_shards(logicalrelid regclass,
                                                 schema_name text,
                                                 table_name text,
                                                 drop_shards_metadata_only boolean default false)
    RETURNS integer
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_drop_all_shards$$;
COMMENT ON FUNCTION pg_catalog.citus_drop_all_shards(regclass, text, text, boolean)
    IS 'drop all shards in a relation and update metadata';
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
    -- remove entries from citus.pg_dist_object for all dropped root (objsubid = 0) objects
    FOR v_obj IN SELECT * FROM pg_event_trigger_dropped_objects()
    LOOP
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
    IF substring(current_Setting('server_version'), '\d+')::int >= 14 THEN
    EXECUTE $cmd$
        CREATE AGGREGATE array_cat_agg(anycompatiblearray) (SFUNC = array_cat, STYPE = anycompatiblearray);
        COMMENT ON AGGREGATE array_cat_agg(anycompatiblearray)
        IS 'concatenate input arrays into a single array';
    $cmd$;
    ELSE
    EXECUTE $cmd$
        CREATE AGGREGATE array_cat_agg(anyarray) (SFUNC = array_cat, STYPE = anyarray);
        COMMENT ON AGGREGATE array_cat_agg(anyarray)
        IS 'concatenate input arrays into a single array';
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
