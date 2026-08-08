-- citus--13.1-1--13.2-1
-- bump version to 13.2-1
DROP FUNCTION pg_catalog.worker_last_saved_explain_analyze();
CREATE OR REPLACE FUNCTION pg_catalog.worker_last_saved_explain_analyze()
    RETURNS TABLE(explain_analyze_output TEXT, execution_duration DOUBLE PRECISION,
        execution_ntuples DOUBLE PRECISION, execution_nloops DOUBLE PRECISION)
    LANGUAGE C STRICT
    AS 'citus';
COMMENT ON FUNCTION pg_catalog.worker_last_saved_explain_analyze() IS
    'Returns the saved explain analyze output for the last run query';
-- Add replica information columns to pg_dist_node
ALTER TABLE pg_catalog.pg_dist_node ADD COLUMN nodeisclone BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE pg_catalog.pg_dist_node ADD COLUMN nodeprimarynodeid INT4 NOT NULL DEFAULT 0;
-- Add a comment to the table and columns for clarity in \d output
COMMENT ON COLUMN pg_catalog.pg_dist_node.nodeisclone IS 'Indicates if this node is a replica of another node.';
COMMENT ON COLUMN pg_catalog.pg_dist_node.nodeprimarynodeid IS 'If nodeisclone is true, this stores the nodeid of its primary node.';
CREATE OR REPLACE FUNCTION pg_catalog.citus_add_clone_node(
    replica_hostname text,
    replica_port integer,
    primary_hostname text,
    primary_port integer)
 RETURNS INTEGER
 LANGUAGE C VOLATILE STRICT
 AS 'MODULE_PATHNAME', $$citus_add_clone_node$$;
COMMENT ON FUNCTION pg_catalog.citus_add_clone_node(text, integer, text, integer) IS
'Adds a new node as a clone of an existing primary node. The clone is initially inactive. Returns the nodeid of the new clone node.';
REVOKE ALL ON FUNCTION pg_catalog.citus_add_clone_node(text, int, text, int) FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_add_clone_node_with_nodeid(
    replica_hostname text,
    replica_port integer,
    primary_nodeid integer)
 RETURNS INTEGER
 LANGUAGE C VOLATILE STRICT
 AS 'MODULE_PATHNAME', $$citus_add_clone_node_with_nodeid$$;
COMMENT ON FUNCTION pg_catalog.citus_add_clone_node_with_nodeid(text, integer, integer) IS
'Adds a new node as a clone of an existing primary node using the primary node''s ID. The clone is initially inactive. Returns the nodeid of the new clone node.';
REVOKE ALL ON FUNCTION pg_catalog.citus_add_clone_node_with_nodeid(text, int, int) FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_remove_clone_node(
    nodename text,
    nodeport integer
)
RETURNS VOID
LANGUAGE C VOLATILE STRICT
AS 'MODULE_PATHNAME', $$citus_remove_clone_node$$;
COMMENT ON FUNCTION pg_catalog.citus_remove_clone_node(text, integer)
IS 'Removes an inactive streaming clone node from Citus metadata. Errors if the node is not found, not registered as a clone, or is currently marked active.';
REVOKE ALL ON FUNCTION pg_catalog.citus_remove_clone_node(text, integer) FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_remove_clone_node_with_nodeid(
    nodeid integer
)
RETURNS VOID
LANGUAGE C VOLATILE STRICT
AS 'MODULE_PATHNAME', $$citus_remove_clone_node_with_nodeid$$;
COMMENT ON FUNCTION pg_catalog.citus_remove_clone_node_with_nodeid(integer)
IS 'Removes an inactive streaming clone node from Citus metadata using its node ID. Errors if the node is not found, not registered as a clone, or is currently marked active.';
REVOKE ALL ON FUNCTION pg_catalog.citus_remove_clone_node_with_nodeid(integer) FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_promote_clone_and_rebalance(
    clone_nodeid integer,
    rebalance_strategy name DEFAULT NULL,
    catchup_timeout_seconds integer DEFAULT 300
)
RETURNS VOID
AS 'MODULE_PATHNAME'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION pg_catalog.citus_promote_clone_and_rebalance(integer, name, integer) IS
'Promotes a registered clone node to a primary, performs necessary metadata updates, and rebalances a portion of shards from its original primary to the newly promoted node. The catchUpTimeoutSeconds parameter controls how long to wait for the clone to catch up with the primary (default: 300 seconds).';
REVOKE ALL ON FUNCTION pg_catalog.citus_promote_clone_and_rebalance(integer, name, integer) FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.get_snapshot_based_node_split_plan(
    primary_node_name text,
    primary_node_port integer,
    replica_node_name text,
    replica_node_port integer,
    rebalance_strategy name DEFAULT NULL
    )
    RETURNS TABLE (table_name regclass,
                   shardid bigint,
                   shard_size bigint,
                   placement_node text)
    AS 'MODULE_PATHNAME'
    LANGUAGE C VOLATILE;
COMMENT ON FUNCTION pg_catalog.get_snapshot_based_node_split_plan(text, int, text, int, name)
    IS 'shows the shard placements to balance shards between primary and replica worker nodes';
REVOKE ALL ON FUNCTION pg_catalog.get_snapshot_based_node_split_plan(text, int, text, int, name) FROM PUBLIC;
DROP FUNCTION IF EXISTS pg_catalog.citus_rebalance_start(name, boolean, citus.shard_transfer_mode);
CREATE OR REPLACE FUNCTION pg_catalog.citus_rebalance_start(
        rebalance_strategy name DEFAULT NULL,
        drain_only boolean DEFAULT false,
        shard_transfer_mode citus.shard_transfer_mode default 'auto',
        parallel_transfer_reference_tables boolean DEFAULT false,
        parallel_transfer_colocated_shards boolean DEFAULT false
    )
    RETURNS bigint
    AS 'MODULE_PATHNAME'
    LANGUAGE C VOLATILE;
COMMENT ON FUNCTION pg_catalog.citus_rebalance_start(name, boolean, citus.shard_transfer_mode, boolean, boolean)
    IS 'rebalance the shards in the cluster in the background';
GRANT EXECUTE ON FUNCTION pg_catalog.citus_rebalance_start(name, boolean, citus.shard_transfer_mode, boolean, boolean) TO PUBLIC;
CREATE OR REPLACE FUNCTION citus_internal.citus_internal_copy_single_shard_placement(
 shard_id bigint,
 source_node_id integer,
 target_node_id integer,
 flags integer,
 transfer_mode citus.shard_transfer_mode default 'auto')
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_internal_copy_single_shard_placement$$;
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
    -- Temporarily disable trigger to check for validity of functions while
    -- inserting. The current contents of the table might be invalid if one of
    -- the functions was removed by the user without also removing the
    -- rebalance strategy. Obviously that's not great, but it should be no
    -- reason to fail the upgrade.
    ALTER TABLE pg_catalog.pg_dist_rebalance_strategy DISABLE TRIGGER pg_dist_rebalance_strategy_validation_trigger;
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
    ALTER TABLE pg_catalog.pg_dist_rebalance_strategy ENABLE TRIGGER pg_dist_rebalance_strategy_validation_trigger;
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
    -- If citus_columnar extension exists, then perform the post PG-upgrade work for columnar as well.
    --
    -- First look if pg_catalog.columnar_finish_pg_upgrade function exists as part of the citus_columnar
    -- extension. (We check whether it's part of the extension just for security reasons). If it does, then
    -- call it. If not, then look for columnar_internal.columnar_ensure_am_depends_catalog function and as
    -- part of the citus_columnar extension. If so, then call it. We alternatively check for the latter UDF
    -- just because pg_catalog.columnar_finish_pg_upgrade function is introduced in citus_columnar 13.2-1
    -- and as of today all it does is to call columnar_internal.columnar_ensure_am_depends_catalog function.
    IF EXISTS (
        SELECT 1 FROM pg_depend
        JOIN pg_proc ON (pg_depend.objid = pg_proc.oid)
        JOIN pg_namespace ON (pg_proc.pronamespace = pg_namespace.oid)
        JOIN pg_extension ON (pg_depend.refobjid = pg_extension.oid)
        WHERE
            -- Looking if pg_catalog.columnar_finish_pg_upgrade function exists and
            -- if there is a dependency record from it (proc class = 1255) ..
            pg_depend.classid = 1255 AND pg_namespace.nspname = 'pg_catalog' AND pg_proc.proname = 'columnar_finish_pg_upgrade' AND
            -- .. to citus_columnar extension (3079 = extension class), if it exists.
            pg_depend.refclassid = 3079 AND pg_extension.extname = 'citus_columnar'
    )
    THEN PERFORM pg_catalog.columnar_finish_pg_upgrade();
    ELSIF EXISTS (
        SELECT 1 FROM pg_depend
        JOIN pg_proc ON (pg_depend.objid = pg_proc.oid)
        JOIN pg_namespace ON (pg_proc.pronamespace = pg_namespace.oid)
        JOIN pg_extension ON (pg_depend.refobjid = pg_extension.oid)
        WHERE
            -- Looking if columnar_internal.columnar_ensure_am_depends_catalog function exists and
            -- if there is a dependency record from it (proc class = 1255) ..
            pg_depend.classid = 1255 AND pg_namespace.nspname = 'columnar_internal' AND pg_proc.proname = 'columnar_ensure_am_depends_catalog' AND
            -- .. to citus_columnar extension (3079 = extension class), if it exists.
            pg_depend.refclassid = 3079 AND pg_extension.extname = 'citus_columnar'
    )
    THEN PERFORM columnar_internal.columnar_ensure_am_depends_catalog();
    END IF;
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
SET search_path = 'pg_catalog';
DROP VIEW IF EXISTS pg_catalog.citus_stats;
CREATE OR REPLACE VIEW citus.citus_stats AS
WITH most_common_vals_double_json AS (
    SELECT ( SELECT json_agg(row_to_json(f)) FROM ( SELECT * FROM run_command_on_shards(logicalrelid,
            $$ SELECT json_agg(row_to_json(shard_stats)) FROM (
            SELECT '$$ || logicalrelid || $$' AS citus_table, attname, s.null_frac,
                   most_common_vals, most_common_freqs, c.reltuples AS reltuples
            -- join on tablename is enough here, no need to join with pg_namespace
            -- since shards have unique ids in their names, hence two shard names
            -- could never be the same
            FROM pg_stats s RIGHT JOIN pg_class c ON (s.tablename = c.relname)
            WHERE c.oid = '%s'::regclass) shard_stats $$ ))f)
        FROM pg_dist_partition),
most_common_vals_json AS (
    SELECT (json_array_elements(json_agg)->>'result') AS result,
        (json_array_elements(json_agg)->>'shardid') AS shardid
    FROM most_common_vals_double_json),
table_reltuples_json AS (
    SELECT distinct(shardid),
           CAST( CAST((json_array_elements(result::json)->>'reltuples') AS DOUBLE PRECISION) AS bigint) AS shard_reltuples,
        (json_array_elements(result::json)->>'citus_table')::regclass AS citus_table
    FROM most_common_vals_json),
table_reltuples AS (
        SELECT citus_table, sum(shard_reltuples) AS table_reltuples
        FROM table_reltuples_json GROUP BY 1 ORDER BY 1),
null_frac_json AS (
    SELECT (json_array_elements(result::json)->>'citus_table')::regclass AS citus_table,
           CAST( CAST((json_array_elements(result::json)->>'reltuples') AS DOUBLE PRECISION) AS bigint) AS shard_reltuples,
           CAST((json_array_elements(result::json)->>'null_frac') AS float4) AS null_frac,
           (json_array_elements(result::json)->>'attname')::text AS attname
    FROM most_common_vals_json
),
null_occurrences AS (
    SELECT citus_table, attname, sum(null_frac * shard_reltuples)::bigint AS null_occurrences
    FROM null_frac_json
    GROUP BY 1, 2
    ORDER BY 1, 2
),
most_common_vals AS (
    SELECT (json_array_elements(result::json)->>'citus_table')::regclass AS citus_table,
           (json_array_elements(result::json)->>'attname')::text AS attname,
           json_array_elements_text((json_array_elements(result::json)->>'most_common_vals')::json)::text AS common_val,
           CAST(json_array_elements_text((json_array_elements(result::json)->>'most_common_freqs')::json) AS float4) AS common_freq,
           CAST( CAST((json_array_elements(result::json)->>'reltuples') AS DOUBLE PRECISION) AS bigint) AS shard_reltuples
    FROM most_common_vals_json),
common_val_occurrence AS (
    SELECT citus_table, m.attname, common_val,
            sum(common_freq * shard_reltuples)::bigint AS occurrence
    FROM most_common_vals m
    GROUP BY citus_table, m.attname, common_val
    ORDER BY 1, 2, occurrence DESC, 3)
SELECT nsp.nspname AS schemaname, p.relname AS tablename, c.attname,
       CASE WHEN max(t.table_reltuples::bigint) = 0 THEN 0
       ELSE max(n.null_occurrences/t.table_reltuples)::float4 END AS null_frac,
       ARRAY_agg(common_val) AS most_common_vals,
       CASE WHEN max(t.table_reltuples::bigint) = 0 THEN NULL
       ELSE ARRAY_agg((occurrence/t.table_reltuples)::float4) END AS most_common_freqs
FROM common_val_occurrence c, table_reltuples t, null_occurrences n, pg_class p, pg_namespace nsp
WHERE c.citus_table = t.citus_table
      AND c.citus_table = n.citus_table AND c.attname = n.attname
      AND c.citus_table::regclass::oid = p.oid AND p.relnamespace = nsp.oid
GROUP BY nsp.nspname, c.citus_table, p.relname, c.attname;
ALTER VIEW citus.citus_stats SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_stats TO PUBLIC;
RESET search_path;
DO $drop_leftover_old_columnar_objects$
BEGIN
  -- If old columnar exists, i.e., the columnar access method that we had before Citus 11.1,
  -- and we don't have any relations using the old columnar, then we want to drop the columnar
  -- objects. This is because, we don't want to automatically create the "citus_columnar"
  -- extension together with the "citus" extension anymore. And for the cases where we don't
  -- want to automatically create the "citus_columnar" extension, there is no point of keeping
  -- the columnar objects that we had before Citus 11.1 around.
  IF (
    SELECT EXISTS (
      SELECT 1 FROM pg_am
      WHERE
        -- looking for an access method whose name is "columnar" ..
        pg_am.amname = 'columnar' AND
        -- .. and there should *NOT* be such a dependency edge in pg_depend, where ..
        NOT EXISTS (
          SELECT 1 FROM pg_depend
          WHERE
            -- .. the depender is columnar access method (2601 = access method class) ..
            pg_depend.classid = 2601 AND pg_depend.objid = pg_am.oid AND pg_depend.objsubid = 0 AND
            -- .. and the dependee is an extension (3079 = extension class)
            pg_depend.refclassid = 3079 AND pg_depend.refobjsubid = 0
          LIMIT 1
        ) AND
        -- .. and there should *NOT* be any relations using it
        NOT EXISTS (
          SELECT 1
          FROM pg_class
          WHERE pg_class.relam = pg_am.oid
          LIMIT 1
        )
    )
  )
  THEN
    -- Below we drop the columnar objects in such an order that the objects that depend on
    -- other objects are dropped first.
    DROP VIEW IF EXISTS columnar.options;
    DROP VIEW IF EXISTS columnar.stripe;
    DROP VIEW IF EXISTS columnar.chunk_group;
    DROP VIEW IF EXISTS columnar.chunk;
    DROP VIEW IF EXISTS columnar.storage;
    DROP ACCESS METHOD IF EXISTS columnar;
    DROP SEQUENCE IF EXISTS columnar_internal.storageid_seq;
    DROP TABLE IF EXISTS columnar_internal.options;
    DROP TABLE IF EXISTS columnar_internal.stripe;
    DROP TABLE IF EXISTS columnar_internal.chunk_group;
    DROP TABLE IF EXISTS columnar_internal.chunk;
    DROP FUNCTION IF EXISTS columnar_internal.columnar_handler;
    DROP FUNCTION IF EXISTS pg_catalog.alter_columnar_table_set;
    DROP FUNCTION IF EXISTS pg_catalog.alter_columnar_table_reset;
    DROP FUNCTION IF EXISTS columnar.get_storage_id;
    DROP FUNCTION IF EXISTS citus_internal.upgrade_columnar_storage;
    DROP FUNCTION IF EXISTS citus_internal.downgrade_columnar_storage;
    DROP FUNCTION IF EXISTS citus_internal.columnar_ensure_am_depends_catalog;
    DROP SCHEMA IF EXISTS columnar;
    DROP SCHEMA IF EXISTS columnar_internal;
  END IF;
END $drop_leftover_old_columnar_objects$;
