-- citus_locks combines the pg_locks views from all nodes and adds global_pid, nodeid, and
-- relation_name. The columns of citus_locks don't change based on the Postgres version,
-- however the pg_locks's columns do. Postgres 14 added one more column to pg_locks
-- (waitstart timestamptz). citus_locks has the most expansive column set, including the
-- newly added column. If citus_locks is queried in a Postgres version where pg_locks
-- doesn't have some columns, the values for those columns in citus_locks will be NULL
CREATE OR REPLACE FUNCTION pg_catalog.citus_locks (
    OUT global_pid bigint,
    OUT nodeid int,
    OUT locktype text,
    OUT database oid,
    OUT relation oid,
    OUT relation_name text,
    OUT page integer,
    OUT tuple smallint,
    OUT virtualxid text,
    OUT transactionid xid,
    OUT classid oid,
    OUT objid oid,
    OUT objsubid smallint,
    OUT virtualtransaction text,
    OUT pid integer,
    OUT mode text,
    OUT granted boolean,
    OUT fastpath boolean,
    OUT waitstart timestamp with time zone
)
    RETURNS SETOF record
    LANGUAGE plpgsql
    AS $function$
BEGIN
    RETURN QUERY
    SELECT *
    FROM jsonb_to_recordset((
        SELECT
            jsonb_agg(all_citus_locks_rows_as_jsonb.citus_locks_row_as_jsonb)::jsonb
        FROM (
            SELECT
                jsonb_array_elements(run_command_on_all_nodes.result::jsonb)::jsonb ||
                    ('{"nodeid":' || run_command_on_all_nodes.nodeid || '}')::jsonb AS citus_locks_row_as_jsonb
            FROM
                run_command_on_all_nodes (
                    $$
                        SELECT
                            coalesce(to_jsonb (array_agg(citus_locks_from_one_node.*)), '[{}]'::jsonb)
                        FROM (
                            SELECT
                                global_pid, pg_locks.relation::regclass::text AS relation_name, pg_locks.*
                            FROM pg_locks
                        LEFT JOIN get_all_active_transactions () ON process_id = pid) AS citus_locks_from_one_node;
                    $$,
                    parallel:= TRUE,
                    give_warning_for_connection_errors:= TRUE)
            WHERE
                success = 't')
        AS all_citus_locks_rows_as_jsonb))
AS (
    global_pid bigint,
    nodeid int,
    locktype text,
    database oid,
    relation oid,
    relation_name text,
    page integer,
    tuple smallint,
    virtualxid text,
    transactionid xid,
    classid oid,
    objid oid,
    objsubid smallint,
    virtualtransaction text,
    pid integer,
    mode text,
    granted boolean,
    fastpath boolean,
    waitstart timestamp with time zone
);
END;
$function$;
CREATE OR REPLACE VIEW citus.citus_locks AS
SELECT * FROM pg_catalog.citus_locks();
ALTER VIEW citus.citus_locks SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_locks TO PUBLIC;
DO $$
declare
citus_tables_create_query text;
BEGIN
citus_tables_create_query=$CTCQ$
    CREATE OR REPLACE VIEW %I.citus_tables AS
    SELECT
        logicalrelid AS table_name,
        CASE WHEN partkey IS NOT NULL THEN 'distributed' ELSE
            CASE when repmodel = 't' THEN 'reference' ELSE 'local' END
        END AS citus_table_type,
        coalesce(column_to_column_name(logicalrelid, partkey), '<none>') AS distribution_column,
        colocationid AS colocation_id,
        pg_size_pretty(citus_total_relation_size(logicalrelid, fail_on_error := false)) AS table_size,
        (select count(*) from pg_dist_shard where logicalrelid = p.logicalrelid) AS shard_count,
        pg_get_userbyid(relowner) AS table_owner,
        amname AS access_method
    FROM
        pg_dist_partition p
    JOIN
        pg_class c ON (p.logicalrelid = c.oid)
    LEFT JOIN
        pg_am a ON (a.oid = c.relam)
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
GRANT SELECT ON pg_catalog.citus_shards TO public;
CREATE FUNCTION pg_catalog.create_distributed_table_concurrently(table_name regclass,
                                                                 distribution_column text,
                                                                 distribution_type citus.distribution_type DEFAULT 'hash',
                                                                 colocate_with text DEFAULT 'default',
                                                                 shard_count int DEFAULT NULL)
  RETURNS void
  LANGUAGE C
  AS 'MODULE_PATHNAME', $$create_distributed_table_concurrently$$;
COMMENT ON FUNCTION pg_catalog.create_distributed_table_concurrently(table_name regclass,
                                                                     distribution_column text,
                                                                     distribution_type citus.distribution_type,
                                                                     colocate_with text,
                                                                     shard_count int)
    IS 'creates a distributed table and avoids blocking writes';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_delete_partition_metadata(table_name regclass)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_delete_partition_metadata(regclass) IS
    'Deletes a row from pg_dist_partition with table ownership checks';
DROP FUNCTION pg_catalog.citus_copy_shard_placement;
CREATE FUNCTION pg_catalog.citus_copy_shard_placement(
 shard_id bigint,
 source_node_name text,
 source_node_port integer,
 target_node_name text,
 target_node_port integer,
 transfer_mode citus.shard_transfer_mode default 'auto')
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_copy_shard_placement$$;
COMMENT ON FUNCTION pg_catalog.citus_copy_shard_placement(shard_id bigint,
 source_node_name text,
 source_node_port integer,
 target_node_name text,
 target_node_port integer,
 shard_transfer_mode citus.shard_transfer_mode)
IS 'copy a shard from the source node to the destination node';
-- We should not introduce breaking sql changes to upgrade files after they are released.
-- We did that for worker_fetch_foreign_file in v9.0.0 and worker_repartition_cleanup in v9.2.0.
-- When we try to drop those udfs in that file, they were missing for some clients unexpectedly
-- due to buggy changes in old upgrade scripts. For that case, the fix is to change DROP statements
-- with DROP IF EXISTS for those 2 udfs in 11.0-4--11.1-1.
-- Fixes an upgrade problem for worker_fetch_foreign_file when upgrade starts from 8.3 up to 11.1
-- Fixes an upgrade problem for worker_repartition_cleanup when upgrade starts from 9.1 up to 11.1
-- Refer the related PR https:
DROP FUNCTION IF EXISTS pg_catalog.worker_fetch_foreign_file(text, text, bigint, text[], integer[]);
DROP FUNCTION IF EXISTS pg_catalog.worker_repartition_cleanup(bigint);
DROP FUNCTION pg_catalog.worker_create_schema(bigint,text);
DROP FUNCTION pg_catalog.worker_cleanup_job_schema_cache();
DROP FUNCTION pg_catalog.worker_fetch_partition_file(bigint, integer, integer, integer, text, integer);
DROP FUNCTION pg_catalog.worker_hash_partition_table(bigint, integer, text, text, oid, anyarray);
DROP FUNCTION pg_catalog.worker_merge_files_into_table(bigint, integer, text[], text[]);
DROP FUNCTION pg_catalog.worker_range_partition_table(bigint, integer, text, text, oid, anyarray);
DO $check_columnar$
BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension AS e
             INNER JOIN pg_catalog.pg_depend AS d ON (d.refobjid = e.oid)
             INNER JOIN pg_catalog.pg_proc AS p ON (p.oid = d.objid)
             WHERE e.extname='citus_columnar' and p.proname = 'columnar_handler'
  ) THEN
CREATE OR REPLACE FUNCTION pg_catalog.alter_columnar_table_set(
    table_name regclass,
    chunk_group_row_limit int DEFAULT NULL,
    stripe_row_limit int DEFAULT NULL,
    compression name DEFAULT null,
    compression_level int DEFAULT NULL)
    RETURNS void
    LANGUAGE plpgsql AS
$alter_columnar_table_set$
declare
  noop BOOLEAN := true;
  cmd TEXT := 'ALTER TABLE ' || table_name::text || ' SET (';
begin
  if (chunk_group_row_limit is not null) then
    if (not noop) then cmd := cmd || ', '; end if;
    cmd := cmd || 'columnar.chunk_group_row_limit=' || chunk_group_row_limit;
    noop := false;
  end if;
  if (stripe_row_limit is not null) then
    if (not noop) then cmd := cmd || ', '; end if;
    cmd := cmd || 'columnar.stripe_row_limit=' || stripe_row_limit;
    noop := false;
  end if;
  if (compression is not null) then
    if (not noop) then cmd := cmd || ', '; end if;
    cmd := cmd || 'columnar.compression=' || compression;
    noop := false;
  end if;
  if (compression_level is not null) then
    if (not noop) then cmd := cmd || ', '; end if;
    cmd := cmd || 'columnar.compression_level=' || compression_level;
    noop := false;
  end if;
  cmd := cmd || ')';
  if (not noop) then
    execute cmd;
  end if;
  return;
end;
$alter_columnar_table_set$;
COMMENT ON FUNCTION pg_catalog.alter_columnar_table_set(
    table_name regclass,
    chunk_group_row_limit int,
    stripe_row_limit int,
    compression name,
    compression_level int)
IS 'set one or more options on a columnar table, when set to NULL no change is made';
CREATE OR REPLACE FUNCTION pg_catalog.alter_columnar_table_reset(
    table_name regclass,
    chunk_group_row_limit bool DEFAULT false,
    stripe_row_limit bool DEFAULT false,
    compression bool DEFAULT false,
    compression_level bool DEFAULT false)
    RETURNS void
    LANGUAGE plpgsql AS
$alter_columnar_table_reset$
declare
  noop BOOLEAN := true;
  cmd TEXT := 'ALTER TABLE ' || table_name::text || ' RESET (';
begin
  if (chunk_group_row_limit) then
    if (not noop) then cmd := cmd || ', '; end if;
    cmd := cmd || 'columnar.chunk_group_row_limit';
    noop := false;
  end if;
  if (stripe_row_limit) then
    if (not noop) then cmd := cmd || ', '; end if;
    cmd := cmd || 'columnar.stripe_row_limit';
    noop := false;
  end if;
  if (compression) then
    if (not noop) then cmd := cmd || ', '; end if;
    cmd := cmd || 'columnar.compression';
    noop := false;
  end if;
  if (compression_level) then
    if (not noop) then cmd := cmd || ', '; end if;
    cmd := cmd || 'columnar.compression_level';
    noop := false;
  end if;
  cmd := cmd || ')';
  if (not noop) then
    execute cmd;
  end if;
  return;
end;
$alter_columnar_table_reset$;
COMMENT ON FUNCTION pg_catalog.alter_columnar_table_reset(
    table_name regclass,
    chunk_group_row_limit bool,
    stripe_row_limit bool,
    compression bool,
    compression_level bool)
IS 'reset on or more options on a columnar table to the system defaults';
-- rename columnar schema to columnar_internal and tighten security
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA columnar FROM PUBLIC;
ALTER SCHEMA columnar RENAME TO columnar_internal;
REVOKE ALL PRIVILEGES ON SCHEMA columnar_internal FROM PUBLIC;
-- create columnar schema with public usage privileges
CREATE SCHEMA columnar;
GRANT USAGE ON SCHEMA columnar TO PUBLIC;
-- update UDF to account for columnar_internal schema
CREATE OR REPLACE FUNCTION citus_internal.columnar_ensure_am_depends_catalog()
  RETURNS void
  LANGUAGE plpgsql
  SET search_path = pg_catalog
AS $func$
BEGIN
  INSERT INTO pg_depend
  WITH columnar_schema_members(relid) AS (
    SELECT pg_class.oid AS relid FROM pg_class
      WHERE relnamespace =
            COALESCE(
        (SELECT pg_namespace.oid FROM pg_namespace WHERE nspname = 'columnar_internal'),
        (SELECT pg_namespace.oid FROM pg_namespace WHERE nspname = 'columnar')
     )
        AND relname IN ('chunk',
                        'chunk_group',
                        'chunk_group_pkey',
                        'chunk_pkey',
                        'options',
                        'options_pkey',
                        'storageid_seq',
                        'stripe',
                        'stripe_first_row_number_idx',
                        'stripe_pkey')
  )
  SELECT -- Define a dependency edge from "columnar table access method" ..
         'pg_am'::regclass::oid as classid,
         (select oid from pg_am where amname = 'columnar') as objid,
         0 as objsubid,
         -- ... to each object that is registered to pg_class and that lives
         -- in "columnar" schema. That contains catalog tables, indexes
         -- created on them and the sequences created in "columnar" schema.
         --
         -- Given the possibility of user might have created their own objects
         -- in columnar schema, we explicitly specify list of objects that we
         -- are interested in.
         'pg_class'::regclass::oid as refclassid,
         columnar_schema_members.relid as refobjid,
         0 as refobjsubid,
         'n' as deptype
  FROM columnar_schema_members
  -- Avoid inserting duplicate entries into pg_depend.
  EXCEPT TABLE pg_depend;
END;
$func$;
COMMENT ON FUNCTION citus_internal.columnar_ensure_am_depends_catalog()
  IS 'internal function responsible for creating dependencies from columnar '
     'table access method to the rel objects in columnar schema';
-- add utility function
CREATE FUNCTION columnar.get_storage_id(regclass) RETURNS bigint
    LANGUAGE C STRICT
    AS 'citus_columnar', $$columnar_relation_storageid$$;
-- create views for columnar table information
CREATE VIEW columnar.storage WITH (security_barrier) AS
  SELECT c.oid::regclass AS relation,
         columnar.get_storage_id(c.oid) AS storage_id
    FROM pg_class c, pg_am am
    WHERE c.relam = am.oid AND am.amname = 'columnar'
      AND pg_has_role(c.relowner, 'USAGE');
COMMENT ON VIEW columnar.storage IS 'Columnar relation ID to storage ID mapping.';
GRANT SELECT ON columnar.storage TO PUBLIC;
CREATE VIEW columnar.options WITH (security_barrier) AS
  SELECT regclass AS relation, chunk_group_row_limit,
         stripe_row_limit, compression, compression_level
    FROM columnar_internal.options o, pg_class c
    WHERE o.regclass = c.oid
      AND pg_has_role(c.relowner, 'USAGE');
COMMENT ON VIEW columnar.options
  IS 'Columnar options for tables on which the current user has ownership privileges.';
GRANT SELECT ON columnar.options TO PUBLIC;
CREATE VIEW columnar.stripe WITH (security_barrier) AS
  SELECT relation, storage.storage_id, stripe_num, file_offset, data_length,
         column_count, chunk_row_count, row_count, chunk_group_count, first_row_number
    FROM columnar_internal.stripe stripe, columnar.storage storage
    WHERE stripe.storage_id = storage.storage_id;
COMMENT ON VIEW columnar.stripe
  IS 'Columnar stripe information for tables on which the current user has ownership privileges.';
GRANT SELECT ON columnar.stripe TO PUBLIC;
CREATE VIEW columnar.chunk_group WITH (security_barrier) AS
  SELECT relation, storage.storage_id, stripe_num, chunk_group_num, row_count
    FROM columnar_internal.chunk_group cg, columnar.storage storage
    WHERE cg.storage_id = storage.storage_id;
COMMENT ON VIEW columnar.chunk_group
  IS 'Columnar chunk group information for tables on which the current user has ownership privileges.';
GRANT SELECT ON columnar.chunk_group TO PUBLIC;
CREATE VIEW columnar.chunk WITH (security_barrier) AS
  SELECT relation, storage.storage_id, stripe_num, attr_num, chunk_group_num,
         minimum_value, maximum_value, value_stream_offset, value_stream_length,
         exists_stream_offset, exists_stream_length, value_compression_type,
         value_compression_level, value_decompressed_length, value_count
    FROM columnar_internal.chunk chunk, columnar.storage storage
    WHERE chunk.storage_id = storage.storage_id;
COMMENT ON VIEW columnar.chunk
  IS 'Columnar chunk information for tables on which the current user has ownership privileges.';
GRANT SELECT ON columnar.chunk TO PUBLIC;
END IF;
END;
$check_columnar$;
-- If upgrading citus, the columnar objects are already being a part of the
-- citus extension, and must be detached so that they can be attached
-- to the citus_columnar extension.
DO $check_citus$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_extension AS e
             INNER JOIN pg_catalog.pg_depend AS d ON (d.refobjid = e.oid)
             INNER JOIN pg_catalog.pg_proc AS p ON (p.oid = d.objid)
             WHERE e.extname='citus' and p.proname = 'columnar_handler'
  ) THEN
    ALTER EXTENSION citus DROP SCHEMA columnar;
    ALTER EXTENSION citus DROP SCHEMA columnar_internal;
    ALTER EXTENSION citus DROP SEQUENCE columnar_internal.storageid_seq;
    -- columnar tables
    ALTER EXTENSION citus DROP TABLE columnar_internal.options;
    ALTER EXTENSION citus DROP TABLE columnar_internal.stripe;
    ALTER EXTENSION citus DROP TABLE columnar_internal.chunk_group;
    ALTER EXTENSION citus DROP TABLE columnar_internal.chunk;
    ALTER EXTENSION citus DROP FUNCTION columnar_internal.columnar_handler;
    ALTER EXTENSION citus DROP ACCESS METHOD columnar;
    ALTER EXTENSION citus DROP FUNCTION pg_catalog.alter_columnar_table_set;
    ALTER EXTENSION citus DROP FUNCTION pg_catalog.alter_columnar_table_reset;
    ALTER EXTENSION citus DROP FUNCTION columnar.get_storage_id;
    -- columnar view
    ALTER EXTENSION citus DROP VIEW columnar.storage;
    ALTER EXTENSION citus DROP VIEW columnar.options;
    ALTER EXTENSION citus DROP VIEW columnar.stripe;
    ALTER EXTENSION citus DROP VIEW columnar.chunk_group;
    ALTER EXTENSION citus DROP VIEW columnar.chunk;
    -- functions under citus_internal for columnar
    ALTER EXTENSION citus DROP FUNCTION citus_internal.upgrade_columnar_storage;
    ALTER EXTENSION citus DROP FUNCTION citus_internal.downgrade_columnar_storage;
    ALTER EXTENSION citus DROP FUNCTION citus_internal.columnar_ensure_am_depends_catalog;
  END IF;
END $check_citus$;
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
DROP FUNCTION pg_catalog.get_all_active_transactions(OUT datid oid, OUT process_id int, OUT initiator_node_identifier int4,
                                                     OUT worker_query BOOL, OUT transaction_number int8, OUT transaction_stamp timestamptz,
                                                     OUT global_pid int8);
DROP FUNCTION IF EXISTS pg_catalog.get_all_active_transactions();
CREATE OR REPLACE FUNCTION pg_catalog.get_all_active_transactions(OUT datid oid, OUT process_id int, OUT initiator_node_identifier int4,
                                                                  OUT worker_query BOOL, OUT transaction_number int8, OUT transaction_stamp timestamptz,
                                                                  OUT global_pid int8)
RETURNS SETOF RECORD
LANGUAGE C STRICT AS 'MODULE_PATHNAME',
$$get_all_active_transactions$$;
COMMENT ON FUNCTION pg_catalog.get_all_active_transactions(OUT datid oid, OUT process_id int, OUT initiator_node_identifier int4,
                                                           OUT worker_query BOOL, OUT transaction_number int8, OUT transaction_stamp timestamptz,
                                                           OUT global_pid int8)
IS 'returns transaction information for all Citus initiated transactions';
CREATE OR REPLACE FUNCTION pg_catalog.citus_split_shard_by_split_points(
    shard_id bigint,
    split_points text[],
    -- A 'nodeId' is a uint32 in CITUS [1, 4294967296] but postgres does not have unsigned type support.
    -- Use integer (consistent with other previously defined UDFs that take nodeId as integer) as for all practical purposes it is big enough.
    node_ids integer[],
    -- Three modes to be implemented: block_writes, force_logical and auto.
    -- The default mode is auto.
    shard_transfer_mode citus.shard_transfer_mode default 'auto')
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_split_shard_by_split_points$$;
COMMENT ON FUNCTION pg_catalog.citus_split_shard_by_split_points(shard_id bigint, split_points text[], nodeIds integer[], citus.shard_transfer_mode)
    IS 'split a shard using split mode.';
-- We want to create the type in pg_catalog but doing that leads to an error
-- "ERROR:  permission denied to create "pg_catalog.split_copy_info"
-- "DETAIL:  System catalog modifications are currently disallowed. ""
-- As a workaround, we create the type in the citus schema and then later modify it to pg_catalog.
DROP TYPE IF EXISTS citus.split_copy_info;
CREATE TYPE citus.split_copy_info AS (
    destination_shard_id bigint,
    destination_shard_min_value text,
    destination_shard_max_value text,
    -- A 'nodeId' is a uint32 in CITUS [1, 4294967296] but postgres does not have unsigned type support.
    -- Use integer (consistent with other previously defined UDFs that take nodeId as integer) as for all practical purposes it is big enough.
    destination_shard_node_id integer);
ALTER TYPE citus.split_copy_info SET SCHEMA pg_catalog;
CREATE OR REPLACE FUNCTION pg_catalog.worker_split_copy(
    source_shard_id bigint,
 distribution_column text,
    splitCopyInfos pg_catalog.split_copy_info[])
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$worker_split_copy$$;
COMMENT ON FUNCTION pg_catalog.worker_split_copy(source_shard_id bigint, distribution_column text, splitCopyInfos pg_catalog.split_copy_info[])
    IS 'Perform split copy for shard';
CREATE OR REPLACE FUNCTION pg_catalog.worker_copy_table_to_node(
    source_table regclass,
    target_node_id integer)
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$worker_copy_table_to_node$$;
COMMENT ON FUNCTION pg_catalog.worker_copy_table_to_node(regclass, integer)
    IS 'Perform copy of a shard';
CREATE TYPE citus.split_shard_info AS (
    source_shard_id bigint,
    distribution_column text,
    child_shard_id bigint,
    shard_min_value text,
    shard_max_value text,
    node_id integer);
ALTER TYPE citus.split_shard_info SET SCHEMA pg_catalog;
COMMENT ON TYPE pg_catalog.split_shard_info
    IS 'Stores split child shard information';
CREATE TYPE citus.replication_slot_info AS(node_id integer, slot_owner text, slot_name text);
ALTER TYPE citus.replication_slot_info SET SCHEMA pg_catalog;
COMMENT ON TYPE pg_catalog.replication_slot_info
    IS 'Replication slot information to be used for subscriptions during non blocking shard split';
CREATE OR REPLACE FUNCTION pg_catalog.worker_split_shard_replication_setup(
    splitShardInfo pg_catalog.split_shard_info[])
RETURNS setof pg_catalog.replication_slot_info
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$worker_split_shard_replication_setup$$;
COMMENT ON FUNCTION pg_catalog.worker_split_shard_replication_setup(splitShardInfo pg_catalog.split_shard_info[])
    IS 'Replication setup for splitting a shard';
REVOKE ALL ON FUNCTION pg_catalog.worker_split_shard_replication_setup(pg_catalog.split_shard_info[]) FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_isolation_test_session_is_blocked(pBlockedPid integer, pInterestingPids integer[])
RETURNS boolean AS $$
  DECLARE
    mBlockedGlobalPid int8;
    workerProcessId integer := current_setting('citus.isolation_test_session_remote_process_id');
    coordinatorProcessId integer := current_setting('citus.isolation_test_session_process_id');
  BEGIN
    IF pg_catalog.old_pg_isolation_test_session_is_blocked(pBlockedPid, pInterestingPids) THEN
      RETURN true;
    END IF;
    -- pg says we're not blocked locally; check whether we're blocked globally.
    -- Note that worker process may be blocked or waiting for a lock. So we need to
    -- get transaction number for both of them. Following IF provides the transaction
    -- number when the worker process waiting for other session.
    IF EXISTS (SELECT 1 FROM get_global_active_transactions()
               WHERE process_id = workerProcessId AND pBlockedPid = coordinatorProcessId) THEN
      SELECT global_pid INTO mBlockedGlobalPid FROM get_global_active_transactions()
      WHERE process_id = workerProcessId AND pBlockedPid = coordinatorProcessId;
    ELSE
      -- Check whether transactions initiated from the coordinator get locked
      SELECT global_pid INTO mBlockedGlobalPid
        FROM get_all_active_transactions() WHERE process_id = pBlockedPid;
    END IF;
    RETURN EXISTS (
      SELECT 1 FROM citus_internal_global_blocked_processes()
        WHERE waiting_global_pid = mBlockedGlobalPid
    );
  END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION citus_isolation_test_session_is_blocked(integer,integer[]) FROM PUBLIC;
DROP FUNCTION pg_catalog.replicate_reference_tables;
CREATE FUNCTION pg_catalog.replicate_reference_tables(shard_transfer_mode citus.shard_transfer_mode default 'auto')
  RETURNS VOID
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$replicate_reference_tables$$;
COMMENT ON FUNCTION pg_catalog.replicate_reference_tables(citus.shard_transfer_mode)
  IS 'replicate reference tables to all nodes';
REVOKE ALL ON FUNCTION pg_catalog.replicate_reference_tables(citus.shard_transfer_mode) FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.worker_split_shard_release_dsm()
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$worker_split_shard_release_dsm$$;
COMMENT ON FUNCTION pg_catalog.worker_split_shard_release_dsm()
    IS 'Releases shared memory segment allocated by non-blocking split workflow';
REVOKE ALL ON FUNCTION pg_catalog.worker_split_shard_release_dsm() FROM PUBLIC;
DROP FUNCTION pg_catalog.isolate_tenant_to_new_shard(table_name regclass, tenant_id "any", cascade_option text);
CREATE FUNCTION pg_catalog.isolate_tenant_to_new_shard(
  table_name regclass,
  tenant_id "any",
  cascade_option text DEFAULT '',
  shard_transfer_mode citus.shard_transfer_mode DEFAULT 'auto')
RETURNS bigint LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$isolate_tenant_to_new_shard$$;
COMMENT ON FUNCTION pg_catalog.isolate_tenant_to_new_shard(
  table_name regclass,
  tenant_id "any",
  cascade_option text,
  shard_transfer_mode citus.shard_transfer_mode)
IS 'isolate a tenant to its own shard and return the new shard id';
-- Table of records to:
-- 1) Cleanup leftover resources after a failure
-- 2) Deferred drop of old shard placements after a split.
CREATE OR REPLACE PROCEDURE pg_catalog.citus_cleanup_orphaned_resources()
    LANGUAGE C
    AS 'citus', $$citus_cleanup_orphaned_resources$$;
COMMENT ON PROCEDURE pg_catalog.citus_cleanup_orphaned_resources()
    IS 'cleanup orphaned resources';
CREATE TABLE citus.pg_dist_cleanup (
    record_id bigint primary key,
    operation_id bigint not null,
    object_type int not null,
    object_name text not null,
    node_group_id int not null,
    policy_type int not null
);
ALTER TABLE citus.pg_dist_cleanup SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.pg_dist_cleanup TO public;
-- Sequence used to generate operation Ids and record Ids in pg_dist_cleanup_record.
CREATE SEQUENCE citus.pg_dist_operationid_seq;
ALTER SEQUENCE citus.pg_dist_operationid_seq SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.pg_dist_operationid_seq TO public;
CREATE SEQUENCE citus.pg_dist_cleanup_recordid_seq;
ALTER SEQUENCE citus.pg_dist_cleanup_recordid_seq SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.pg_dist_cleanup_recordid_seq TO public;
-- We recreate these two UDF from 11.0-1 on purpose, because we changed their
-- old definition. By recreating it here upgrades also pick up the new changes.
DROP FUNCTION IF EXISTS pg_catalog.pg_cancel_backend(global_pid bigint) CASCADE;
CREATE OR REPLACE FUNCTION pg_catalog.pg_cancel_backend(global_pid bigint)
    RETURNS BOOL
    LANGUAGE C
AS 'MODULE_PATHNAME', $$citus_cancel_backend$$;
COMMENT ON FUNCTION pg_catalog.pg_cancel_backend(global_pid bigint)
    IS 'cancels a Citus query which might be on any node in the Citus cluster';
DROP FUNCTION IF EXISTS pg_catalog.pg_terminate_backend(global_pid bigint, timeout bigint) CASCADE;
CREATE OR REPLACE FUNCTION pg_catalog.pg_terminate_backend(global_pid bigint, timeout bigint DEFAULT 0)
    RETURNS BOOL
    LANGUAGE C
AS 'MODULE_PATHNAME', $$citus_terminate_backend$$;
COMMENT ON FUNCTION pg_catalog.pg_terminate_backend(global_pid bigint, timeout bigint)
    IS 'terminates a Citus query which might be on any node in the Citus cluster';
CREATE TYPE citus.citus_job_status AS ENUM ('scheduled', 'running', 'finished', 'cancelling', 'cancelled', 'failing', 'failed');
ALTER TYPE citus.citus_job_status SET SCHEMA pg_catalog;
CREATE TABLE citus.pg_dist_background_job (
    job_id bigserial NOT NULL,
    state pg_catalog.citus_job_status DEFAULT 'scheduled' NOT NULL,
    job_type name NOT NULL,
    description text NOT NULL,
    started_at timestamptz,
    finished_at timestamptz,
    CONSTRAINT pg_dist_background_job_pkey PRIMARY KEY (job_id)
);
ALTER TABLE citus.pg_dist_background_job SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.pg_dist_background_job TO PUBLIC;
GRANT SELECT ON pg_catalog.pg_dist_background_job_job_id_seq TO PUBLIC;
CREATE TYPE citus.citus_task_status AS ENUM ('blocked', 'runnable', 'running', 'done', 'cancelling', 'error', 'unscheduled', 'cancelled');
ALTER TYPE citus.citus_task_status SET SCHEMA pg_catalog;
CREATE TABLE citus.pg_dist_background_task(
    job_id bigint NOT NULL REFERENCES pg_catalog.pg_dist_background_job(job_id),
    task_id bigserial NOT NULL,
    owner regrole NOT NULL DEFAULT CURRENT_USER::regrole,
    pid integer,
    status pg_catalog.citus_task_status default 'runnable' NOT NULL,
    command text NOT NULL,
    retry_count integer,
    not_before timestamptz, -- can be null to indicate no delay for start of the task, will be set on failure to delay retries
    message text NOT NULL DEFAULT '',
    CONSTRAINT pg_dist_background_task_pkey PRIMARY KEY (task_id),
    CONSTRAINT pg_dist_background_task_job_id_task_id UNIQUE (job_id, task_id) -- required for FK's to enforce tasks only reference other tasks within the same job
);
ALTER TABLE citus.pg_dist_background_task SET SCHEMA pg_catalog;
CREATE INDEX pg_dist_background_task_status_task_id_index ON pg_catalog.pg_dist_background_task USING btree(status, task_id);
GRANT SELECT ON pg_catalog.pg_dist_background_task TO PUBLIC;
GRANT SELECT ON pg_catalog.pg_dist_background_task_task_id_seq TO PUBLIC;
CREATE TABLE citus.pg_dist_background_task_depend(
   job_id bigint NOT NULL REFERENCES pg_catalog.pg_dist_background_job(job_id) ON DELETE CASCADE,
   task_id bigint NOT NULL,
   depends_on bigint NOT NULL,
   PRIMARY KEY (job_id, task_id, depends_on),
   FOREIGN KEY (job_id, task_id) REFERENCES pg_catalog.pg_dist_background_task (job_id, task_id) ON DELETE CASCADE,
   FOREIGN KEY (job_id, depends_on) REFERENCES pg_catalog.pg_dist_background_task (job_id, task_id) ON DELETE CASCADE
);
ALTER TABLE citus.pg_dist_background_task_depend SET SCHEMA pg_catalog;
CREATE INDEX pg_dist_background_task_depend_task_id ON pg_catalog.pg_dist_background_task_depend USING btree(job_id, task_id);
CREATE INDEX pg_dist_background_task_depend_depends_on ON pg_catalog.pg_dist_background_task_depend USING btree(job_id, depends_on);
GRANT SELECT ON pg_catalog.pg_dist_background_task_depend TO PUBLIC;
CREATE FUNCTION pg_catalog.citus_job_wait(jobid bigint, desired_status pg_catalog.citus_job_status DEFAULT NULL)
    RETURNS VOID
    LANGUAGE C
    AS 'MODULE_PATHNAME',$$citus_job_wait$$;
COMMENT ON FUNCTION pg_catalog.citus_job_wait(jobid bigint, desired_status pg_catalog.citus_job_status)
    IS 'blocks till the job identified by jobid is at the specified status, or reached a terminal status. Only waits for terminal status when no desired_status was specified. The return value indicates if the desired status was reached or not. When no desired status was specified it will assume any terminal status was desired';
GRANT EXECUTE ON FUNCTION pg_catalog.citus_job_wait(jobid bigint, desired_status pg_catalog.citus_job_status) TO PUBLIC;
CREATE FUNCTION pg_catalog.citus_job_cancel(jobid bigint)
    RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME',$$citus_job_cancel$$;
COMMENT ON FUNCTION pg_catalog.citus_job_cancel(jobid bigint)
    IS 'cancel a scheduled or running job and all of its tasks that didn''t finish yet';
GRANT EXECUTE ON FUNCTION pg_catalog.citus_job_cancel(jobid bigint) TO PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_rebalance_start(
        rebalance_strategy name DEFAULT NULL,
        drain_only boolean DEFAULT false,
        shard_transfer_mode citus.shard_transfer_mode default 'auto'
    )
    RETURNS bigint
    AS 'MODULE_PATHNAME'
    LANGUAGE C VOLATILE;
COMMENT ON FUNCTION pg_catalog.citus_rebalance_start(name, boolean, citus.shard_transfer_mode)
    IS 'rebalance the shards in the cluster in the background';
GRANT EXECUTE ON FUNCTION pg_catalog.citus_rebalance_start(name, boolean, citus.shard_transfer_mode) TO PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_rebalance_stop()
    RETURNS VOID
    AS 'MODULE_PATHNAME'
    LANGUAGE C VOLATILE;
COMMENT ON FUNCTION pg_catalog.citus_rebalance_stop()
    IS 'stop a rebalance that is running in the background';
GRANT EXECUTE ON FUNCTION pg_catalog.citus_rebalance_stop() TO PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_rebalance_wait()
    RETURNS VOID
    AS 'MODULE_PATHNAME'
    LANGUAGE C VOLATILE;
COMMENT ON FUNCTION pg_catalog.citus_rebalance_wait()
    IS 'wait on a running rebalance in the background';
GRANT EXECUTE ON FUNCTION pg_catalog.citus_rebalance_wait() TO PUBLIC;
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
                target_shard_size bigint,
                operation_type text
            )
  AS 'MODULE_PATHNAME'
  LANGUAGE C STRICT;
COMMENT ON FUNCTION pg_catalog.get_rebalance_progress()
    IS 'provides progress information about the ongoing rebalance operations';
