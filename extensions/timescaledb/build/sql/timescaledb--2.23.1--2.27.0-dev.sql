-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- This file is always prepended to all installation and upgrade/downgrade scripts.
SET LOCAL search_path TO pg_catalog, pg_temp;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

DO $$
DECLARE
  catalog_version TEXT;
BEGIN
  SELECT value INTO catalog_version FROM _timescaledb_catalog.metadata WHERE key='timescaledb_version' AND value <> '2.23.1';
  IF FOUND THEN
    RAISE EXCEPTION 'catalog version mismatch'
      USING
        DETAIL = format('current extension version is "%s" but catalog version is "%s"', '2.23.1', catalog_version),
        HINT = 'Make sure the TimescaleDB version used to dump the database is the same as the one used to restore it.';
  END IF;
END$$;

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- This file is always prepended to all upgrade and downgrade scripts.
-- This file must avoid referencing extension objects directly as that
-- would limit the things we can alter in extension update/downgrade
-- itself.
SET LOCAL search_path TO pg_catalog, pg_temp;

-- Disable parallel execution for the duration of the update process.
-- This avoids version mismatch errors that would have beeen triggered by the
-- parallel workers in ts_extension_check_version().
SET LOCAL max_parallel_workers = 0;

-- Triggers should be disabled during upgrades to avoid having them
-- invoke functions that might load an old version of the shared
-- library before those functions have been updated.
DROP EVENT TRIGGER IF EXISTS timescaledb_ddl_command_end;
DROP EVENT TRIGGER IF EXISTS timescaledb_ddl_sql_drop;

-- Since we want to call the new version of restart_background_workers we
-- create a function that points to that version. The proper restart_background_workers
-- may either be in _timescaledb_internal or in _timescaledb_functions
-- depending on the version we are upgrading from and we can't make
-- the move in this location as the new schema might not have been set up.
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_namespace WHERE nspname='_timescaledb_functions') THEN
    CREATE FUNCTION _timescaledb_functions._tmp_restart_background_workers() RETURNS BOOL
    AS '$libdir/timescaledb', 'ts_bgw_db_workers_restart' LANGUAGE C VOLATILE;
    PERFORM _timescaledb_functions._tmp_restart_background_workers();
    DROP FUNCTION _timescaledb_functions._tmp_restart_background_workers();
  ELSE
    -- timescaledb < 2.11 does not have _timescaledb_functions schema
    CREATE FUNCTION _timescaledb_internal._tmp_restart_background_workers() RETURNS BOOL
    AS '$libdir/timescaledb', 'ts_bgw_db_workers_restart' LANGUAGE C VOLATILE;
    PERFORM _timescaledb_internal._tmp_restart_background_workers();
    DROP FUNCTION _timescaledb_internal._tmp_restart_background_workers();
  END IF;
END
$$;

-- Table for ACL and initprivs of tables.
CREATE TABLE _timescaledb_internal.saved_privs(
       tmpnsp name,
       tmpname name,
       tmpacl aclitem[],
       tmpini aclitem[],
       UNIQUE (tmpnsp, tmpname));

-- We save away both the ACL and the initprivs for all tables and
-- views in the extension (but not for chunks and internal objects) so
-- that we can restore them to the proper state after the update.
INSERT INTO _timescaledb_internal.saved_privs
SELECT nspname, relname, relacl, initprivs
  FROM pg_class cl JOIN pg_namespace ns ON ns.oid = relnamespace
                   JOIN pg_init_privs ip ON ip.objoid = cl.oid AND ip.objsubid = 0 AND ip.classoid = 'pg_class'::regclass
WHERE
  nspname IN ('_timescaledb_catalog', '_timescaledb_config')
  OR (
    relname IN ('hypertable_chunk_local_size', 'compressed_chunk_stats', 'bgw_job_stat', 'bgw_policy_chunk_stats')
    AND nspname = '_timescaledb_internal'
  )
;

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- This file is always prepended to all upgrade scripts.

DROP FUNCTION IF EXISTS _timescaledb_functions.policy_job_stat_history_retention;
DROP VIEW IF EXISTS timescaledb_information.chunks;

-- Add support for concurrent merge_chunks()
CREATE TABLE _timescaledb_catalog.chunk_rewrite (
  chunk_relid REGCLASS NOT NULL,
  new_relid REGCLASS NOT NULL,
  CONSTRAINT chunk_rewrite_key UNIQUE (chunk_relid)
);

GRANT SELECT ON _timescaledb_catalog.chunk_rewrite TO PUBLIC;
DROP PROCEDURE IF EXISTS @extschema@.merge_chunks(REGCLASS, REGCLASS);


-- Check whether the database has the sparse bloom filter indexes on compressed
-- chunks, which will require manual action to re-enable.
DO $$
DECLARE
    num_chunks_with_bloom int;
BEGIN
    SELECT count(*) INTO num_chunks_with_bloom
    FROM pg_attribute WHERE attname LIKE '_ts_meta_v2_bloom1_%';

    IF num_chunks_with_bloom > 0 THEN
       RAISE WARNING 'bloom filter sparse indexes require action to re-enable'
              USING HINT = 'See the changelog for details.';
    END IF;
END
$$;
DROP VIEW IF EXISTS timescaledb_information.dimensions;
-- Block update if CAggs in old format are found
DO
$$
DECLARE
  caggs text;
BEGIN
  SELECT string_agg(format('%I.%I', user_view_schema, user_view_name), ', ')
  INTO caggs
  FROM _timescaledb_catalog.continuous_agg
  WHERE finalized IS FALSE
  GROUP BY user_view_schema, user_view_name
  ORDER BY user_view_schema, user_view_name;

  IF caggs IS NOT NULL THEN
    RAISE
      EXCEPTION 'continuous aggregates with old format found, update blocked'
      USING
        DETAIL = format('Continuous Aggregates: %s', caggs),
        HINT = 'You should use `cagg_migrate` procedure to migrate to the new format.';
  END IF;
END
$$;

-- Block update if CAggs using time_bucket_ng are found
DO
$$
DECLARE
  caggs text;
BEGIN
  SELECT string_agg(pg_catalog.format('%I.%I', user_view_schema, user_view_name), ', ')
  INTO caggs
  FROM _timescaledb_catalog.continuous_agg cagg
  JOIN _timescaledb_catalog.continuous_aggs_bucket_function AS bf ON (cagg.mat_hypertable_id = bf.mat_hypertable_id)
  WHERE bf.bucket_func::text LIKE '%time_bucket_ng%';

  IF caggs IS NOT NULL THEN
    RAISE
      EXCEPTION 'continuous aggregates using time_bucket_ng found, update blocked'
      USING
        DETAIL = format('Continuous Aggregates: %s', caggs),
        HINT = 'time_bucket_ng has been removed. Please migrate the continuous aggregates using `cagg_migrate` before updating';
  END IF;
END
$$;

--
-- Rebuild the catalog table `_timescaledb_catalog.continuous_agg` to remove `finalized` column
--

-- (1) Remove cagg migration functions and procedures from public and internal schemas
DROP PROCEDURE IF EXISTS @extschema@.cagg_migrate (REGCLASS, BOOLEAN, BOOLEAN);
DROP FUNCTION IF EXISTS _timescaledb_internal.cagg_migrate_pre_validation (TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS _timescaledb_functions.cagg_migrate_pre_validation (TEXT, TEXT, TEXT);
DROP PROCEDURE IF EXISTS _timescaledb_internal.cagg_migrate_create_plan (_timescaledb_catalog.continuous_agg, TEXT, BOOLEAN, BOOLEAN);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_create_plan (_timescaledb_catalog.continuous_agg, TEXT, BOOLEAN, BOOLEAN);

DROP FUNCTION IF EXISTS _timescaledb_internal.cagg_migrate_plan_exists (INTEGER);
DROP FUNCTION IF EXISTS _timescaledb_functions.cagg_migrate_plan_exists (INTEGER);
DROP PROCEDURE IF EXISTS _timescaledb_internal.cagg_migrate_execute_plan (_timescaledb_catalog.continuous_agg);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_execute_plan (_timescaledb_catalog.continuous_agg);
DROP PROCEDURE IF EXISTS _timescaledb_internal.cagg_migrate_execute_create_new_cagg (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_execute_create_new_cagg (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_internal.cagg_migrate_execute_disable_policies (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_execute_disable_policies (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_internal.cagg_migrate_execute_enable_policies (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_execute_enable_policies (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_internal.cagg_migrate_execute_copy_policies (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_execute_copy_policies (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_internal.cagg_migrate_execute_refresh_new_cagg (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_execute_refresh_new_cagg (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_update_watermark(integer);
DROP PROCEDURE IF EXISTS _timescaledb_internal.cagg_migrate_execute_copy_data (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_execute_copy_data (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_internal.cagg_migrate_execute_override_cagg (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_execute_override_cagg (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_internal.cagg_migrate_execute_drop_old_cagg (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);
DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_execute_drop_old_cagg (_timescaledb_catalog.continuous_agg, _timescaledb_catalog.continuous_agg_migrate_plan_step);

-- (2) Rebuild catalog table
DROP VIEW IF EXISTS timescaledb_experimental.policies;
DROP VIEW IF EXISTS timescaledb_information.hypertables;
DROP VIEW IF EXISTS timescaledb_information.continuous_aggregates;
DROP VIEW IF EXISTS timescaledb_information.jobs;

ALTER TABLE _timescaledb_catalog.continuous_aggs_materialization_ranges
    DROP CONSTRAINT continuous_aggs_materialization_ranges_materialization_id_fkey;

ALTER TABLE _timescaledb_catalog.continuous_aggs_materialization_invalidation_log
    DROP CONSTRAINT continuous_aggs_materialization_invalid_materialization_id_fkey;

ALTER TABLE _timescaledb_catalog.continuous_aggs_watermark
    DROP CONSTRAINT continuous_aggs_watermark_mat_hypertable_id_fkey;

ALTER EXTENSION timescaledb
    DROP TABLE _timescaledb_catalog.continuous_agg;

CREATE TABLE _timescaledb_catalog._tmp_continuous_agg AS
    SELECT
        mat_hypertable_id,
        raw_hypertable_id,
        parent_mat_hypertable_id,
        user_view_schema,
        user_view_name,
        partial_view_schema,
        partial_view_name,
        direct_view_schema,
        direct_view_name,
        materialized_only
    FROM
        _timescaledb_catalog.continuous_agg
    ORDER BY
        mat_hypertable_id;

DROP TABLE _timescaledb_catalog.continuous_agg;

CREATE TABLE _timescaledb_catalog.continuous_agg (
    mat_hypertable_id integer NOT NULL,
    raw_hypertable_id integer NOT NULL,
    parent_mat_hypertable_id integer,
    user_view_schema name NOT NULL,
    user_view_name name NOT NULL,
    partial_view_schema name NOT NULL,
    partial_view_name name NOT NULL,
    direct_view_schema name NOT NULL,
    direct_view_name name NOT NULL,
    materialized_only bool NOT NULL DEFAULT FALSE,
    -- table constraints
    CONSTRAINT continuous_agg_pkey PRIMARY KEY (mat_hypertable_id),
    CONSTRAINT continuous_agg_partial_view_schema_partial_view_name_key UNIQUE (partial_view_schema, partial_view_name),
    CONSTRAINT continuous_agg_user_view_schema_user_view_name_key UNIQUE (user_view_schema, user_view_name),
    CONSTRAINT continuous_agg_mat_hypertable_id_fkey
        FOREIGN KEY (mat_hypertable_id) REFERENCES _timescaledb_catalog.hypertable (id) ON DELETE CASCADE,
    CONSTRAINT continuous_agg_raw_hypertable_id_fkey
        FOREIGN KEY (raw_hypertable_id) REFERENCES _timescaledb_catalog.hypertable (id) ON DELETE CASCADE,
    CONSTRAINT continuous_agg_parent_mat_hypertable_id_fkey
        FOREIGN KEY (parent_mat_hypertable_id)
        REFERENCES _timescaledb_catalog.continuous_agg (mat_hypertable_id) ON DELETE CASCADE
);

INSERT INTO _timescaledb_catalog.continuous_agg
SELECT * FROM _timescaledb_catalog._tmp_continuous_agg;
DROP TABLE _timescaledb_catalog._tmp_continuous_agg;

CREATE INDEX continuous_agg_raw_hypertable_id_idx ON _timescaledb_catalog.continuous_agg (raw_hypertable_id);

SELECT pg_catalog.pg_extension_config_dump('_timescaledb_catalog.continuous_agg', '');

GRANT SELECT ON TABLE _timescaledb_catalog.continuous_agg TO PUBLIC;

-- clean up orphaned entries in related tables
DELETE FROM _timescaledb_catalog.continuous_aggs_materialization_ranges range WHERE NOT EXISTS (
    SELECT FROM _timescaledb_catalog.continuous_agg ca WHERE ca.mat_hypertable_id = range.materialization_id
);
DELETE FROM _timescaledb_catalog.continuous_aggs_materialization_invalidation_log inval WHERE NOT EXISTS (
    SELECT FROM _timescaledb_catalog.continuous_agg ca WHERE ca.mat_hypertable_id = inval.materialization_id
);
DELETE FROM _timescaledb_catalog.continuous_aggs_watermark wm WHERE NOT EXISTS (
    SELECT FROM _timescaledb_catalog.continuous_agg ca WHERE ca.mat_hypertable_id = wm.mat_hypertable_id
);

ALTER TABLE _timescaledb_catalog.continuous_aggs_materialization_ranges
    ADD CONSTRAINT continuous_aggs_materialization_ranges_materialization_id_fkey
        FOREIGN KEY (materialization_id)
        REFERENCES _timescaledb_catalog.continuous_agg(mat_hypertable_id) ON DELETE CASCADE;

ALTER TABLE _timescaledb_catalog.continuous_aggs_materialization_invalidation_log
    ADD CONSTRAINT continuous_aggs_materialization_invalid_materialization_id_fkey
        FOREIGN KEY (materialization_id)
        REFERENCES _timescaledb_catalog.continuous_agg(mat_hypertable_id) ON DELETE CASCADE;

ALTER TABLE _timescaledb_catalog.continuous_aggs_watermark
    ADD CONSTRAINT continuous_aggs_watermark_mat_hypertable_id_fkey
        FOREIGN KEY (mat_hypertable_id)
        REFERENCES _timescaledb_catalog.continuous_agg (mat_hypertable_id) ON DELETE CASCADE;

ANALYZE _timescaledb_catalog.continuous_agg;

--
-- END Rebuild the catalog table `_timescaledb_catalog.continuous_agg`
--

DROP FUNCTION IF EXISTS _timescaledb_debug.extension_state();
DROP SCHEMA IF EXISTS _timescaledb_debug;

ALTER TABLE _timescaledb_config.bgw_job SET SCHEMA _timescaledb_catalog;

-- Remove legacy partialize/finalize aggregate functions. It should be
-- conditional because on 2.12.0 we moved from internal to functions schema
DO
$$
DECLARE
    foid regprocedure;
    fkind text;
    fargs text;
    funcs text[] = '{finalize_agg, finalize_agg_sfunc, finalize_agg_ffunc, partialize_agg}';
BEGIN
    FOR foid, fkind, fargs IN
        SELECT
            p.oid,
            CASE
                WHEN p.prokind = 'f' THEN 'FUNCTION'
                WHEN p.prokind = 'a' THEN 'AGGREGATE'
                ELSE 'PROCEDURE'
            END,
            pg_catalog.pg_get_function_arguments(p.oid)
        FROM
            pg_catalog.pg_proc AS p
        WHERE
            p.proname = ANY(funcs)
            AND p.pronamespace IN ('_timescaledb_internal'::regnamespace, '_timescaledb_functions'::regnamespace)
        ORDER BY
            p.proname
    LOOP
        EXECUTE format('ALTER EXTENSION timescaledb DROP %s %s (%s);', fkind, foid::regproc, fargs);
        EXECUTE format('DROP %s %s (%s);', fkind, foid::regproc, fargs);
    END LOOP;
END;
$$
LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS _timescaledb_functions.cagg_parse_invalidation_record(bytea);
DROP FUNCTION IF EXISTS _timescaledb_functions.get_hypertable_id(regclass, regtype);
DROP FUNCTION IF EXISTS _timescaledb_functions.get_hypertable_invalidations(regclass,timestamp without time zone,interval[]);
DROP FUNCTION IF EXISTS _timescaledb_functions.get_hypertable_invalidations(regclass,timestamp with time zone,interval[]);
DROP FUNCTION IF EXISTS _timescaledb_functions.get_materialization_info(regclass);
DROP FUNCTION IF EXISTS _timescaledb_functions.get_materialization_invalidations(regclass,tsrange);
DROP FUNCTION IF EXISTS _timescaledb_functions.get_materialization_invalidations(regclass,tstzrange);
DROP FUNCTION IF EXISTS _timescaledb_functions.get_raw_materialization_ranges(regtype);
DROP FUNCTION IF EXISTS _timescaledb_functions.invalidation_plugin_name();
DROP PROCEDURE IF EXISTS _timescaledb_functions.accept_hypertable_invalidations(regclass,text);
DROP PROCEDURE IF EXISTS _timescaledb_functions.add_materialization_invalidations(regclass,tsrange);
DROP PROCEDURE IF EXISTS _timescaledb_functions.add_materialization_invalidations(regclass,tstzrange);
DROP PROCEDURE IF EXISTS _timescaledb_functions.process_hypertable_invalidations(name);
DROP PROCEDURE IF EXISTS _timescaledb_functions.process_hypertable_invalidations(regclass);
DROP PROCEDURE IF EXISTS _timescaledb_functions.process_hypertable_invalidations(regclass[]);

DROP PROCEDURE IF EXISTS _timescaledb_functions.cagg_migrate_to_time_bucket(regclass);

DROP FUNCTION timescaledb_experimental.time_bucket_ng(bucket_width INTERVAL, ts DATE);

DROP FUNCTION timescaledb_experimental.time_bucket_ng(bucket_width INTERVAL, ts DATE, origin DATE);

DROP FUNCTION timescaledb_experimental.time_bucket_ng(bucket_width INTERVAL, ts TIMESTAMP);

DROP FUNCTION timescaledb_experimental.time_bucket_ng(bucket_width INTERVAL, ts TIMESTAMP, origin TIMESTAMP);

DROP FUNCTION timescaledb_experimental.time_bucket_ng(bucket_width INTERVAL, ts TIMESTAMPTZ, timezone TEXT);

DROP FUNCTION timescaledb_experimental.time_bucket_ng(bucket_width INTERVAL, ts TIMESTAMPTZ, origin TIMESTAMPTZ, timezone TEXT);

DROP FUNCTION timescaledb_experimental.time_bucket_ng(bucket_width INTERVAL, ts TIMESTAMPTZ);

DROP FUNCTION timescaledb_experimental.time_bucket_ng(bucket_width INTERVAL, ts TIMESTAMPTZ, origin TIMESTAMPTZ);

--
-- Rebuild the catalog table `_timescaledb_catalog.chunk` to drop column `dropped`
--

CREATE TABLE _timescaledb_internal.tmp_chunk AS SELECT * from _timescaledb_catalog.chunk WHERE NOT dropped;
CREATE TABLE _timescaledb_internal.tmp_chunk_seq_value AS SELECT last_value, is_called FROM _timescaledb_catalog.chunk_id_seq;

--drop foreign keys on chunk table
ALTER TABLE _timescaledb_catalog.chunk_constraint DROP CONSTRAINT chunk_constraint_chunk_id_fkey;
ALTER TABLE _timescaledb_catalog.chunk_column_stats DROP CONSTRAINT chunk_column_stats_chunk_id_fkey;
ALTER TABLE _timescaledb_internal.bgw_policy_chunk_stats DROP CONSTRAINT bgw_policy_chunk_stats_chunk_id_fkey;
ALTER TABLE _timescaledb_catalog.compression_chunk_size DROP CONSTRAINT compression_chunk_size_chunk_id_fkey;
ALTER TABLE _timescaledb_catalog.compression_chunk_size DROP CONSTRAINT compression_chunk_size_compressed_chunk_id_fkey;

--drop dependent views
DROP VIEW IF EXISTS timescaledb_information.hypertables;
DROP VIEW IF EXISTS timescaledb_information.chunks;
DROP VIEW IF EXISTS _timescaledb_internal.hypertable_chunk_local_size;
DROP VIEW IF EXISTS _timescaledb_internal.compressed_chunk_stats;
DROP VIEW IF EXISTS timescaledb_information.chunk_columnstore_settings;
DROP VIEW IF EXISTS timescaledb_information.chunk_compression_settings;

ALTER EXTENSION timescaledb DROP TABLE _timescaledb_catalog.chunk;
ALTER EXTENSION timescaledb DROP SEQUENCE _timescaledb_catalog.chunk_id_seq;

DROP TABLE _timescaledb_catalog.chunk;

CREATE SEQUENCE _timescaledb_catalog.chunk_id_seq MINVALUE 1;

-- now create table without self referential foreign key
CREATE TABLE _timescaledb_catalog.chunk (
  id integer NOT NULL DEFAULT nextval('_timescaledb_catalog.chunk_id_seq'),
  hypertable_id int NOT NULL,
  schema_name name NOT NULL,
  table_name name NOT NULL,
  compressed_chunk_id integer ,
  status integer NOT NULL DEFAULT 0,
  osm_chunk boolean NOT NULL DEFAULT FALSE,
  creation_time timestamptz NOT NULL,
  -- table constraints
  CONSTRAINT chunk_pkey PRIMARY KEY (id),
  CONSTRAINT chunk_schema_name_table_name_key UNIQUE (schema_name, table_name)
);

INSERT INTO _timescaledb_catalog.chunk( id, hypertable_id, schema_name, table_name, compressed_chunk_id, status, osm_chunk, creation_time)
SELECT id, hypertable_id, schema_name, table_name, compressed_chunk_id, status, osm_chunk, creation_time
FROM _timescaledb_internal.tmp_chunk;

--add indexes to the chunk table
CREATE INDEX chunk_hypertable_id_idx ON _timescaledb_catalog.chunk (hypertable_id);
CREATE INDEX chunk_compressed_chunk_id_idx ON _timescaledb_catalog.chunk (compressed_chunk_id);
CREATE INDEX chunk_osm_chunk_idx ON _timescaledb_catalog.chunk (osm_chunk, hypertable_id);
CREATE INDEX chunk_hypertable_id_creation_time_idx ON _timescaledb_catalog.chunk(hypertable_id, creation_time);

ALTER SEQUENCE _timescaledb_catalog.chunk_id_seq OWNED BY _timescaledb_catalog.chunk.id;
SELECT setval('_timescaledb_catalog.chunk_id_seq', last_value, is_called) FROM _timescaledb_internal.tmp_chunk_seq_value;

-- add self referential foreign key
ALTER TABLE _timescaledb_catalog.chunk ADD CONSTRAINT chunk_compressed_chunk_id_fkey FOREIGN KEY ( compressed_chunk_id ) REFERENCES _timescaledb_catalog.chunk( id );

--add foreign key constraint
ALTER TABLE _timescaledb_catalog.chunk ADD CONSTRAINT chunk_hypertable_id_fkey FOREIGN KEY (hypertable_id) REFERENCES _timescaledb_catalog.hypertable (id);

SELECT pg_catalog.pg_extension_config_dump('_timescaledb_catalog.chunk', '');
SELECT pg_catalog.pg_extension_config_dump('_timescaledb_catalog.chunk_id_seq', '');

-- clean orphaned entries
DELETE FROM _timescaledb_catalog.compression_chunk_size ccs WHERE
  NOT EXISTS (SELECT FROM _timescaledb_catalog.chunk c WHERE c.id = ccs.chunk_id)
  OR NOT EXISTS (SELECT FROM _timescaledb_catalog.chunk c WHERE c.id = ccs.compressed_chunk_id);

--add the foreign key constraints
ALTER TABLE _timescaledb_catalog.chunk_constraint ADD CONSTRAINT chunk_constraint_chunk_id_fkey FOREIGN KEY (chunk_id) REFERENCES _timescaledb_catalog.chunk(id);
ALTER TABLE _timescaledb_catalog.chunk_column_stats ADD CONSTRAINT chunk_column_stats_chunk_id_fkey FOREIGN KEY (chunk_id) REFERENCES _timescaledb_catalog.chunk (id);
ALTER TABLE _timescaledb_internal.bgw_policy_chunk_stats ADD CONSTRAINT bgw_policy_chunk_stats_chunk_id_fkey FOREIGN KEY (chunk_id) REFERENCES _timescaledb_catalog.chunk(id) ON DELETE CASCADE;
ALTER TABLE _timescaledb_catalog.compression_chunk_size ADD CONSTRAINT compression_chunk_size_chunk_id_fkey FOREIGN KEY (chunk_id) REFERENCES _timescaledb_catalog.chunk(id) ON DELETE CASCADE;
ALTER TABLE _timescaledb_catalog.compression_chunk_size ADD CONSTRAINT compression_chunk_size_compressed_chunk_id_fkey FOREIGN KEY (compressed_chunk_id) REFERENCES _timescaledb_catalog.chunk(id) ON DELETE CASCADE;

--cleanup
DROP TABLE _timescaledb_internal.tmp_chunk;
DROP TABLE _timescaledb_internal.tmp_chunk_seq_value;

GRANT SELECT ON _timescaledb_catalog.chunk_id_seq TO PUBLIC;
GRANT SELECT ON _timescaledb_catalog.chunk TO PUBLIC;
-- end rebuild _timescaledb_catalog.chunk table --

-- drop the catalog tables for continuous aggregate migration plans

ALTER EXTENSION timescaledb DROP TABLE _timescaledb_catalog.continuous_agg_migrate_plan;
ALTER EXTENSION timescaledb DROP TABLE _timescaledb_catalog.continuous_agg_migrate_plan_step;
ALTER EXTENSION timescaledb DROP SEQUENCE _timescaledb_catalog.continuous_agg_migrate_plan_step_step_id_seq;
DROP TABLE _timescaledb_catalog.continuous_agg_migrate_plan_step;
DROP TABLE _timescaledb_catalog.continuous_agg_migrate_plan;

--
-- Add this index to speed up queries for recent job history
-- This statement is idempotent to allow the index to have been precreated.
--
CREATE INDEX IF NOT EXISTS bgw_job_stat_history_execution_start_idx
    ON _timescaledb_internal.bgw_job_stat_history(execution_start);
CREATE INDEX IF NOT EXISTS bgw_job_stat_history_job_id_execution_start_idx
    ON _timescaledb_internal.bgw_job_stat_history(job_id, execution_start DESC);

DROP INDEX IF EXISTS _timescaledb_internal.bgw_job_stat_history_job_id_idx;

-- Add continuous_aggs_jobs_refresh_ranges table
CREATE TABLE _timescaledb_catalog.continuous_aggs_jobs_refresh_ranges (
  materialization_id integer NOT NULL,
  start_range bigint NOT NULL,
  end_range bigint NOT NULL,
  pid integer NOT NULL,
  job_id integer NOT NULL,
  created_at timestamptz NOT NULL,
  CONSTRAINT continuous_aggs_jobs_refresh_ranges_materialization_id_fkey FOREIGN KEY (materialization_id) REFERENCES _timescaledb_catalog.continuous_agg (mat_hypertable_id) ON DELETE CASCADE
);

SELECT pg_catalog.pg_extension_config_dump('_timescaledb_catalog.continuous_aggs_jobs_refresh_ranges', '');

CREATE INDEX continuous_aggs_jobs_refresh_ranges_idx ON _timescaledb_catalog.continuous_aggs_jobs_refresh_ranges (materialization_id);

GRANT SELECT ON _timescaledb_catalog.continuous_aggs_jobs_refresh_ranges TO PUBLIC;

DROP PROCEDURE IF EXISTS _timescaledb_functions.repair_relation_acls();
DROP FUNCTION IF EXISTS _timescaledb_functions.makeaclitem(regrole, regrole, text, bool);

-- Create watermark record when required. This uses pure SQL to avoid calling
-- C functions that need catalog access during ALTER EXTENSION UPDATE.
-- this is only needed for users upgrading from before 2.11.0, as the watermark
-- was added in that version.
DO
$$
DECLARE
  ts_version TEXT;
  cagg_rec RECORD;
  max_val BIGINT;
  watermark_val BIGINT;
  bucket_width_val BIGINT;
BEGIN
    SELECT extversion INTO ts_version FROM pg_extension WHERE extname = 'timescaledb';
    IF ts_version < '2.11.0' THEN
      RETURN;
    END IF;

    FOR cagg_rec IN
      SELECT a.mat_hypertable_id,
             h.schema_name, h.table_name,
             d.column_name, d.column_type,
             bf.bucket_width, bf.bucket_fixed_width
      FROM _timescaledb_catalog.continuous_agg a
      LEFT JOIN _timescaledb_catalog.continuous_aggs_watermark w ON w.mat_hypertable_id = a.mat_hypertable_id
      JOIN _timescaledb_catalog.hypertable h ON h.id = a.mat_hypertable_id
      JOIN _timescaledb_catalog.dimension d ON d.hypertable_id = a.mat_hypertable_id AND d.num_slices IS NULL
      LEFT JOIN _timescaledb_catalog.continuous_aggs_bucket_function bf ON bf.mat_hypertable_id = a.mat_hypertable_id
      WHERE w.mat_hypertable_id IS NULL
      ORDER BY a.mat_hypertable_id
    LOOP
      -- Get max value from materialization hypertable converted to internal representation
      IF cagg_rec.column_type IN ('timestamptz'::regtype, 'timestamp'::regtype, 'date'::regtype) THEN
        EXECUTE format(
          'SELECT (pg_catalog.date_part(''epoch'', pg_catalog.max(%I)) * 1000000)::bigint FROM %I.%I',
          cagg_rec.column_name, cagg_rec.schema_name, cagg_rec.table_name
        ) INTO max_val;
      ELSE
        EXECUTE format(
          'SELECT pg_catalog.max(%I)::bigint FROM %I.%I',
          cagg_rec.column_name, cagg_rec.schema_name, cagg_rec.table_name
        ) INTO max_val;
      END IF;

      IF max_val IS NULL OR cagg_rec.bucket_width IS NULL OR NOT cagg_rec.bucket_fixed_width THEN
        -- No data, no bucket function info, or variable-width bucket: use minimum value.
        -- The next cagg refresh will compute the correct watermark.
        watermark_val := '-9223372036854775808'::bigint;
      ELSE
        -- Fixed-width bucket: watermark is max value + bucket width
        IF cagg_rec.column_type IN ('timestamptz'::regtype, 'timestamp'::regtype, 'date'::regtype) THEN
          bucket_width_val := (pg_catalog.date_part('epoch', cagg_rec.bucket_width::interval) * 1000000)::bigint;
        ELSE
          bucket_width_val := cagg_rec.bucket_width::bigint;
        END IF;
        watermark_val := max_val + bucket_width_val;
      END IF;

      INSERT INTO _timescaledb_catalog.continuous_aggs_watermark (mat_hypertable_id, watermark)
      VALUES (cagg_rec.mat_hypertable_id, watermark_val);
    END LOOP;
END;
$$;

-- Cleanup orphaned compression settings
WITH orphaned_settings AS (
     SELECT cs.relid, cl.relname
     FROM _timescaledb_catalog.compression_settings cs
     LEFT JOIN pg_class cl ON (cs.relid = cl.oid)
     WHERE cl.relname IS NULL
)
DELETE FROM _timescaledb_catalog.compression_settings AS cs
USING orphaned_settings AS os WHERE cs.relid = os.relid;

-- Remove self-referential foreign keys to eliminate pg_dump circular dependency warnings
ALTER TABLE _timescaledb_catalog.hypertable DROP CONSTRAINT IF EXISTS hypertable_compressed_hypertable_id_fkey;
ALTER TABLE _timescaledb_catalog.chunk DROP CONSTRAINT IF EXISTS chunk_compressed_chunk_id_fkey;

DROP FUNCTION IF EXISTS _timescaledb_functions.job_history_bsearch;

DROP FUNCTION IF EXISTS _timescaledb_functions.policy_process_hypertable_invalidations_check(JSONB);
DROP PROCEDURE IF EXISTS _timescaledb_functions.policy_process_hypertable_invalidations(INTEGER, JSONB);
DROP PROCEDURE IF EXISTS @extschema@.add_process_hypertable_invalidations_policy(REGCLASS, INTERVAL, BOOL, TIMESTAMPTZ, TEXT);
DROP PROCEDURE IF EXISTS @extschema@.remove_process_hypertable_invalidations_policy(REGCLASS, BOOL);

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.


-- Functions have to be run in 2 places:
-- 1) In pre-install between types.pre.sql and types.post.sql to set up the types.
-- 2) On every update to make sure the function points to the correct versioned.so


-- PostgreSQL composite types do not support constraint checks. That is why any table having a ts_interval column must use the following
-- function for constraint validation.
-- This function needs to be defined before executing pre_install/tables.sql because it is used as
-- validation constraint for columns of type ts_interval.

--the textual input/output is simply base64 encoding of the binary representation
CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_data_in(CSTRING)
   RETURNS _timescaledb_internal.compressed_data
   AS '$libdir/timescaledb-2.27.0-dev', 'ts_compressed_data_in'
   LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_data_out(_timescaledb_internal.compressed_data)
   RETURNS CSTRING
   AS '$libdir/timescaledb-2.27.0-dev', 'ts_compressed_data_out'
   LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_data_send(_timescaledb_internal.compressed_data)
   RETURNS BYTEA
   AS '$libdir/timescaledb-2.27.0-dev', 'ts_compressed_data_send'
   LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_data_recv(internal)
   RETURNS _timescaledb_internal.compressed_data
   AS '$libdir/timescaledb-2.27.0-dev', 'ts_compressed_data_recv'
   LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_data_info(_timescaledb_internal.compressed_data)
    RETURNS TABLE (algorithm name, has_nulls bool)
    LANGUAGE C STRICT IMMUTABLE
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_compressed_data_info';

CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_data_has_nulls(_timescaledb_internal.compressed_data)
    RETURNS BOOL
    LANGUAGE C STRICT IMMUTABLE
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_compressed_data_has_nulls';

CREATE OR REPLACE FUNCTION _timescaledb_functions.dimension_info_in(cstring)
    RETURNS _timescaledb_internal.dimension_info
    LANGUAGE C STRICT IMMUTABLE
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_dimension_info_in';

CREATE OR REPLACE FUNCTION _timescaledb_functions.dimension_info_out(_timescaledb_internal.dimension_info)
    RETURNS cstring
    LANGUAGE C STRICT IMMUTABLE
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_dimension_info_out';


-- Type for bloom filters used by the sparse indexes on compressed hypertables.
CREATE OR REPLACE FUNCTION _timescaledb_functions.bloom1in(cstring) RETURNS _timescaledb_internal.bloom1 AS 'byteain' LANGUAGE INTERNAL STRICT IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _timescaledb_functions.bloom1out(_timescaledb_internal.bloom1) RETURNS cstring AS 'byteaout' LANGUAGE INTERNAL STRICT IMMUTABLE PARALLEL SAFE;

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION @extschema@.set_integer_now_func(hypertable REGCLASS, integer_now_func REGPROC, replace_if_exists BOOL = false) RETURNS VOID
AS '$libdir/timescaledb-2.27.0-dev', 'ts_hypertable_set_integer_now_func'
LANGUAGE C VOLATILE STRICT;

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- Built-in function for calculating the next chunk interval when
-- using adaptive chunking. The function can be replaced by a
-- user-defined function with the same signature.
--
-- The parameters passed to the function are as follows:
--
-- dimension_id: the ID of the dimension to calculate the interval for
-- dimension_coord: the coordinate / point on the dimensional axis
-- where the tuple that triggered this chunk creation falls.
-- chunk_target_size: the target size in bytes that the chunk should have.
--
-- The function should return the new interval in dimension-specific
-- time (ususally microseconds).
CREATE OR REPLACE FUNCTION _timescaledb_functions.calculate_chunk_interval(
        dimension_id INTEGER,
        dimension_coord BIGINT,
        chunk_target_size BIGINT
) RETURNS BIGINT AS '$libdir/timescaledb-2.27.0-dev', 'ts_calculate_chunk_interval' LANGUAGE C;

-- Get the status of the chunk
CREATE OR REPLACE FUNCTION _timescaledb_functions.chunk_status(REGCLASS) RETURNS INT
AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_status' LANGUAGE C;

-- Get the status of the chunk as text array
CREATE OR REPLACE FUNCTION _timescaledb_functions.chunk_status_text(chunk_status int) RETURNS TEXT[]
AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_status_text' LANGUAGE C STRICT IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.chunk_status_text(chunk regclass) RETURNS TEXT[]
AS $$ SELECT _timescaledb_functions.chunk_status_text(_timescaledb_functions.chunk_status($1)); $$ LANGUAGE SQL STRICT IMMUTABLE PARALLEL SAFE SET search_path TO pg_catalog, pg_temp;;

--given a chunk's relid, return the id. Error out if not a chunk relid.
CREATE OR REPLACE FUNCTION _timescaledb_functions.chunk_id_from_relid(relid OID) RETURNS INTEGER
AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_id_from_relid' LANGUAGE C STABLE STRICT PARALLEL SAFE;

-- Show the definition of a chunk.
CREATE OR REPLACE FUNCTION _timescaledb_functions.show_chunk(chunk REGCLASS)
RETURNS TABLE(chunk_id INTEGER, hypertable_id INTEGER, schema_name NAME, table_name NAME, relkind "char", slices JSONB)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_show' LANGUAGE C VOLATILE;

-- Create a chunk with the given dimensional constraints (slices) as
-- given in the JSONB. If chunk_table is a valid relation, it will be
-- attached to the hypertable and used as the data table for the new
-- chunk. Note that schema_name and table_name need not be the same as
-- the existing schema and name for chunk_table. The provided chunk
-- table will be renamed and/or moved as necessary.
CREATE OR REPLACE FUNCTION _timescaledb_functions.create_chunk(
       hypertable REGCLASS,
       slices JSONB,
       schema_name NAME = NULL,
       table_name NAME = NULL,
	   chunk_table REGCLASS = NULL)
RETURNS TABLE(chunk_id INTEGER, hypertable_id INTEGER, schema_name NAME, table_name NAME, relkind "char", slices JSONB, created BOOLEAN)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_create' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.freeze_chunk(
   chunk REGCLASS)
RETURNS BOOL AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_freeze_chunk' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.unfreeze_chunk(
   chunk REGCLASS)
RETURNS BOOL AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_unfreeze_chunk' LANGUAGE C VOLATILE;

--wrapper for ts_chunk_drop
--drops the chunk table and its entry in the chunk catalog
CREATE OR REPLACE FUNCTION _timescaledb_functions.drop_chunk(
   chunk REGCLASS)
RETURNS BOOL AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_drop_single_chunk' LANGUAGE C VOLATILE;

-- internal API used by OSM extension to attach a table as a chunk of the hypertable
CREATE OR REPLACE FUNCTION _timescaledb_functions.attach_osm_table_chunk(
   hypertable REGCLASS,
   chunk REGCLASS)
RETURNS BOOL AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_attach_osm_table_chunk' LANGUAGE C VOLATILE;

-- internal API used by OSM extension to drop an OSM chunk table from the hypertable
CREATE OR REPLACE FUNCTION _timescaledb_functions.drop_osm_chunk(hypertable REGCLASS)
RETURNS BOOL AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_drop_osm_chunk' LANGUAGE C VOLATILE;

CREATE OR REPLACE PROCEDURE @extschema@.detach_chunk(chunk REGCLASS)
LANGUAGE C AS '$libdir/timescaledb-2.27.0-dev', 'ts_detach_chunk';

CREATE OR REPLACE PROCEDURE @extschema@.attach_chunk(hypertable REGCLASS,
   chunk REGCLASS,
   slices JSONB)
LANGUAGE C AS '$libdir/timescaledb-2.27.0-dev', 'ts_attach_chunk';
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- This file contains utilities for time conversion.

-- Return the minimum for the type. For time types, it will be the
-- Unix timestamp in microseconds.
CREATE OR REPLACE FUNCTION _timescaledb_functions.get_internal_time_min(REGTYPE) RETURNS BIGINT
AS '$libdir/timescaledb-2.27.0-dev', 'ts_get_internal_time_min' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- Return the minimum for the type. For time types, it will be the
-- Unix timestamp in microseconds.
CREATE OR REPLACE FUNCTION _timescaledb_functions.get_internal_time_max(REGTYPE) RETURNS BIGINT
AS '$libdir/timescaledb-2.27.0-dev', 'ts_get_internal_time_max' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.to_unix_microseconds(ts TIMESTAMPTZ) RETURNS BIGINT
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_pg_timestamp_to_unix_microseconds' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.to_timestamp(unixtime_us BIGINT) RETURNS TIMESTAMPTZ
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_pg_unix_microseconds_to_timestamp' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.to_timestamp_without_timezone(unixtime_us BIGINT)
  RETURNS TIMESTAMP
  AS '$libdir/timescaledb-2.27.0-dev', 'ts_pg_unix_microseconds_to_timestamp'
  LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.to_date(unixtime_us BIGINT)
  RETURNS DATE
  AS '$libdir/timescaledb-2.27.0-dev', 'ts_pg_unix_microseconds_to_date'
  LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.to_interval(unixtime_us BIGINT) RETURNS INTERVAL
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_pg_unix_microseconds_to_interval' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- Time can be represented in a hypertable as an int* (bigint/integer/smallint) or as a timestamp type (
-- with or without timezones). In metatables and other internal systems all time values are stored as bigint.
-- Converting from int* columns to internal representation is a cast to bigint.
-- Converting from timestamps to internal representation is conversion to epoch (in microseconds).

CREATE OR REPLACE FUNCTION _timescaledb_functions.interval_to_usec(
       chunk_interval INTERVAL
)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE PARALLEL SAFE AS
$BODY$
    SELECT (int_sec * 1000000)::bigint from extract(epoch from chunk_interval) as int_sec;
$BODY$ SET search_path TO pg_catalog, pg_temp;

CREATE OR REPLACE FUNCTION _timescaledb_functions.time_to_internal(time_val ANYELEMENT)
RETURNS BIGINT AS '$libdir/timescaledb-2.27.0-dev', 'ts_time_to_internal' LANGUAGE C VOLATILE STRICT;

CREATE OR REPLACE FUNCTION _timescaledb_functions.cagg_watermark(hypertable_id INTEGER)
RETURNS INT8 AS '$libdir/timescaledb-2.27.0-dev', 'ts_continuous_agg_watermark' LANGUAGE C STABLE STRICT PARALLEL RESTRICTED;

CREATE OR REPLACE FUNCTION _timescaledb_functions.cagg_watermark_materialized(hypertable_id INTEGER)
RETURNS INT8 AS '$libdir/timescaledb-2.27.0-dev', 'ts_continuous_agg_watermark_materialized' LANGUAGE C STABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.subtract_integer_from_now( hypertable_relid REGCLASS, lag INT8 )
RETURNS INT8 AS '$libdir/timescaledb-2.27.0-dev', 'ts_subtract_integer_from_now' LANGUAGE C STABLE STRICT;

-- Convert integer UNIX timestamps in microsecond to a timestamp range.
CREATE OR REPLACE FUNCTION _timescaledb_functions.make_multirange_from_internal_time(
    base tstzrange, low_usec bigint, high_usec bigint
) RETURNS TSTZMULTIRANGE AS
$body$
  select multirange(tstzrange(_timescaledb_functions.to_timestamp(low_usec),
			      _timescaledb_functions.to_timestamp(high_usec)));
$body$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE
SET search_path TO pg_catalog, pg_temp;

-- Convert integer UNIX timestamps in microsecond to a timestamp range.
CREATE OR REPLACE FUNCTION _timescaledb_functions.make_multirange_from_internal_time(
    base TSRANGE, low_usec bigint, high_usec bigint
) RETURNS TSMULTIRANGE AS
$body$
  select multirange(tsrange(_timescaledb_functions.to_timestamp_without_timezone(low_usec),
			    _timescaledb_functions.to_timestamp_without_timezone(high_usec)));
$body$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE
SET search_path TO pg_catalog, pg_temp;

-- Helper function to construct a range given an existing type from
-- UNIX timestamps in microsecond precision.
CREATE OR REPLACE FUNCTION _timescaledb_functions.make_range_from_internal_time(
    base anyrange, low_usec anyelement, high_usec anyelement
) RETURNS anyrange
AS '$libdir/timescaledb-2.27.0-dev', 'ts_make_range_from_internal_time'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- This file contains functions associated with creating new
-- hypertables.

-- Outputs the create_hypertable command to recreate the given hypertable.
--
-- This is currently used internally for our single hypertable backup tool
-- so that it knows how to restore the hypertable without user intervention.
--
-- It only works for hypertables with up to 2 dimensions.
CREATE OR REPLACE FUNCTION _timescaledb_functions.get_create_command(
    table_name NAME
)
    RETURNS TEXT LANGUAGE PLPGSQL VOLATILE AS
$BODY$
DECLARE
    h_id             INTEGER;
    schema_name      NAME;
    time_column      NAME;
    time_interval    BIGINT;
    space_column     NAME;
    space_partitions INTEGER;
    dimension_cnt    INTEGER;
    dimension_row    record;
    ret              TEXT;
BEGIN
    SELECT h.id, h.schema_name
    FROM _timescaledb_catalog.hypertable AS h
    WHERE h.table_name = get_create_command.table_name
    INTO h_id, schema_name;

    IF h_id IS NULL THEN
        RAISE EXCEPTION 'hypertable "%" not found', table_name
        USING ERRCODE = 'TS101';
    END IF;

    SELECT COUNT(*)
    FROM _timescaledb_catalog.dimension d
    WHERE d.hypertable_id = h_id
    INTO STRICT dimension_cnt;

    IF dimension_cnt > 2 THEN
        RAISE EXCEPTION 'get_create_command only supports hypertables with up to 2 dimensions'
        USING ERRCODE = 'TS101';
    END IF;

    FOR dimension_row IN
        SELECT *
        FROM _timescaledb_catalog.dimension d
        WHERE d.hypertable_id = h_id
        LOOP
        IF dimension_row.interval_length IS NOT NULL THEN
            time_column := dimension_row.column_name;
            time_interval := dimension_row.interval_length;
        ELSIF dimension_row.num_slices IS NOT NULL THEN
            space_column := dimension_row.column_name;
            space_partitions := dimension_row.num_slices;
        END IF;
    END LOOP;

    ret := format($$SELECT create_hypertable('%I.%I', '%s'$$, schema_name, table_name, time_column);
    IF space_column IS NOT NULL THEN
        ret := ret || format($$, '%I', %s$$, space_column, space_partitions);
    END IF;
    ret := ret || format($$, chunk_time_interval => %s, create_default_indexes=>FALSE);$$, time_interval);

    RETURN ret;
END
$BODY$ SET search_path TO pg_catalog, pg_temp;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- create constraint on newly created chunk based on hypertable constraint
CREATE OR REPLACE FUNCTION _timescaledb_functions.chunk_constraint_add_table_constraint(
    chunk_constraint_row  _timescaledb_catalog.chunk_constraint
)
    RETURNS VOID LANGUAGE PLPGSQL AS
$BODY$
DECLARE
    chunk_row _timescaledb_catalog.chunk;
    hypertable_row _timescaledb_catalog.hypertable;
    constraint_oid OID;
    constraint_type CHAR;
    check_sql TEXT;
    def TEXT;
    indx_tablespace NAME;
    tablespace_def TEXT;
BEGIN
    SELECT * INTO STRICT chunk_row FROM _timescaledb_catalog.chunk c WHERE c.id = chunk_constraint_row.chunk_id;
    SELECT * INTO STRICT hypertable_row FROM _timescaledb_catalog.hypertable h WHERE h.id = chunk_row.hypertable_id;

    IF chunk_constraint_row.dimension_slice_id IS NOT NULL THEN
	    RAISE 'cannot create dimension constraint %', chunk_constraint_row;
    ELSIF chunk_constraint_row.hypertable_constraint_name IS NOT NULL THEN

        SELECT oid, contype INTO STRICT constraint_oid, constraint_type FROM pg_constraint
        WHERE conname=chunk_constraint_row.hypertable_constraint_name AND
              conrelid = format('%I.%I', hypertable_row.schema_name, hypertable_row.table_name)::regclass::oid;

        IF constraint_type IN ('p','u') THEN
          -- since primary keys and unique constraints are backed by an index
          -- they might have an index tablespace assigned
          -- the tablspace is not part of the constraint definition so
          -- we have to append it explicitly to preserve it
          SELECT T.spcname INTO indx_tablespace
          FROM pg_constraint C, pg_class I, pg_tablespace T
          WHERE C.oid = constraint_oid AND C.contype IN ('p', 'u') AND I.oid = C.conindid AND I.reltablespace = T.oid;

          def := pg_get_constraintdef(constraint_oid);

        ELSIF constraint_type = 't' THEN
          -- constraint triggers are copied separately with normal triggers
          def := NULL;
        ELSE
          def := pg_get_constraintdef(constraint_oid);
        END IF;

    ELSE
        RAISE 'unknown constraint type';
    END IF;

    IF def IS NOT NULL THEN
        -- to allow for custom types with operators outside of pg_catalog
        -- we set search_path to @extschema@
        SET LOCAL search_path TO @extschema@, pg_temp;
        EXECUTE pg_catalog.format(
            $$ ALTER TABLE %I.%I ADD CONSTRAINT %I %s $$,
            chunk_row.schema_name, chunk_row.table_name, chunk_constraint_row.constraint_name, def
        );

        -- if constraint (primary or unique) needs a tablespace then add it
        -- via a separate ALTER INDEX SET TABLESPACE command. We cannot append it
        -- to the "def" string above since it leads to a SYNTAX error when
        -- "DEFERRABLE" or "INITIALLY DEFERRED" are used in the constraint
        IF indx_tablespace IS NOT NULL THEN
            EXECUTE pg_catalog.format(
                $$ ALTER INDEX %I.%I SET TABLESPACE %I $$,
                chunk_row.schema_name, chunk_constraint_row.constraint_name, indx_tablespace
            );
        END IF;

    END IF;
END
$BODY$ SET search_path TO pg_catalog, pg_temp;

-- Clone fk constraint from a hypertable to a compressed chunk
CREATE OR REPLACE FUNCTION _timescaledb_functions.constraint_clone(
    constraint_oid OID,
    target_oid REGCLASS
)
    RETURNS VOID LANGUAGE PLPGSQL AS
$BODY$
DECLARE
    constraint_name NAME;
    def TEXT;
BEGIN
    def := pg_get_constraintdef(constraint_oid);
    SELECT conname INTO STRICT constraint_name FROM pg_constraint WHERE oid = constraint_oid;

    IF def IS NULL THEN
        RAISE 'constraint not found';
    END IF;

    -- to allow for custom types with operators outside of pg_catalog
    -- we set search_path to @extschema@
    SET LOCAL search_path TO @extschema@, pg_temp;
    EXECUTE pg_catalog.format($$ ALTER TABLE %s ADD CONSTRAINT %I %s $$, target_oid::pg_catalog.text, constraint_name, def);

END
$BODY$ SET search_path TO pg_catalog, pg_temp;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- Deprecated partition hash function
CREATE OR REPLACE FUNCTION _timescaledb_functions.get_partition_for_key(val anyelement)
    RETURNS int
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_get_partition_for_key' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.get_partition_hash(val anyelement)
    RETURNS int
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_get_partition_hash' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- This file defines DDL functions for adding and manipulating hypertables.

-- Converts a regular postgres table to a hypertable.
--
-- relation - The OID of the table to be converted
-- time_column_name - Name of the column that contains time for a given record
-- partitioning_column - Name of the column to partition data by
-- number_partitions - (Optional) Number of partitions for data
-- associated_schema_name - (Optional) Schema for internal hypertable tables
-- associated_table_prefix - (Optional) Prefix for internal hypertable table names
-- chunk_time_interval - (Optional) Initial time interval for a chunk
-- create_default_indexes - (Optional) Whether or not to create the default indexes
-- if_not_exists - (Optional) Do not fail if table is already a hypertable
-- partitioning_func - (Optional) The partitioning function to use for spatial partitioning
-- migrate_data - (Optional) Set to true to migrate any existing data in the table to chunks
-- chunk_target_size - (Optional) The target size for chunks (e.g., '1000MB', 'estimate', or 'off')
-- chunk_sizing_func - (Optional) A function to calculate the chunk time interval for new chunks
-- time_partitioning_func - (Optional) The partitioning function to use for "time" partitioning
CREATE OR REPLACE FUNCTION @extschema@.create_hypertable(
    relation                REGCLASS,
    time_column_name        NAME,
    partitioning_column     NAME = NULL,
    number_partitions       INTEGER = NULL,
    associated_schema_name  NAME = NULL,
    associated_table_prefix NAME = NULL,
    chunk_time_interval     ANYELEMENT = NULL::bigint,
    create_default_indexes  BOOLEAN = TRUE,
    if_not_exists           BOOLEAN = FALSE,
    partitioning_func       REGPROC = NULL,
    migrate_data            BOOLEAN = FALSE,
    chunk_target_size       TEXT = NULL,
    chunk_sizing_func       REGPROC = '_timescaledb_functions.calculate_chunk_interval'::regproc,
    time_partitioning_func  REGPROC = NULL
) RETURNS TABLE(hypertable_id INT, schema_name NAME, table_name NAME, created BOOL) AS '$libdir/timescaledb-2.27.0-dev', 'ts_hypertable_create' LANGUAGE C VOLATILE;

-- A generalized hypertable creation API that can be used to convert a PostgreSQL table
-- with TIME/SERIAL/BIGSERIAL columns to a hypertable.
--
-- relation - The OID of the table to be converted
-- dimension - The dimension to use for partitioning
-- create_default_indexes (Optional) Whether or not to create the default indexes
-- if_not_exists (Optional) Do not fail if table is already a hypertable
-- migrate_data (Optional) Set to true to migrate any existing data in the table to chunks
CREATE OR REPLACE FUNCTION @extschema@.create_hypertable(
    relation                REGCLASS,
    dimension               _timescaledb_internal.dimension_info,
    create_default_indexes  BOOLEAN = TRUE,
    if_not_exists           BOOLEAN = FALSE,
    migrate_data            BOOLEAN = FALSE
) RETURNS TABLE(hypertable_id INT, created BOOL) AS '$libdir/timescaledb-2.27.0-dev', 'ts_hypertable_create_general' LANGUAGE C VOLATILE;


-- Set adaptive chunking. To disable, set chunk_target_size => 'off'.
CREATE OR REPLACE FUNCTION @extschema@.set_adaptive_chunking(
    hypertable                     REGCLASS,
    chunk_target_size              TEXT,
    INOUT chunk_sizing_func        REGPROC = '_timescaledb_functions.calculate_chunk_interval'::regproc,
    OUT chunk_target_size          BIGINT
) RETURNS RECORD AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_adaptive_set' LANGUAGE C VOLATILE;

-- Update chunk_time_interval for a hypertable [DEPRECATED].
--
-- hypertable - The OID of the table corresponding to a hypertable whose time
--     interval should be updated
-- chunk_time_interval - The new time interval. For hypertables with integral
--     time columns, this must be an integral type. For hypertables with a
--     TIMESTAMP/TIMESTAMPTZ/DATE type, it can be integral which is treated as
--     microseconds, or an INTERVAL type.
CREATE OR REPLACE FUNCTION @extschema@.set_chunk_time_interval(
    hypertable              REGCLASS,
    chunk_time_interval     ANYELEMENT,
    dimension_name          NAME = NULL
) RETURNS VOID AS '$libdir/timescaledb-2.27.0-dev', 'ts_dimension_set_interval' LANGUAGE C VOLATILE;

-- Update partition_interval for a hypertable.
--
-- hypertable - The OID of the table corresponding to a hypertable whose
--     partition interval should be updated
-- partition_interval - The new interval. For hypertables with integral/serial/bigserial
--     time columns, this must be an integral type. For hypertables with a
--     TIMESTAMP/TIMESTAMPTZ/DATE type, it can be integral which is treated as
--     microseconds, or an INTERVAL type.
CREATE OR REPLACE FUNCTION @extschema@.set_partitioning_interval(
    hypertable              REGCLASS,
    partition_interval      ANYELEMENT,
    dimension_name          NAME = NULL
) RETURNS VOID AS '$libdir/timescaledb-2.27.0-dev', 'ts_dimension_set_interval' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.set_number_partitions(
    hypertable              REGCLASS,
    number_partitions       INTEGER,
    dimension_name          NAME = NULL
) RETURNS VOID AS '$libdir/timescaledb-2.27.0-dev', 'ts_dimension_set_num_slices' LANGUAGE C VOLATILE;

-- Drop chunks older than the given timestamp for the specific
-- hypertable or continuous aggregate.
CREATE OR REPLACE FUNCTION @extschema@.drop_chunks(
    relation               REGCLASS,
    older_than             "any" = NULL,
    newer_than             "any" = NULL,
    verbose                BOOLEAN = FALSE,
    created_before         "any" = NULL,
    created_after          "any" = NULL
) RETURNS SETOF TEXT AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_drop_chunks'
LANGUAGE C VOLATILE PARALLEL UNSAFE;

-- show chunks older than or newer than a specific time.
-- `relation` must be a valid hypertable or continuous aggregate.
CREATE OR REPLACE FUNCTION @extschema@.show_chunks(
    relation               REGCLASS,
    older_than             "any" = NULL,
    newer_than             "any" = NULL,
    created_before         "any" = NULL,
    created_after          "any" = NULL
) RETURNS SETOF REGCLASS AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_show_chunks'
LANGUAGE C STABLE PARALLEL SAFE;

-- Add a dimension (of partitioning) to a hypertable [DEPRECATED]
--
-- hypertable - OID of the table to add a dimension to
-- column_name - NAME of the column to use in partitioning for this dimension
-- number_partitions - Number of partitions, for non-time dimensions
-- chunk_time_interval - Size of intervals for time dimensions (can be integral or INTERVAL)
-- partitioning_func - Function used to partition the column
-- if_not_exists - If set, and the dimension already exists, generate a notice instead of an error
CREATE OR REPLACE FUNCTION @extschema@.add_dimension(
    hypertable              REGCLASS,
    column_name             NAME,
    number_partitions       INTEGER = NULL,
    chunk_time_interval     ANYELEMENT = NULL::BIGINT,
    partitioning_func       REGPROC = NULL,
    if_not_exists           BOOLEAN = FALSE
) RETURNS TABLE(dimension_id INT, schema_name NAME, table_name NAME, column_name NAME, created BOOL)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_dimension_add' LANGUAGE C VOLATILE;

-- Add a dimension (of partitioning) to a hypertable.
--
-- hypertable - OID of the table to add a dimension to
-- dimension - Dimension to add
-- if_not_exists - If set, and the dimension already exists, generate a notice instead of an error
CREATE OR REPLACE FUNCTION @extschema@.add_dimension(
    hypertable              REGCLASS,
    dimension               _timescaledb_internal.dimension_info,
    if_not_exists           BOOLEAN = FALSE
) RETURNS TABLE(dimension_id INT, created BOOL)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_dimension_add_general' LANGUAGE C VOLATILE;

-- Enable tracking of statistics on a column of a hypertable.
--
-- hypertable - OID of the table to which the column belongs to
-- column_name - The column to track statistics for
-- if_not_exists - If set, and the entry already exists, generate a notice instead of an error
-- Returns the "id" of the entry created. The "enabled" field
-- is set to true if entry is created or exists already.
CREATE OR REPLACE FUNCTION @extschema@.enable_chunk_skipping(
    hypertable              REGCLASS,
    column_name             NAME,
    if_not_exists           BOOLEAN = FALSE
) RETURNS TABLE(column_stats_id INT, enabled BOOL)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_column_stats_enable' LANGUAGE C VOLATILE;

-- Disable tracking of statistics on a column of a hypertable.
--
-- hypertable - OID of the table to remove from
-- column_name - NAME of the column on which the stats are tracked
-- if_not_exists - If set, and the entry does not exist,
-- generate a notice instead of an error. The "disabled" field
-- is set to true if entry is deleted successfully.
CREATE OR REPLACE FUNCTION @extschema@.disable_chunk_skipping(
    hypertable              REGCLASS,
    column_name             NAME,
    if_not_exists           BOOLEAN = FALSE
) RETURNS TABLE(hypertable_id INT, column_name NAME, disabled BOOL)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_column_stats_disable' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.by_hash(column_name NAME, number_partitions INTEGER,
                                               partition_func regproc = NULL)
    RETURNS _timescaledb_internal.dimension_info LANGUAGE C
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_hash_dimension';

CREATE OR REPLACE FUNCTION @extschema@.by_range(column_name NAME,
                                                partition_interval ANYELEMENT = NULL::bigint,
                                                partition_func regproc = NULL)
    RETURNS _timescaledb_internal.dimension_info LANGUAGE C
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_range_dimension';

CREATE OR REPLACE FUNCTION @extschema@.attach_tablespace(
    tablespace NAME,
    hypertable REGCLASS,
    if_not_attached BOOLEAN = false
) RETURNS VOID
AS '$libdir/timescaledb-2.27.0-dev', 'ts_tablespace_attach' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.detach_tablespace(
    tablespace NAME,
    hypertable REGCLASS = NULL,
    if_attached BOOLEAN = false
) RETURNS INTEGER
AS '$libdir/timescaledb-2.27.0-dev', 'ts_tablespace_detach' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.detach_tablespaces(hypertable REGCLASS) RETURNS INTEGER
AS '$libdir/timescaledb-2.27.0-dev', 'ts_tablespace_detach_all_from_hypertable' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.show_tablespaces(hypertable REGCLASS) RETURNS SETOF NAME
AS '$libdir/timescaledb-2.27.0-dev', 'ts_tablespace_show' LANGUAGE C VOLATILE STRICT;

-- Refresh a continuous aggregate across the given window.
CREATE OR REPLACE PROCEDURE @extschema@.refresh_continuous_aggregate(
    continuous_aggregate     REGCLASS,
    window_start             "any",
    window_end               "any",
    force                    BOOLEAN = FALSE,
    options                  JSONB = NULL
) LANGUAGE C AS '$libdir/timescaledb-2.27.0-dev', 'ts_continuous_agg_refresh';

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

DROP EVENT TRIGGER IF EXISTS timescaledb_ddl_command_end;

CREATE OR REPLACE FUNCTION _timescaledb_functions.process_ddl_event() RETURNS event_trigger
AS '$libdir/timescaledb-2.27.0-dev', 'ts_timescaledb_process_ddl_event' LANGUAGE C;

--EVENT TRIGGER MUST exclude the ALTER EXTENSION tag.
CREATE EVENT TRIGGER timescaledb_ddl_command_end ON ddl_command_end
WHEN TAG IN ('ALTER TABLE','CREATE TRIGGER','CREATE TABLE','CREATE INDEX','ALTER INDEX', 'DROP TABLE', 'DROP INDEX', 'DROP SCHEMA')
EXECUTE FUNCTION _timescaledb_functions.process_ddl_event();

DROP EVENT TRIGGER IF EXISTS timescaledb_ddl_sql_drop;
CREATE EVENT TRIGGER timescaledb_ddl_sql_drop ON sql_drop
EXECUTE FUNCTION _timescaledb_functions.process_ddl_event();
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION _timescaledb_functions.first_sfunc(internal, anyelement, "any")
RETURNS internal
AS '$libdir/timescaledb-2.27.0-dev', 'ts_first_sfunc'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.first_combinefunc(internal, internal)
RETURNS internal
AS '$libdir/timescaledb-2.27.0-dev', 'ts_first_combinefunc'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.last_sfunc(internal, anyelement, "any")
RETURNS internal
AS '$libdir/timescaledb-2.27.0-dev', 'ts_last_sfunc'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.last_combinefunc(internal, internal)
RETURNS internal
AS '$libdir/timescaledb-2.27.0-dev', 'ts_last_combinefunc'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.bookend_finalfunc(internal, anyelement, "any")
RETURNS anyelement
AS '$libdir/timescaledb-2.27.0-dev', 'ts_bookend_finalfunc'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.bookend_serializefunc(internal)
RETURNS bytea
AS '$libdir/timescaledb-2.27.0-dev', 'ts_bookend_serializefunc'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.bookend_deserializefunc(bytea, internal)
RETURNS internal
AS '$libdir/timescaledb-2.27.0-dev', 'ts_bookend_deserializefunc'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;


-- We started using CREATE OR REPLACE AGGREGATE for aggregate creation once the syntax was fully supported
-- as it is easier to support idempotent changes this way. This will allow for changes to functions supporting
-- the aggregate, and, for instance, the definition and inclusion of inverse functions for window function
-- support. However, it should still be noted that changes to the data structures used for the internal
-- state of the aggregate must be backwards compatible and the old format must be accepted by any new functions
-- in order for them to continue working with Continuous Aggregates, where old states may have been materialized.

--This aggregate returns the "first" value of the first argument when ordered by the second argument.
--Ex. first(temp, time) returns the temp value for the row with the lowest time
CREATE OR REPLACE AGGREGATE @extschema@.first(anyelement, "any") (
    SFUNC = _timescaledb_functions.first_sfunc,
    STYPE = internal,
    COMBINEFUNC = _timescaledb_functions.first_combinefunc,
    SERIALFUNC = _timescaledb_functions.bookend_serializefunc,
    DESERIALFUNC = _timescaledb_functions.bookend_deserializefunc,
    PARALLEL = SAFE,
    FINALFUNC = _timescaledb_functions.bookend_finalfunc,
    FINALFUNC_EXTRA
);

--This aggregate returns the "last" value of the first argument when ordered by the second argument.
--Ex. last(temp, time) returns the temp value for the row with highest time
CREATE OR REPLACE AGGREGATE @extschema@.last(anyelement, "any") (
    SFUNC = _timescaledb_functions.last_sfunc,
    STYPE = internal,
    COMBINEFUNC = _timescaledb_functions.last_combinefunc,
    SERIALFUNC = _timescaledb_functions.bookend_serializefunc,
    DESERIALFUNC = _timescaledb_functions.bookend_deserializefunc,
    PARALLEL = SAFE,
    FINALFUNC = _timescaledb_functions.bookend_finalfunc,
    FINALFUNC_EXTRA
);
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- time_bucket returns the left edge of the bucket where ts falls into.
-- Buckets span an interval of time equal to the bucket_width and are aligned with the epoch.
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts TIMESTAMP) RETURNS TIMESTAMP
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_timestamp_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

-- bucketing of timestamptz happens at UTC time
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts TIMESTAMPTZ) RETURNS TIMESTAMPTZ
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_timestamptz_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

--bucketing on date should not do any timezone conversion
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts DATE) RETURNS DATE
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_date_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts UUID) RETURNS TIMESTAMPTZ
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_uuid_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

--bucketing with origin
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts TIMESTAMP, origin TIMESTAMP) RETURNS TIMESTAMP
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_timestamp_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts TIMESTAMPTZ, origin TIMESTAMPTZ) RETURNS TIMESTAMPTZ
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_timestamptz_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts DATE, origin DATE) RETURNS DATE
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_date_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts UUID, origin TIMESTAMPTZ) RETURNS TIMESTAMPTZ
  AS '$libdir/timescaledb-2.27.0-dev', 'ts_uuid_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

--bucketing with offset
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts TIMESTAMP, "offset" INTERVAL) RETURNS TIMESTAMP
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_timestamp_offset_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts TIMESTAMPTZ, "offset" INTERVAL) RETURNS TIMESTAMPTZ
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_timestamptz_offset_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts DATE, "offset" INTERVAL) RETURNS DATE
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_date_offset_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts UUID, "offset" INTERVAL) RETURNS TIMESTAMPTZ
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_uuid_offset_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

-- bucketing with timezone
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts TIMESTAMPTZ, timezone TEXT, origin TIMESTAMPTZ DEFAULT NULL, "offset" INTERVAL DEFAULT NULL) RETURNS TIMESTAMPTZ
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_timestamptz_timezone_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INTERVAL, ts UUID, timezone TEXT, origin TIMESTAMPTZ DEFAULT NULL, "offset" INTERVAL DEFAULT NULL) RETURNS TIMESTAMPTZ
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_uuid_timezone_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- bucketing of int
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width SMALLINT, ts SMALLINT) RETURNS SMALLINT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_int16_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INT, ts INT) RETURNS INT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_int32_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width BIGINT, ts BIGINT) RETURNS BIGINT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_int64_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

-- bucketing of int with offset
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width SMALLINT, ts SMALLINT, "offset" SMALLINT) RETURNS SMALLINT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_int16_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width INT, ts INT, "offset" INT) RETURNS INT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_int32_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;
CREATE OR REPLACE FUNCTION @extschema@.time_bucket(bucket_width BIGINT, ts BIGINT, "offset" BIGINT) RETURNS BIGINT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_int64_bucket' LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

-- This will align a range to a bucket size. It is similar to
-- time_bucket(), but takes a range and produces a range that starts
-- and ends at bucket boundaries.
CREATE OR REPLACE FUNCTION _timescaledb_functions.align_to_bucket(width interval, rng anyrange)
RETURNS anyrange AS
$body$
BEGIN
  RETURN _timescaledb_functions.make_range_from_internal_time(
         rng,
         @extschema@.time_bucket(width, lower(rng)),
         @extschema@.time_bucket(width, upper(rng) - '1 microsecond'::interval) + width
  );
END
$body$
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
SET search_path TO pg_catalog, pg_temp;

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION _timescaledb_functions.get_git_commit()
    RETURNS TABLE(commit_tag TEXT, commit_hash TEXT, commit_time TIMESTAMPTZ)
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_get_git_commit' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.get_os_info()
    RETURNS TABLE(sysname TEXT, version TEXT, release TEXT, version_pretty TEXT)
    AS '$libdir/timescaledb-2.27.0-dev', 'ts_get_os_info' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.tsl_loaded() RETURNS BOOLEAN
AS '$libdir/timescaledb-2.27.0-dev', 'ts_tsl_loaded' LANGUAGE C;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- This file contains utility functions to get the relation size
-- of hypertables, chunks, and indexes on hypertables.

CREATE OR REPLACE FUNCTION _timescaledb_functions.index_matches(index1 regclass, index2 regclass) RETURNS BOOLEAN
AS '$libdir/timescaledb-2.27.0-dev', 'ts_index_matches' LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.relation_size(relation REGCLASS)
RETURNS TABLE (total_size BIGINT, heap_size BIGINT, index_size BIGINT, toast_size BIGINT)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_relation_size' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.relation_approximate_size(relation REGCLASS)
RETURNS TABLE (total_size BIGINT, heap_size BIGINT, index_size BIGINT, toast_size BIGINT)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_relation_approximate_size' LANGUAGE C STRICT VOLATILE;

CREATE OR REPLACE VIEW _timescaledb_internal.hypertable_chunk_local_size AS
SELECT
    h.schema_name AS hypertable_schema,
    h.table_name AS hypertable_name,
    h.id AS hypertable_id,
    c.id AS chunk_id,
    c.schema_name AS chunk_schema,
    c.table_name AS chunk_name,
    COALESCE((relsize).total_size, 0) AS total_bytes,
    COALESCE((relsize).heap_size, 0) AS heap_bytes,
    COALESCE((relsize).index_size, 0) AS index_bytes,
    COALESCE((relsize).toast_size, 0) AS toast_bytes,
    COALESCE((relcompsize).total_size, 0) AS compressed_total_size,
    COALESCE((relcompsize).heap_size, 0) AS compressed_heap_size,
    COALESCE((relcompsize).index_size, 0) AS compressed_index_size,
    COALESCE((relcompsize).toast_size, 0) AS compressed_toast_size
FROM
    _timescaledb_catalog.hypertable h
    JOIN _timescaledb_catalog.chunk c ON h.id = c.hypertable_id
    JOIN pg_class cl ON cl.relname = c.table_name AND cl.relkind = 'r'
    JOIN pg_namespace n ON n.oid = cl.relnamespace
    AND n.nspname = c.schema_name
    JOIN LATERAL _timescaledb_functions.relation_size(cl.oid) AS relsize ON TRUE
    LEFT JOIN _timescaledb_catalog.compression_settings cs ON cs.relid = cl.oid
    LEFT JOIN LATERAL _timescaledb_functions.relation_size(cs.compress_relid) AS relcompsize ON TRUE;

GRANT SELECT ON  _timescaledb_internal.hypertable_chunk_local_size TO PUBLIC;

CREATE OR REPLACE FUNCTION _timescaledb_functions.hypertable_local_size(
	schema_name_in name,
	table_name_in name)
RETURNS TABLE (
	table_bytes BIGINT,
	index_bytes BIGINT,
	toast_bytes BIGINT,
	total_bytes BIGINT)
LANGUAGE SQL VOLATILE STRICT AS
$BODY$
    /* get the main hypertable id and sizes */
    WITH _hypertable_sizes AS (
        SELECT
            id,
            COALESCE((relsize).total_size, 0) AS total_bytes,
            COALESCE((relsize).heap_size, 0) AS heap_bytes,
            COALESCE((relsize).index_size, 0) AS index_bytes,
            COALESCE((relsize).toast_size, 0) AS toast_bytes,
            0::BIGINT AS compressed_total_size,
            0::BIGINT AS compressed_index_size,
            0::BIGINT AS compressed_toast_size,
            0::BIGINT AS compressed_heap_size
        FROM
            _timescaledb_catalog.hypertable ht
            JOIN pg_class c ON relname = ht.table_name AND c.relkind = 'r'
            JOIN pg_namespace n ON n.oid = c.relnamespace
            AND n.nspname = ht.schema_name
            JOIN LATERAL _timescaledb_functions.relation_size(c.oid) AS relsize ON TRUE
        WHERE
            schema_name = schema_name_in
            AND table_name = table_name_in
    ),
    /* calculate the size of the hypertable chunks */
    _chunk_sizes AS (
        SELECT
            chunk_id,
            COALESCE(ch.total_bytes, 0) AS total_bytes,
            COALESCE(ch.heap_bytes, 0) AS heap_bytes,
            COALESCE(ch.index_bytes, 0) AS index_bytes,
            COALESCE(ch.toast_bytes, 0) AS toast_bytes,
            COALESCE(ch.compressed_total_size, 0) AS compressed_total_size,
            COALESCE(ch.compressed_index_size, 0) AS compressed_index_size,
            COALESCE(ch.compressed_toast_size, 0) AS compressed_toast_size,
            COALESCE(ch.compressed_heap_size, 0) AS compressed_heap_size
        FROM
            _timescaledb_internal.hypertable_chunk_local_size ch
            JOIN _hypertable_sizes ht ON ht.id = ch.hypertable_id
        WHERE hypertable_schema = schema_name_in
          AND hypertable_name = table_name_in
    )
    /* calculate the SUM of the hypertable and chunk sizes */
	SELECT
		(SUM(heap_bytes)  + SUM(compressed_heap_size))::BIGINT AS heap_bytes,
		(SUM(index_bytes) + SUM(compressed_index_size))::BIGINT AS index_bytes,
		(SUM(toast_bytes) + SUM(compressed_toast_size))::BIGINT AS toast_bytes,
		(SUM(total_bytes) + SUM(compressed_total_size))::BIGINT AS total_bytes
	FROM
		(SELECT * FROM _hypertable_sizes
         UNION ALL
         SELECT * FROM _chunk_sizes) AS sizes;
$BODY$ SET search_path TO pg_catalog, pg_temp;

-- Get relation size of hypertable
-- like pg_relation_size(hypertable)
--
-- hypertable - hypertable to get size of
--
-- Returns:
-- table_bytes        - Disk space used by hypertable (like pg_relation_size(hypertable))
-- index_bytes        - Disk space used by indexes
-- toast_bytes        - Disk space of toast tables
-- total_bytes        - Total disk space used by the specified table, including all indexes and TOAST data

CREATE OR REPLACE FUNCTION @extschema@.hypertable_detailed_size(
    hypertable              REGCLASS)
RETURNS TABLE (table_bytes BIGINT,
               index_bytes BIGINT,
               toast_bytes BIGINT,
               total_bytes BIGINT,
               node_name   NAME)
LANGUAGE PLPGSQL VOLATILE STRICT AS
$BODY$
DECLARE
        table_name       NAME = NULL;
        schema_name      NAME = NULL;
BEGIN
        SELECT relname, nspname
        INTO table_name, schema_name
        FROM pg_class c
        INNER JOIN pg_namespace n ON (n.OID = c.relnamespace)
        INNER JOIN _timescaledb_catalog.hypertable ht ON (ht.schema_name = n.nspname AND ht.table_name = c.relname)
        WHERE c.OID = hypertable;

        IF table_name IS NULL THEN
                SELECT h.schema_name, h.table_name
                INTO schema_name, table_name
                FROM pg_class c
                INNER JOIN pg_namespace n ON (n.OID = c.relnamespace)
                INNER JOIN _timescaledb_catalog.continuous_agg a ON (a.user_view_schema = n.nspname AND a.user_view_name = c.relname)
                INNER JOIN _timescaledb_catalog.hypertable h ON h.id = a.mat_hypertable_id
                WHERE c.OID = hypertable;

	        IF table_name IS NULL THEN
                        RETURN;
                END IF;
        END IF;

			RETURN QUERY
			SELECT *, NULL::name
			FROM _timescaledb_functions.hypertable_local_size(schema_name, table_name);
END;
$BODY$ SET search_path TO pg_catalog, pg_temp;

--- returns total-bytes for a hypertable (includes table + index)
CREATE OR REPLACE FUNCTION @extschema@.hypertable_size(
    hypertable              REGCLASS)
RETURNS BIGINT
LANGUAGE SQL VOLATILE STRICT AS
$BODY$
   SELECT total_bytes::bigint FROM @extschema@.hypertable_detailed_size(hypertable);
$BODY$ SET search_path TO pg_catalog, pg_temp;

-- Get approximate relation size of hypertable
--
-- hypertable - hypertable to get approximate size of
--
-- Returns:
-- table_bytes        - Approximate disk space used by hypertable
-- index_bytes        - Approximate disk space used by indexes
-- toast_bytes        - Approximate disk space of toast tables
-- total_bytes        - Total approximate disk space used by the specified table, including all indexes and TOAST data
CREATE OR REPLACE FUNCTION @extschema@.hypertable_approximate_detailed_size(relation REGCLASS)
RETURNS TABLE (table_bytes BIGINT, index_bytes BIGINT, toast_bytes BIGINT, total_bytes BIGINT)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_hypertable_approximate_size' LANGUAGE C VOLATILE;

--- returns approximate total-bytes for a hypertable (includes table + index)
CREATE OR REPLACE FUNCTION @extschema@.hypertable_approximate_size(
    hypertable              REGCLASS)
RETURNS BIGINT
LANGUAGE SQL VOLATILE STRICT AS
$BODY$
   SELECT sum(total_bytes)::bigint
   FROM @extschema@.hypertable_approximate_detailed_size(hypertable);
$BODY$ SET search_path TO pg_catalog, pg_temp;

CREATE OR REPLACE FUNCTION _timescaledb_functions.chunks_local_size(
    schema_name_in name,
    table_name_in name)
RETURNS TABLE (
    chunk_id    integer,
    chunk_schema NAME,
    chunk_name  NAME,
    table_bytes bigint,
    index_bytes bigint,
    toast_bytes bigint,
    total_bytes bigint)
LANGUAGE SQL VOLATILE STRICT AS
$BODY$
   SELECT
      ch.chunk_id,
      ch.chunk_schema,
      ch.chunk_name,
      (ch.total_bytes - COALESCE( ch.index_bytes , 0 ) - COALESCE( ch.toast_bytes, 0 ) + COALESCE( ch.compressed_heap_size , 0 ))::bigint  as heap_bytes,
      (COALESCE( ch.index_bytes, 0 ) + COALESCE( ch.compressed_index_size , 0) )::bigint as index_bytes,
      (COALESCE( ch.toast_bytes, 0 ) + COALESCE( ch.compressed_toast_size, 0 ))::bigint as toast_bytes,
      (ch.total_bytes + COALESCE( ch.compressed_total_size, 0 ))::bigint as total_bytes
   FROM
	  _timescaledb_internal.hypertable_chunk_local_size ch
   WHERE
      ch.hypertable_schema = schema_name_in
      AND ch.hypertable_name = table_name_in;
$BODY$ SET search_path TO pg_catalog, pg_temp;

-- Get relation size of the chunks of an hypertable
-- hypertable - hypertable to get size of
--
-- Returns:
-- chunk_schema                  - schema name for chunk
-- chunk_name                    - chunk table name
-- table_bytes                   - Disk space used by chunk table
-- index_bytes                   - Disk space used by indexes
-- toast_bytes                   - Disk space of toast tables
-- total_bytes                   - Disk space used in total
-- node_name                     - node on which chunk lives if this is
--                              a distributed hypertable.
CREATE OR REPLACE FUNCTION @extschema@.chunks_detailed_size(
    hypertable              REGCLASS
)
RETURNS TABLE (
               chunk_schema NAME,
               chunk_name NAME,
               table_bytes BIGINT,
               index_bytes BIGINT,
               toast_bytes BIGINT,
               total_bytes BIGINT,
               node_name   NAME)
LANGUAGE PLPGSQL VOLATILE STRICT AS
$BODY$
DECLARE
        table_name       NAME;
        schema_name      NAME;
BEGIN
        SELECT relname, nspname
        INTO table_name, schema_name
        FROM pg_class c
        INNER JOIN pg_namespace n ON (n.OID = c.relnamespace)
        INNER JOIN _timescaledb_catalog.hypertable ht ON (ht.schema_name = n.nspname AND ht.table_name = c.relname)
        WHERE c.OID = hypertable;

        IF table_name IS NULL THEN
            SELECT h.schema_name, h.table_name
            INTO schema_name, table_name
            FROM pg_class c
            INNER JOIN pg_namespace n ON (n.OID = c.relnamespace)
            INNER JOIN _timescaledb_catalog.continuous_agg a ON (a.user_view_schema = n.nspname AND a.user_view_name = c.relname)
            INNER JOIN _timescaledb_catalog.hypertable h ON h.id = a.mat_hypertable_id
            WHERE c.OID = hypertable;

            IF table_name IS NULL THEN
                RETURN;
            END IF;
		END IF;

    RETURN QUERY SELECT chl.chunk_schema, chl.chunk_name, chl.table_bytes, chl.index_bytes,
                        chl.toast_bytes, chl.total_bytes, NULL::NAME
            FROM _timescaledb_functions.chunks_local_size(schema_name, table_name) chl;
END;
$BODY$ SET search_path TO pg_catalog, pg_temp;
---------- end of detailed size functions ------

CREATE OR REPLACE FUNCTION _timescaledb_functions.range_value_to_pretty(
    time_value      BIGINT,
    column_type     REGTYPE
)
    RETURNS TEXT LANGUAGE PLPGSQL STABLE AS
$BODY$
DECLARE
BEGIN
    IF NOT (time_value > (-9223372036854775808)::bigint AND
	   	    time_value < 9223372036854775807::bigint) THEN
        RETURN '';
    END IF;
    IF time_value IS NULL THEN
        RETURN format('%L', NULL);
    END IF;
    CASE column_type
      WHEN 'BIGINT'::regtype, 'INTEGER'::regtype, 'SMALLINT'::regtype THEN
        RETURN format('%L', time_value); -- scale determined by user.
      WHEN 'TIMESTAMP'::regtype, 'TIMESTAMPTZ'::regtype THEN
        -- assume time_value is in microsec
        RETURN format('%1$L', _timescaledb_functions.to_timestamp(time_value)); -- microseconds
      WHEN 'DATE'::regtype THEN
        RETURN format('%L', timezone('UTC',_timescaledb_functions.to_timestamp(time_value))::date);
      ELSE
        RETURN time_value;
    END CASE;
END
$BODY$ SET search_path TO pg_catalog, pg_temp;

-- Convenience function to return approximate row count
--
-- relation - table or hypertable to get approximate row count for
--
-- Returns:
-- Estimated number of rows according to catalog tables
CREATE OR REPLACE FUNCTION @extschema@.approximate_row_count(relation REGCLASS)
RETURNS BIGINT
LANGUAGE PLPGSQL VOLATILE STRICT AS
$BODY$
DECLARE
    v_mat_ht REGCLASS = NULL;
    v_name NAME = NULL;
    v_schema NAME = NULL;
    v_hypertable_id INTEGER;
BEGIN
    -- Check if input relation is continuous aggregate view then
    -- get the corresponding materialized hypertable and schema name
    SELECT format('%I.%I', ht.schema_name, ht.table_name)::regclass INTO v_mat_ht
      FROM pg_class c
      JOIN pg_namespace n ON (n.OID = c.relnamespace)
      JOIN _timescaledb_catalog.continuous_agg a ON (a.user_view_schema = n.nspname AND a.user_view_name = c.relname)
      JOIN _timescaledb_catalog.hypertable ht ON (a.mat_hypertable_id = ht.id)
      WHERE c.OID = relation;

    IF FOUND THEN
        relation = v_mat_ht;
    END IF;

    SELECT nspname, relname FROM pg_class c
    INNER JOIN pg_namespace n ON (n.OID = c.relnamespace)
    INTO v_schema, v_name
    WHERE c.OID = relation;

    -- for hypertables return the sum of the row counts of all chunks
    SELECT id FROM _timescaledb_catalog.hypertable INTO v_hypertable_id WHERE table_name = v_name AND schema_name = v_schema;
    IF FOUND THEN
        RETURN (SELECT coalesce(sum(_timescaledb_functions.get_approx_row_count(format('%I.%I',schema_name,table_name))),0)
          FROM _timescaledb_catalog.chunk
          WHERE hypertable_id = v_hypertable_id);
    END IF;

		IF EXISTS (SELECT FROM pg_inherits WHERE inhparent = relation) THEN
		RETURN (
        SELECT _timescaledb_functions.get_approx_row_count(relation) + COALESCE(SUM(@extschema@.approximate_row_count(i.inhrelid)),0) FROM pg_inherits i
        WHERE i.inhparent = relation
     );
    END IF;

    -- Check for input relation is Plain RELATION
    RETURN _timescaledb_functions.get_approx_row_count(relation);
END;
$BODY$ SET search_path TO pg_catalog, pg_temp;

CREATE OR REPLACE FUNCTION _timescaledb_functions.estimate_compressed_batch_size(relation REGCLASS)
RETURNS FLOAT8
AS '$libdir/timescaledb-2.27.0-dev', 'ts_estimate_compressed_batch_size' LANGUAGE C STRICT STABLE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.get_approx_row_count(relation REGCLASS)
RETURNS BIGINT
LANGUAGE PLPGSQL VOLATILE STRICT AS
$BODY$
DECLARE
  v_schema NAME;
  v_name NAME;
  v_chunk_id INTEGER;
  v_oid OID;
  row_count BIGINT = 0;
BEGIN
  SELECT nspname, relname INTO v_schema, v_name FROM pg_class c JOIN pg_namespace n ON (n.OID = c.relnamespace) WHERE c.OID = relation;

  -- we only need to check if the relation has a compressed chunk if it is a chunk
  SELECT compress_relid FROM _timescaledb_catalog.compression_settings INTO v_oid WHERE relid = relation;

  IF v_oid IS NOT NULL THEN
    row_count := (SELECT CASE WHEN reltuples IS NULL THEN 0 WHEN reltuples < 0 THEN 0 ELSE reltuples * _timescaledb_functions.estimate_compressed_batch_size(oid) END FROM pg_class WHERE oid = v_oid);
  END IF;

  row_count := COALESCE((SELECT row_count + CASE WHEN reltuples < 0 OR relkind = 'p' THEN 0 ELSE reltuples END FROM pg_class WHERE oid = relation), 0);

  RETURN row_count;
END
$BODY$ SET search_path TO pg_catalog, pg_temp;

-------- stats related to compression ------
CREATE OR REPLACE VIEW _timescaledb_internal.compressed_chunk_stats AS
SELECT
    srcht.schema_name AS hypertable_schema,
    srcht.table_name AS hypertable_name,
    srcch.schema_name AS chunk_schema,
    srcch.table_name AS chunk_name,
    CASE WHEN srcch.status & 1 = 1 THEN
        'Compressed'::text
    ELSE
        'Uncompressed'::text
    END AS compression_status,
    map.uncompressed_heap_size,
    map.uncompressed_index_size,
    map.uncompressed_toast_size,
    map.uncompressed_heap_size + map.uncompressed_toast_size + map.uncompressed_index_size AS uncompressed_total_size,
    map.compressed_heap_size,
    map.compressed_index_size,
    map.compressed_toast_size,
    map.compressed_heap_size + map.compressed_toast_size + map.compressed_index_size AS compressed_total_size
FROM
    _timescaledb_catalog.hypertable AS srcht
    JOIN _timescaledb_catalog.chunk AS srcch ON srcht.id = srcch.hypertable_id
        AND srcht.compressed_hypertable_id IS NOT NULL
    LEFT JOIN _timescaledb_catalog.compression_chunk_size map ON srcch.id = map.chunk_id;

GRANT SELECT ON _timescaledb_internal.compressed_chunk_stats TO PUBLIC;

CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_chunk_local_stats(schema_name_in name, table_name_in name)
    RETURNS TABLE (
        chunk_schema name,
        chunk_name name,
        compression_status text,
        before_compression_table_bytes bigint,
        before_compression_index_bytes bigint,
        before_compression_toast_bytes bigint,
        before_compression_total_bytes bigint,
        after_compression_table_bytes bigint,
        after_compression_index_bytes bigint,
        after_compression_toast_bytes bigint,
        after_compression_total_bytes bigint)
    LANGUAGE SQL
    STABLE STRICT
    AS
$BODY$
    SELECT
        ch.chunk_schema,
        ch.chunk_name,
        ch.compression_status,
        ch.uncompressed_heap_size,
        ch.uncompressed_index_size,
        ch.uncompressed_toast_size,
        ch.uncompressed_total_size,
        ch.compressed_heap_size,
        ch.compressed_index_size,
        ch.compressed_toast_size,
        ch.compressed_total_size
    FROM
        _timescaledb_internal.compressed_chunk_stats ch
    WHERE
        ch.hypertable_schema = schema_name_in
        AND ch.hypertable_name = table_name_in;
$BODY$ SET search_path TO pg_catalog, pg_temp;

-- Get per chunk compression statistics for a hypertable that has
-- compression enabled
CREATE OR REPLACE FUNCTION @extschema@.chunk_compression_stats (hypertable REGCLASS)
    RETURNS TABLE (
        chunk_schema name,
        chunk_name name,
        compression_status text,
        before_compression_table_bytes bigint,
        before_compression_index_bytes bigint,
        before_compression_toast_bytes bigint,
        before_compression_total_bytes bigint,
        after_compression_table_bytes bigint,
        after_compression_index_bytes bigint,
        after_compression_toast_bytes bigint,
        after_compression_total_bytes bigint,
        node_name name)
    LANGUAGE PLPGSQL
    STABLE STRICT
    AS $BODY$
DECLARE
    table_name name;
    schema_name name;
BEGIN
    SELECT
      relname, nspname
    INTO
	    table_name, schema_name
    FROM
        pg_class c
        INNER JOIN pg_namespace n ON (n.OID = c.relnamespace)
        INNER JOIN _timescaledb_catalog.hypertable ht ON (ht.schema_name = n.nspname
                AND ht.table_name = c.relname)
    WHERE
        c.OID = hypertable;

    IF table_name IS NULL THEN
	    RETURN;
	END IF;

  RETURN QUERY
  SELECT
      *,
      NULL::name
  FROM
      _timescaledb_functions.compressed_chunk_local_stats(schema_name, table_name);
END;
$BODY$ SET search_path TO pg_catalog, pg_temp;

CREATE OR REPLACE FUNCTION @extschema@.chunk_columnstore_stats (hypertable REGCLASS)
    RETURNS TABLE (
        chunk_schema name,
        chunk_name name,
        compression_status text,
        before_compression_table_bytes bigint,
        before_compression_index_bytes bigint,
        before_compression_toast_bytes bigint,
        before_compression_total_bytes bigint,
        after_compression_table_bytes bigint,
        after_compression_index_bytes bigint,
        after_compression_toast_bytes bigint,
        after_compression_total_bytes bigint,
        node_name name)
    LANGUAGE SQL
    STABLE STRICT
    AS 'SELECT * FROM @extschema@.chunk_compression_stats($1)'
    SET search_path TO pg_catalog, pg_temp;

-- Get compression statistics for a hypertable that has
-- compression enabled
CREATE OR REPLACE FUNCTION @extschema@.hypertable_compression_stats (hypertable REGCLASS)
    RETURNS TABLE (
        total_chunks bigint,
        number_compressed_chunks bigint,
        before_compression_table_bytes bigint,
        before_compression_index_bytes bigint,
        before_compression_toast_bytes bigint,
        before_compression_total_bytes bigint,
        after_compression_table_bytes bigint,
        after_compression_index_bytes bigint,
        after_compression_toast_bytes bigint,
        after_compression_total_bytes bigint,
        node_name name)
    LANGUAGE SQL
    STABLE STRICT
    AS
$BODY$
	SELECT
        count(*)::bigint AS total_chunks,
        (count(*) FILTER (WHERE ch.compression_status = 'Compressed'))::bigint AS number_compressed_chunks,
        sum(ch.before_compression_table_bytes)::bigint AS before_compression_table_bytes,
        sum(ch.before_compression_index_bytes)::bigint AS before_compression_index_bytes,
        sum(ch.before_compression_toast_bytes)::bigint AS before_compression_toast_bytes,
        sum(ch.before_compression_total_bytes)::bigint AS before_compression_total_bytes,
        sum(ch.after_compression_table_bytes)::bigint AS after_compression_table_bytes,
        sum(ch.after_compression_index_bytes)::bigint AS after_compression_index_bytes,
        sum(ch.after_compression_toast_bytes)::bigint AS after_compression_toast_bytes,
        sum(ch.after_compression_total_bytes)::bigint AS after_compression_total_bytes,
        ch.node_name
    FROM
	    @extschema@.chunk_compression_stats(hypertable) ch
    GROUP BY
        ch.node_name;
$BODY$ SET search_path TO pg_catalog, pg_temp;

CREATE OR REPLACE FUNCTION @extschema@.hypertable_columnstore_stats (hypertable REGCLASS)
    RETURNS TABLE (
        total_chunks bigint,
        number_compressed_chunks bigint,
        before_compression_table_bytes bigint,
        before_compression_index_bytes bigint,
        before_compression_toast_bytes bigint,
        before_compression_total_bytes bigint,
        after_compression_table_bytes bigint,
        after_compression_index_bytes bigint,
        after_compression_toast_bytes bigint,
        after_compression_total_bytes bigint,
        node_name name)
    LANGUAGE SQL
    STABLE STRICT
    AS 'SELECT * FROM @extschema@.hypertable_compression_stats($1)'
    SET search_path TO pg_catalog, pg_temp;

-------------Get index size for hypertables -------

CREATE OR REPLACE FUNCTION @extschema@.hypertable_index_size(
    index_name              REGCLASS
)
RETURNS BIGINT
LANGUAGE SQL VOLATILE STRICT AS
$BODY$
  SELECT
  	pg_relation_size(ht_i.indexrelid) + COALESCE(sum(pg_relation_size(ch_i.indexrelid)), 0)
  FROM pg_index ht_i
  LEFT JOIN pg_inherits ch on ch.inhparent = ht_i.indrelid
  LEFT JOIN pg_index ch_i on ch_i.indrelid = ch.inhrelid and _timescaledb_functions.index_matches(ht_i.indexrelid, ch_i.indexrelid)
  WHERE ht_i.indexrelid = index_name
  GROUP BY ht_i.indexrelid;
$BODY$ SET search_path TO pg_catalog, pg_temp;

-------------End index size for hypertables -------

CREATE OR REPLACE FUNCTION _timescaledb_functions.estimate_uncompressed_size(IN regclass, OUT tuples bigint, OUT relation_size bigint, OUT index_size bigint, OUT total_size bigint)
AS $$
DECLARE
  v_compressed_chunk regclass;
  v_uncompressed_chunk regclass;
  v_index regclass;
  v_fixed_column_size integer;
  v_num_varlen_columns integer;
  v_tuple_header integer;
  v_tuple_data integer;
  v_index_header integer;
  v_index_size bigint;
  v_columns integer;
  v_varlen_query text:= '';
  v_multiplier decimal:=1.15; -- multiplier to account for page header, fill factor and alignment padding
  v_index_multiplier decimal:=1.25; -- multiplier to account for page header, fill factor and alignment padding
BEGIN

  v_compressed_chunk := $1;

  SELECT relid INTO v_uncompressed_chunk FROM _timescaledb_catalog.compression_settings WHERE compress_relid = v_compressed_chunk;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT
    count(*), sum(attlen) FILTER(WHERE attlen > 0), count(*) FILTER(WHERE attlen = -1)
  FROM pg_attribute
    INTO v_columns, v_fixed_column_size, v_num_varlen_columns
  WHERE attrelid = v_uncompressed_chunk AND attnum > 0 AND NOT attisdropped;

  -- header size = MAXALIGN(Header + NullBitmap) + MAXALIGN(Data)
  v_tuple_header := 23; -- Heap tuple header
  v_tuple_header := v_tuple_header + ((v_columns + 7) / 8); -- Null bitmap size
  v_tuple_header := v_tuple_header + 7 & ~7; -- align to 8 bytes

  v_tuple_data := v_fixed_column_size; -- Fixed-length column sizes
  v_tuple_data := v_tuple_data + 7 & ~7; -- align to 8 bytes

  IF v_num_varlen_columns > 0 THEN
	  SELECT ' + (' || string_agg(format('sum(_timescaledb_functions.compressed_data_column_size(%I,NULL::%s))', attname, pg_catalog.format_type(atttypid, atttypmod)), ' + ') || ')' FROM pg_attribute INTO v_varlen_query WHERE attrelid = v_uncompressed_chunk AND attnum > 0 AND NOT attisdropped AND attlen = -1;
  END IF;

  EXECUTE format('SELECT sum(_ts_meta_count) FROM %s', v_compressed_chunk) INTO tuples;
  -- we can optimize the following query if all columns are fixed size
  EXECUTE format('SELECT ((%s * (%s + %s)) %s) * %s FROM %s', tuples, v_tuple_header, v_tuple_data, v_varlen_query, v_multiplier, v_compressed_chunk) INTO relation_size;

  index_size := 0;
  FOR v_index, v_varlen_query, v_columns IN
    SELECT
      i.indexrelid::regclass,
      (SELECT ' + (' || string_agg(format('sum(_timescaledb_functions.compressed_data_column_size(%I,NULL::%s))', attname, pg_catalog.format_type(atttypid, atttypmod)), ' + ' ORDER BY attnum) || ')' FROM pg_attribute att WHERE att.attrelid=i.indrelid AND attnum =ANY(i.indkey)),
      array_length(i.indkey,1) FROM pg_index i
    WHERE i.indrelid = v_uncompressed_chunk
  LOOP
    v_index_header := 8; -- Index tuple header

    -- v_compressed_chunk is a regclass, which will be properly escaped when cast to `text`
    EXECUTE format('SELECT ((%s * %s) %s) * %s FROM %s', tuples, v_index_header, v_varlen_query, v_index_multiplier, v_compressed_chunk) INTO v_index_size;
    index_size := index_size + v_index_size;
  END LOOP;

  total_size := relation_size + index_size;
END
$$ LANGUAGE plpgsql SET search_path TO pg_catalog, pg_temp;

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION _timescaledb_functions.hist_sfunc (state INTERNAL, val DOUBLE PRECISION, MIN DOUBLE PRECISION, MAX DOUBLE PRECISION, nbuckets INTEGER)
RETURNS INTERNAL
AS '$libdir/timescaledb-2.27.0-dev', 'ts_hist_sfunc'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.hist_combinefunc(state1 INTERNAL, state2 INTERNAL)
RETURNS INTERNAL
AS '$libdir/timescaledb-2.27.0-dev', 'ts_hist_combinefunc'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.hist_serializefunc(INTERNAL)
RETURNS bytea
AS '$libdir/timescaledb-2.27.0-dev', 'ts_hist_serializefunc'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.hist_deserializefunc(bytea, INTERNAL)
RETURNS INTERNAL
AS '$libdir/timescaledb-2.27.0-dev', 'ts_hist_deserializefunc'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.hist_finalfunc(state INTERNAL, val DOUBLE PRECISION, MIN DOUBLE PRECISION, MAX DOUBLE PRECISION, nbuckets INTEGER)
RETURNS INTEGER[]
AS '$libdir/timescaledb-2.27.0-dev', 'ts_hist_finalfunc'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- We started using CREATE OR REPLACE AGGREGATE for aggregate creation once the syntax was fully supported
-- as it is easier to support idempotent changes this way. This will allow for changes to functions supporting
-- the aggregate, and, for instance, the definition and inclusion of inverse functions for window function
-- support. However, it should still be noted that changes to the data structures used for the internal
-- state of the aggregate must be backwards compatible and the old format must be accepted by any new functions
-- in order for them to continue working with Continuous Aggregates, where old states may have been materialized.

-- This aggregate partitions the dataset into a specified number of buckets (nbuckets) ranging
-- from the inputted min to max values.
CREATE OR REPLACE AGGREGATE @extschema@.histogram (DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER) (
    SFUNC = _timescaledb_functions.hist_sfunc,
    STYPE = INTERNAL,
    COMBINEFUNC = _timescaledb_functions.hist_combinefunc,
    SERIALFUNC = _timescaledb_functions.hist_serializefunc,
    DESERIALFUNC = _timescaledb_functions.hist_deserializefunc,
    PARALLEL = SAFE,
    FINALFUNC = _timescaledb_functions.hist_finalfunc,
    FINALFUNC_EXTRA
);
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION _timescaledb_functions.restart_background_workers()
RETURNS BOOL
AS '$libdir/timescaledb', 'ts_bgw_db_workers_restart'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.stop_background_workers()
RETURNS BOOL
AS '$libdir/timescaledb', 'ts_bgw_db_workers_stop'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.start_background_workers()
RETURNS BOOL
AS '$libdir/timescaledb', 'ts_bgw_db_workers_start'
LANGUAGE C VOLATILE;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION _timescaledb_functions.generate_uuid() RETURNS UUID
AS '$libdir/timescaledb-2.27.0-dev', 'ts_uuid_generate' LANGUAGE C VOLATILE STRICT;

-- Trigger to change INSERT into UPDATE if key already exists.
--
-- During extension installation we create 3 entries in the metadata table which are
-- included in dumps. To allow loading logical dumps we need this trigger to turn INSERTs
-- into UPDATEs if the key already exists.
CREATE OR REPLACE FUNCTION _timescaledb_functions.metadata_insert_trigger() RETURNS TRIGGER LANGUAGE PLPGSQL
AS $$
BEGIN
  IF EXISTS (SELECT FROM _timescaledb_catalog.metadata WHERE key = NEW.key) THEN
    UPDATE _timescaledb_catalog.metadata SET value = NEW.value WHERE key = NEW.key;
    RETURN NULL;
  END IF;
  RETURN NEW;
END
$$ SET search_path TO pg_catalog, pg_temp;

CREATE OR REPLACE TRIGGER metadata_insert_trigger BEFORE INSERT ON _timescaledb_catalog.metadata FOR EACH ROW EXECUTE PROCEDURE _timescaledb_functions.metadata_insert_trigger();

-- Insert uuid and install_timestamp on database creation since the trigger
-- will turn these into UPDATEs on conflicts we can't use ON CONFLICT DO NOTHING.
DO $$
BEGIN
  IF (NOT EXISTS (SELECT FROM _timescaledb_catalog.metadata WHERE key = 'uuid')) THEN
    INSERT INTO _timescaledb_catalog.metadata SELECT 'uuid', _timescaledb_functions.generate_uuid(), TRUE;
  END IF;
  IF (NOT EXISTS (SELECT FROM _timescaledb_catalog.metadata WHERE key = 'install_timestamp')) THEN
    INSERT INTO _timescaledb_catalog.metadata SELECT 'install_timestamp', now(), TRUE;
  END IF;
END
$$;

-- Install catalog version on database installation and upgrade.
-- This allows us to detect catalog mismatches in dump/restore cycle.
INSERT INTO _timescaledb_catalog.metadata (key, value, include_in_telemetry) SELECT 'timescaledb_version', '2.27.0-dev', FALSE;

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION @extschema@.generate_uuidv7() RETURNS UUID
AS '$libdir/timescaledb-2.27.0-dev', 'ts_uuid_generate_v7' LANGUAGE C VOLATILE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.to_uuidv7(
  ts TIMESTAMPTZ
) RETURNS UUID
AS '$libdir/timescaledb-2.27.0-dev', 'ts_uuid_v7_from_timestamptz' LANGUAGE C VOLATILE STRICT PARALLEL SAFE;

--
-- Produce a boundary UUIDv7 from a timestamp, with all otherwise
-- random bits in the resulting UUID set to zero. Useful for
-- time-range queries directly on a UUID column.
--
CREATE OR REPLACE FUNCTION @extschema@.to_uuidv7_boundary(
  ts TIMESTAMPTZ
) RETURNS UUID
AS '$libdir/timescaledb-2.27.0-dev', 'ts_uuid_v7_from_timestamptz_boundary' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

--
-- Get the v7 UUID timestamp with millisecond precision.
--
CREATE OR REPLACE FUNCTION @extschema@.uuid_timestamp(
  uuid UUID
) RETURNS TIMESTAMPTZ
AS '$libdir/timescaledb-2.27.0-dev', 'ts_timestamptz_from_uuid_v7' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

--
-- Get the v7 UUID timestamp with microsecond precision using the
-- (optional) rand_a bits.
--
CREATE OR REPLACE FUNCTION @extschema@.uuid_timestamp_micros(
  uuid UUID
) RETURNS TIMESTAMPTZ
AS '$libdir/timescaledb-2.27.0-dev', 'ts_timestamptz_from_uuid_v7_with_microseconds' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.uuid_version(
  uuid UUID
) RETURNS INTEGER
AS '$libdir/timescaledb-2.27.0-dev', 'ts_uuid_version' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- Convenience view to list all hypertables
CREATE OR REPLACE VIEW timescaledb_information.hypertables AS
WITH
  hypertable_info AS (
    SELECT hypertable_id, schema_name, table_name,
           num_dimensions, compression_state, column_name,
           column_type, interval_length,
           (compression_state = 1) AS compression_enabled,
           row_number() OVER (PARTITION BY hypertable_id ORDER BY di.id) AS dimension_num
      FROM _timescaledb_catalog.hypertable ht
      JOIN _timescaledb_catalog.dimension di ON ht.id = di.hypertable_id
  )
SELECT
  ht.schema_name AS hypertable_schema,
  ht.table_name AS hypertable_name,
  t.tableowner AS owner,
  ht.num_dimensions,
  (
    SELECT count(1)
    FROM _timescaledb_catalog.chunk ch
    WHERE ch.hypertable_id = ht.hypertable_id
      AND ch.osm_chunk IS FALSE
  ) AS num_chunks,
  ht.compression_enabled,
  srchtbs.tablespace_list AS tablespaces,
  ht.column_name AS primary_dimension,
  ht.column_type AS primary_dimension_type
FROM hypertable_info ht
JOIN pg_tables t ON ht.table_name = t.tablename AND ht.schema_name = t.schemaname
LEFT JOIN _timescaledb_catalog.continuous_agg ca ON ca.mat_hypertable_id = ht.hypertable_id
LEFT JOIN (
    SELECT hypertable_id,
      array_agg(tablespace_name ORDER BY id) AS tablespace_list
    FROM _timescaledb_catalog.tablespace
    GROUP BY hypertable_id) srchtbs ON ht.hypertable_id = srchtbs.hypertable_id
WHERE ht.compression_state != 2 --> no internal compression tables
  AND ca.mat_hypertable_id IS NULL
  AND ht.interval_length IS NOT NULL
  AND ht.dimension_num = 1;

-- Get status of existing jobs.
--
-- Note that we will always list all jobs that are available in the
-- database, but some fields might be null if, for example, the job
-- has not yet executed, or there is no hypertable associated with the
-- job.
CREATE OR REPLACE VIEW timescaledb_information.job_stats AS
SELECT ht.schema_name AS hypertable_schema,
  ht.table_name AS hypertable_name,
  j.id AS job_id,
  js.last_start AS last_run_started_at,
  js.last_successful_finish AS last_successful_finish,
  CASE WHEN js.last_finish < '4714-11-24 00:00:00+00 BC' THEN
    NULL
  WHEN js.last_finish IS NOT NULL THEN
    CASE WHEN js.last_run_success = 't' THEN
      'Success'
    WHEN js.last_run_success = 'f' THEN
      'Failed'
    END
  END AS last_run_status,
  CASE WHEN pgs.state = 'active' THEN
    'Running'
  WHEN j.scheduled = FALSE THEN
    'Paused'
  ELSE
    'Scheduled'
  END AS job_status,
  CASE WHEN js.last_finish > js.last_start THEN
  (js.last_finish - js.last_start)
  END AS last_run_duration,
  CASE WHEN j.scheduled THEN
    js.next_start
  END AS next_start,
  js.total_runs,
  js.total_successes,
  js.total_failures
FROM _timescaledb_catalog.bgw_job j
  LEFT JOIN _timescaledb_internal.bgw_job_stat js ON j.id = js.job_id
  LEFT JOIN _timescaledb_catalog.hypertable ht ON j.hypertable_id = ht.id
  LEFT JOIN pg_stat_activity pgs ON pgs.datname = current_database()
    AND pgs.application_name = j.application_name
  ORDER BY ht.schema_name,
    ht.table_name;

-- view for background worker jobs
CREATE OR REPLACE VIEW timescaledb_information.jobs AS
SELECT j.id AS job_id,
  j.application_name,
  j.schedule_interval,
  j.max_runtime,
  j.max_retries,
  j.retry_period,
  j.proc_schema,
  j.proc_name,
  j.owner,
  j.scheduled,
  j.fixed_schedule,
  j.config,
  js.next_start,
  j.initial_start,
  COALESCE(ca.user_view_schema, ht.schema_name) AS hypertable_schema,
  COALESCE(ca.user_view_name, ht.table_name) AS hypertable_name,
  j.check_schema,
  j.check_name
FROM _timescaledb_catalog.bgw_job j
  LEFT JOIN _timescaledb_catalog.hypertable ht ON ht.id = j.hypertable_id
  LEFT JOIN _timescaledb_internal.bgw_job_stat js ON js.job_id = j.id
  LEFT JOIN _timescaledb_catalog.continuous_agg ca ON ca.mat_hypertable_id = j.hypertable_id;

-- views for continuous aggregate queries ---
CREATE OR REPLACE VIEW timescaledb_information.continuous_aggregates AS
SELECT ht.schema_name AS hypertable_schema,
  ht.table_name AS hypertable_name,
  cagg.user_view_schema AS view_schema,
  cagg.user_view_name AS view_name,
  viewinfo.viewowner AS view_owner,
  cagg.materialized_only,
  CASE WHEN mat_ht.compressed_hypertable_id IS NOT NULL
       THEN TRUE
       ELSE FALSE
  END AS compression_enabled,
  mat_ht.schema_name AS materialization_hypertable_schema,
  mat_ht.table_name AS materialization_hypertable_name,
  directview.viewdefinition AS view_definition
FROM _timescaledb_catalog.continuous_agg cagg,
  _timescaledb_catalog.hypertable ht,
  LATERAL (
    SELECT C.oid,
      pg_get_userbyid(C.relowner) AS viewowner
    FROM pg_class C
      LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
    WHERE C.relkind = 'v'
      AND C.relname = cagg.user_view_name
      AND N.nspname = cagg.user_view_schema) viewinfo,
  LATERAL (
    SELECT pg_get_viewdef(C.oid) AS viewdefinition
    FROM pg_class C
    LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
  WHERE C.relkind = 'v'
    AND C.relname = cagg.direct_view_name
    AND N.nspname = cagg.direct_view_schema) directview,
  LATERAL (
    SELECT schema_name, table_name, compressed_hypertable_id
    FROM _timescaledb_catalog.hypertable
    WHERE cagg.mat_hypertable_id = id) mat_ht
WHERE cagg.raw_hypertable_id = ht.id;

-- chunks metadata view, shows information about the primary dimension column
-- query plans with CTEs are not always optimized by PG. So use in-line
-- tables.

CREATE OR REPLACE VIEW timescaledb_information.chunks AS
SELECT hypertable_schema,
  hypertable_name,
  schema_name AS chunk_schema,
  chunk_name,
  primary_dimension,
  primary_dimension_type,
  range_start,
  range_end,
  integer_range_start AS range_start_integer,
  integer_range_end AS range_end_integer,
  is_compressed,
  chunk_table_space AS chunk_tablespace,
  creation_time AS chunk_creation_time
FROM (
  SELECT ht.schema_name AS hypertable_schema,
    ht.table_name AS hypertable_name,
    srcch.schema_name AS schema_name,
    srcch.table_name AS chunk_name,
    dim.column_name AS primary_dimension,
    dim.column_type AS primary_dimension_type,
    row_number() OVER (PARTITION BY chcons.chunk_id ORDER BY dim.id) AS chunk_dimension_num,
    CASE WHEN dim.column_type = ANY(ARRAY['timestamp','timestamptz','date', 'uuid']::regtype[]) THEN
      _timescaledb_functions.to_timestamp(dimsl.range_start)
    ELSE
      NULL
    END AS range_start,
    CASE WHEN dim.column_type = ANY(ARRAY['timestamp','timestamptz','date', 'uuid']::regtype[]) THEN
      _timescaledb_functions.to_timestamp(dimsl.range_end)
    ELSE
      NULL
    END AS range_end,
    CASE WHEN dim.column_type = ANY(ARRAY['timestamp','timestamptz','date', 'uuid']::regtype[]) THEN
      NULL
    ELSE
      dimsl.range_start
    END AS integer_range_start,
    CASE WHEN dim.column_type = ANY(ARRAY['timestamp','timestamptz','date', 'uuid']::regtype[]) THEN
      NULL
    ELSE
      dimsl.range_end
    END AS integer_range_end,
    CASE WHEN (srcch.status & 1 = 1) THEN
        TRUE
    ELSE FALSE
    END AS is_compressed,
    pgtab.spcname AS chunk_table_space,
	srcch.creation_time AS creation_time
  FROM _timescaledb_catalog.chunk srcch
    INNER JOIN _timescaledb_catalog.hypertable ht ON ht.id = srcch.hypertable_id
    INNER JOIN _timescaledb_catalog.chunk_constraint chcons ON srcch.id = chcons.chunk_id
    INNER JOIN _timescaledb_catalog.dimension dim ON srcch.hypertable_id = dim.hypertable_id
    INNER JOIN _timescaledb_catalog.dimension_slice dimsl ON dim.id = dimsl.dimension_id
      AND chcons.dimension_slice_id = dimsl.id
    INNER JOIN (
      SELECT relname,
        reltablespace,
        nspname AS schema_name
      FROM pg_class,
        pg_namespace
      WHERE pg_class.relnamespace = pg_namespace.oid) cl ON srcch.table_name = cl.relname
      AND srcch.schema_name = cl.schema_name
    LEFT OUTER JOIN pg_tablespace pgtab ON pgtab.oid = reltablespace
  WHERE srcch.osm_chunk IS FALSE
    AND ht.compression_state != 2 ) finalq
WHERE chunk_dimension_num = 1;

-- hypertable's dimension information
-- CTEs aren't used in the query as PG does not always optimize them
-- as expected.

CREATE OR REPLACE VIEW timescaledb_information.dimensions AS
SELECT ht.schema_name AS hypertable_schema,
  ht.table_name AS hypertable_name,
  rank() OVER (PARTITION BY hypertable_id ORDER BY dim.id) AS dimension_number,
  dim.column_name,
  dim.column_type,
  CASE WHEN dim.interval_length IS NULL THEN
    'Space'
  ELSE
    'Time'
  END AS dimension_type,
  CASE WHEN dim.interval_length IS NOT NULL THEN
    CASE WHEN dim.column_type = ANY(ARRAY['timestamp','timestamptz','date', 'uuid']::regtype[]) THEN
      _timescaledb_functions.to_interval(dim.interval_length)
    ELSE
      NULL
    END
  END AS time_interval,
  CASE WHEN dim.interval_length IS NOT NULL THEN
    CASE WHEN dim.column_type = ANY(ARRAY['timestamp','timestamptz','date', 'uuid']::regtype[]) THEN
      NULL
    ELSE
      dim.interval_length
    END
  END AS integer_interval,
  dim.integer_now_func,
  dim.num_slices AS num_partitions
FROM _timescaledb_catalog.hypertable ht,
  _timescaledb_catalog.dimension dim
WHERE dim.hypertable_id = ht.id;

---compression parameters information ---
CREATE OR REPLACE VIEW timescaledb_information.compression_settings AS
SELECT
	schema_name AS hypertable_schema,
  table_name AS hypertable_name,
  (unnest(cs.segmentby))::name COLLATE "C" AS attname,
  generate_series(1,array_length(cs.segmentby,1))::smallint AS segmentby_column_index,
  NULL::smallint AS orderby_column_index,
  NULL::bool AS orderby_asc,
  NULL::bool AS orderby_nullsfirst
FROM _timescaledb_catalog.hypertable ht
INNER JOIN _timescaledb_catalog.compression_settings cs ON cs.relid = format('%I.%I',ht.schema_name,ht.table_name)::regclass AND cs.segmentby IS NOT NULL
WHERE compressed_hypertable_id IS NOT NULL
UNION ALL
SELECT
	schema_name AS hypertable_schema,
  table_name AS hypertable_name,
  (unnest(cs.orderby))::name COLLATE "C" AS attname,
  NULL::smallint AS segmentby_column_index,
  generate_series(1,array_length(cs.orderby,1))::smallint AS orderby_column_index,
  unnest(array_replace(array_replace(array_replace(cs.orderby_desc,false,NULL),true,false),NULL,true)) AS orderby_asc,
  unnest(cs.orderby_nullsfirst) AS orderby_nullsfirst
FROM _timescaledb_catalog.hypertable ht
INNER JOIN _timescaledb_catalog.compression_settings cs ON cs.relid = format('%I.%I',ht.schema_name,ht.table_name)::regclass AND cs.orderby IS NOT NULL
WHERE compressed_hypertable_id IS NOT NULL
ORDER BY hypertable_name,
  segmentby_column_index,
  orderby_column_index;

-- Job errors view that adds a security barrier on the bgw_job_stat_history
-- table in _timescaledb_internal. The view only allows users to view
-- log entries belonging to jobs that are owned by any of the users
-- role. A special case is added so that the superuser or the database
-- owner can see all job log entries, even those that do not have an
-- associated job.
--
-- Note that we have to use a sub-select here since pg_database_owner
-- does not exist before PostgreSQL 14.
CREATE OR REPLACE VIEW timescaledb_information.job_errors
WITH (security_barrier = true) AS
SELECT
    h.job_id,
    h.data->'job'->>'proc_schema' as proc_schema,
    h.data->'job'->>'proc_name' as proc_name,
    h.pid,
    h.execution_start AS start_time,
    h.execution_finish AS finish_time,
    h.data->'error_data'->>'sqlerrcode' AS sqlerrcode,
    CASE
      WHEN h.succeeded IS NULL AND h.execution_finish IS NULL AND h.pid IS NULL THEN
        'job crash detected, see server logs'
      WHEN h.data->'error_data'->>'message' IS NOT NULL THEN
        CASE WHEN h.data->'error_data'->>'detail' IS NOT NULL THEN
          CASE WHEN h.data->'error_data'->>'hint' IS NOT NULL THEN concat(h.data->'error_data'->>'message', '. ', h.data->'error_data'->>'detail', '. ', h.data->'error_data'->>'hint')
          ELSE concat(h.data->'error_data'->>'message', ' ', h.data->'error_data'->>'detail')
          END
        ELSE
          CASE WHEN h.data->'error_data'->>'hint' IS NOT NULL THEN concat(h.data->'error_data'->>'message', '. ', h.data->'error_data'->>'hint')
          ELSE h.data->'error_data'->>'message'
          END
        END
    END AS err_message
FROM
    _timescaledb_internal.bgw_job_stat_history h
LEFT JOIN
    _timescaledb_catalog.bgw_job j ON (j.id = h.job_id)
WHERE
    h.succeeded IS FALSE
    OR h.succeeded IS NULL
    AND (pg_catalog.pg_has_role(current_user,
			   (SELECT pg_catalog.pg_get_userbyid(datdba)
			      FROM pg_catalog.pg_database
			     WHERE datname = current_database()),
			   'MEMBER') IS TRUE
    OR pg_catalog.pg_has_role(current_user, owner, 'MEMBER') IS TRUE);

CREATE OR REPLACE VIEW timescaledb_information.job_history
WITH (security_barrier = true) AS
SELECT
    h.id,
    h.job_id,
    h.succeeded,
    coalesce(h.data->'job'->>'proc_schema', j.proc_schema) as proc_schema,
    coalesce(h.data->'job'->>'proc_name', j.proc_name) as proc_name,
    h.pid,
    h.execution_start AS start_time,
    h.execution_finish AS finish_time,
    h.data->'job'->'config' AS config,
    h.data->'error_data'->>'sqlerrcode' AS sqlerrcode,
    CASE
      WHEN h.succeeded IS NULL AND h.execution_finish IS NULL AND h.pid IS NULL THEN
        'job crash detected, see server logs'
      WHEN h.succeeded IS FALSE AND h.data->'error_data'->>'message' IS NOT NULL THEN
        CASE WHEN h.data->'error_data'->>'detail' IS NOT NULL THEN
          CASE WHEN h.data->'error_data'->>'hint' IS NOT NULL THEN concat(h.data->'error_data'->>'message', '. ', h.data->'error_data'->>'detail', '. ', h.data->'error_data'->>'hint')
          ELSE concat(h.data->'error_data'->>'message', ' ', h.data->'error_data'->>'detail')
          END
        ELSE
          CASE WHEN h.data->'error_data'->>'hint' IS NOT NULL THEN concat(h.data->'error_data'->>'message', '. ', h.data->'error_data'->>'hint')
          ELSE h.data->'error_data'->>'message'
          END
        END
    END AS err_message
FROM
    _timescaledb_internal.bgw_job_stat_history h
LEFT JOIN
    _timescaledb_catalog.bgw_job j ON (j.id = h.job_id)
WHERE (pg_catalog.pg_has_role(current_user,
			   (SELECT pg_catalog.pg_get_userbyid(datdba)
			      FROM pg_catalog.pg_database
			     WHERE datname = current_database()),
			   'MEMBER') IS TRUE
    OR pg_catalog.pg_has_role(current_user, owner, 'MEMBER') IS TRUE);

CREATE OR REPLACE VIEW timescaledb_information.hypertable_compression_settings AS
	SELECT
		format('%I.%I',ht.schema_name,ht.table_name)::regclass AS hypertable,
		array_to_string(segmentby,',') AS segmentby,
		un.orderby,
    d.compress_interval_length,
    s.index AS index
  FROM _timescaledb_catalog.hypertable ht
  JOIN LATERAL (
    SELECT
      CASE WHEN d.column_type = ANY(ARRAY['timestamp','timestamptz','date']::regtype[]) THEN
        _timescaledb_functions.to_interval(d.compress_interval_length)::text
      ELSE
        d.compress_interval_length::text
      END AS compress_interval_length
    FROM _timescaledb_catalog.dimension d WHERE d.hypertable_id = ht.id ORDER BY id LIMIT 1
  ) d ON true
  LEFT JOIN _timescaledb_catalog.compression_settings s ON format('%I.%I',ht.schema_name,ht.table_name)::regclass = s.relid
	LEFT JOIN LATERAL (
		SELECT
			string_agg(
				format('%I%s%s',orderby,
					CASE WHEN "desc" THEN ' DESC' ELSE '' END,
					CASE WHEN nullsfirst AND NOT "desc" THEN ' NULLS FIRST' WHEN NOT nullsfirst AND "desc" THEN ' NULLS LAST' ELSE '' END
				)
			,',') AS orderby
		FROM unnest(s.orderby, s.orderby_desc, s.orderby_nullsfirst) un(orderby, "desc", nullsfirst)
	) un ON true;

CREATE OR REPLACE VIEW timescaledb_information.chunk_compression_settings AS
	SELECT
		format('%I.%I',ht.schema_name,ht.table_name)::regclass AS hypertable,
		format('%I.%I',ch.schema_name,ch.table_name)::regclass AS chunk,
		array_to_string(segmentby,',') AS segmentby,
		un.orderby,
    s.index AS index
	FROM _timescaledb_catalog.hypertable ht
    INNER JOIN _timescaledb_catalog.chunk ch ON ch.hypertable_id = ht.id
    INNER JOIN _timescaledb_catalog.compression_settings s ON (format('%I.%I',ch.schema_name,ch.table_name)::regclass = s.relid)
	LEFT JOIN LATERAL (
		SELECT
			string_agg(
				format('%I%s%s',orderby,
					CASE WHEN "desc" THEN ' DESC' ELSE '' END,
					CASE WHEN nullsfirst AND NOT "desc" THEN ' NULLS FIRST' WHEN NOT nullsfirst AND "desc" THEN ' NULLS LAST' ELSE '' END
				)
			,',') AS orderby
		FROM unnest(s.orderby, s.orderby_desc, s.orderby_nullsfirst) un(orderby, "desc", nullsfirst)
	) un ON true;


CREATE OR REPLACE VIEW timescaledb_information.hypertable_columnstore_settings
AS SELECT * FROM timescaledb_information.hypertable_compression_settings;

CREATE OR REPLACE VIEW timescaledb_information.chunk_columnstore_settings AS
SELECT * FROM timescaledb_information.chunk_compression_settings;

--temporary alias for bgw_job
CREATE OR REPLACE VIEW _timescaledb_config.bgw_job AS
SELECT * from _timescaledb_catalog.bgw_job;

GRANT SELECT ON ALL TABLES IN SCHEMA _timescaledb_config TO PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA timescaledb_information TO PUBLIC;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE VIEW timescaledb_experimental.policies AS
SELECT ca.user_view_name AS relation_name,
  ca.user_view_schema AS relation_schema,
  j.schedule_interval,
  j.proc_schema,
  j.proc_name,
  j.config,
  ht.schema_name AS hypertable_schema,
  ht.table_name AS hypertable_name
FROM _timescaledb_catalog.bgw_job j
  JOIN _timescaledb_catalog.continuous_agg ca ON ca.mat_hypertable_id = j.hypertable_id
  JOIN _timescaledb_catalog.hypertable ht ON ht.id = ca.mat_hypertable_id;

GRANT SELECT ON ALL TABLES IN SCHEMA timescaledb_experimental TO PUBLIC;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION @extschema@.time_bucket_gapfill(bucket_width SMALLINT, ts SMALLINT, start SMALLINT=NULL, finish SMALLINT=NULL) RETURNS SMALLINT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_int16_bucket' LANGUAGE C VOLATILE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.time_bucket_gapfill(bucket_width INT, ts INT, start INT=NULL, finish INT=NULL) RETURNS INT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_int32_bucket' LANGUAGE C VOLATILE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.time_bucket_gapfill(bucket_width BIGINT, ts BIGINT, start BIGINT=NULL, finish BIGINT=NULL) RETURNS BIGINT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_int64_bucket' LANGUAGE C VOLATILE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.time_bucket_gapfill(bucket_width INTERVAL, ts DATE, start DATE=NULL, finish DATE=NULL) RETURNS DATE
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_date_bucket' LANGUAGE C VOLATILE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.time_bucket_gapfill(bucket_width INTERVAL, ts TIMESTAMP, start TIMESTAMP=NULL, finish TIMESTAMP=NULL) RETURNS TIMESTAMP
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_timestamp_bucket' LANGUAGE C VOLATILE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.time_bucket_gapfill(bucket_width INTERVAL, ts TIMESTAMPTZ, start TIMESTAMPTZ=NULL, finish TIMESTAMPTZ=NULL) RETURNS TIMESTAMPTZ
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_timestamptz_bucket' LANGUAGE C VOLATILE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.time_bucket_gapfill(bucket_width INTERVAL, ts TIMESTAMPTZ, timezone TEXT, start TIMESTAMPTZ=NULL, finish TIMESTAMPTZ=NULL) RETURNS TIMESTAMPTZ
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_timestamptz_timezone_bucket' LANGUAGE C VOLATILE PARALLEL SAFE;

-- locf function
CREATE OR REPLACE FUNCTION @extschema@.locf(value ANYELEMENT, prev ANYELEMENT=NULL, treat_null_as_missing BOOL=false) RETURNS ANYELEMENT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_marker' LANGUAGE C VOLATILE PARALLEL SAFE;

-- interpolate functions
CREATE OR REPLACE FUNCTION @extschema@.interpolate(value SMALLINT,prev RECORD=NULL,next RECORD=NULL) RETURNS SMALLINT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_marker' LANGUAGE C VOLATILE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.interpolate(value INT,prev RECORD=NULL,next RECORD=NULL) RETURNS INT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_marker' LANGUAGE C VOLATILE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.interpolate(value BIGINT,prev RECORD=NULL,next RECORD=NULL) RETURNS BIGINT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_marker' LANGUAGE C VOLATILE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.interpolate(value REAL,prev RECORD=NULL,next RECORD=NULL) RETURNS REAL
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_marker' LANGUAGE C VOLATILE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.interpolate(value FLOAT,prev RECORD=NULL,next RECORD=NULL) RETURNS FLOAT
	AS '$libdir/timescaledb-2.27.0-dev', 'ts_gapfill_marker' LANGUAGE C VOLATILE PARALLEL SAFE;

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_data_to_array(_timescaledb_internal.compressed_data, ANYELEMENT)
   RETURNS ANYARRAY
   AS '$libdir/timescaledb-2.27.0-dev', 'ts_compressed_data_to_array'
   LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_data_column_size(_timescaledb_internal.compressed_data, ANYELEMENT)
   RETURNS INTEGER
   AS '$libdir/timescaledb-2.27.0-dev', 'ts_compressed_data_column_size'
   LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- chunk - the OID of the chunk to be CLUSTERed
-- index - the OID of the index to be CLUSTERed on, or NULL to use the index
--         last used
CREATE OR REPLACE FUNCTION @extschema@.reorder_chunk(
    chunk REGCLASS,
    index REGCLASS=NULL,
    verbose BOOLEAN=FALSE
) RETURNS VOID AS '$libdir/timescaledb-2.27.0-dev', 'ts_reorder_chunk' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.move_chunk(
    chunk REGCLASS,
    destination_tablespace Name,
    index_destination_tablespace Name=NULL,
    reorder_index REGCLASS=NULL,
    verbose BOOLEAN=FALSE
) RETURNS VOID AS '$libdir/timescaledb-2.27.0-dev', 'ts_move_chunk' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.create_compressed_chunk(
    chunk REGCLASS,
    chunk_table REGCLASS,
    uncompressed_heap_size BIGINT,
    uncompressed_toast_size BIGINT,
    uncompressed_index_size BIGINT,
    compressed_heap_size BIGINT,
    compressed_toast_size BIGINT,
    compressed_index_size BIGINT,
    numrows_pre_compression BIGINT,
    numrows_post_compression BIGINT
) RETURNS REGCLASS AS '$libdir/timescaledb-2.27.0-dev', 'ts_create_compressed_chunk' LANGUAGE C STRICT VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.compress_chunk(
    uncompressed_chunk REGCLASS,
    if_not_compressed BOOLEAN = true,
    recompress BOOLEAN = false
) RETURNS REGCLASS AS '$libdir/timescaledb-2.27.0-dev', 'ts_compress_chunk' LANGUAGE C VOLATILE;

-- Alias for compress_chunk above.
CREATE OR REPLACE PROCEDURE @extschema@.convert_to_columnstore(
    chunk REGCLASS,
    if_not_columnstore BOOLEAN = true,
    recompress BOOLEAN = false
) AS '$libdir/timescaledb-2.27.0-dev', 'ts_compress_chunk' LANGUAGE C;

CREATE OR REPLACE FUNCTION @extschema@.decompress_chunk(
    uncompressed_chunk REGCLASS,
    if_compressed BOOLEAN = true
) RETURNS REGCLASS AS '$libdir/timescaledb-2.27.0-dev', 'ts_decompress_chunk' LANGUAGE C STRICT VOLATILE;

CREATE OR REPLACE PROCEDURE @extschema@.convert_to_rowstore(
    chunk REGCLASS,
    if_columnstore BOOLEAN = true
) AS '$libdir/timescaledb-2.27.0-dev', 'ts_decompress_chunk' LANGUAGE C;

CREATE OR REPLACE PROCEDURE _timescaledb_functions.rebuild_columnstore(
    chunk REGCLASS
) AS '$libdir/timescaledb-2.27.0-dev', 'ts_rebuild_columnstore' LANGUAGE C;

CREATE OR REPLACE PROCEDURE _timescaledb_functions.chunk_rewrite_cleanup()
LANGUAGE C AS '$libdir/timescaledb-2.27.0-dev', 'ts_chunk_rewrite_cleanup';

CREATE OR REPLACE PROCEDURE @extschema@.merge_chunks(
   chunk1 REGCLASS, chunk2 REGCLASS, concurrently BOOLEAN = false
) LANGUAGE C AS '$libdir/timescaledb-2.27.0-dev', 'ts_merge_two_chunks';

CREATE OR REPLACE PROCEDURE @extschema@.merge_chunks(
    chunks REGCLASS[]
) LANGUAGE C AS '$libdir/timescaledb-2.27.0-dev', 'ts_merge_chunks';

CREATE OR REPLACE PROCEDURE @extschema@.merge_chunks_concurrently(
    chunks REGCLASS[]
) LANGUAGE C AS '$libdir/timescaledb-2.27.0-dev', 'ts_merge_chunks_concurrently';

CREATE OR REPLACE PROCEDURE @extschema@.split_chunk(
    chunk REGCLASS,
    split_at "any" = NULL
) LANGUAGE C AS '$libdir/timescaledb-2.27.0-dev', 'ts_split_chunk';

CREATE OR REPLACE FUNCTION _timescaledb_functions.recompress_chunk_segmentwise(
    uncompressed_chunk REGCLASS,
    if_compressed BOOLEAN = true
) RETURNS REGCLASS AS '$libdir/timescaledb-2.27.0-dev', 'ts_recompress_chunk_segmentwise' LANGUAGE C STRICT VOLATILE;

-- find the index on the compressed chunk that can be used to recompress efficiently
-- this index must contain all the segmentby columns and the meta_sequence_number column last
CREATE OR REPLACE FUNCTION _timescaledb_functions.get_compressed_chunk_index_for_recompression(
    uncompressed_chunk REGCLASS
) RETURNS REGCLASS AS '$libdir/timescaledb-2.27.0-dev', 'ts_get_compressed_chunk_index_for_recompression' LANGUAGE C STRICT VOLATILE;
-- Recompress a chunk
--
-- Will give an error if the chunk was not already compressed. In this
-- case, the user should use compress_chunk instead. Note that this
-- function cannot be executed in an explicit transaction since it
-- contains transaction control commands.
--
-- Parameters:
--   chunk: Chunk to recompress.
--   if_not_compressed: Print notice instead of error if chunk is already compressed.

CREATE OR REPLACE PROCEDURE @extschema@.recompress_chunk(chunk REGCLASS, if_not_compressed BOOLEAN = true) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'procedure @extschema@.recompress_chunk(regclass,boolean) is deprecated and the functionality is now included in @extschema@.compress_chunk. this compatibility function will be removed in a future version.';
  END IF;
  PERFORM @extschema@.compress_chunk(chunk, if_not_compressed);
END$$ SET search_path TO pg_catalog,pg_temp;

-- Remove chunk metadata when marked as dropped
CREATE OR REPLACE FUNCTION _timescaledb_functions.remove_dropped_chunk_metadata(_hypertable_id INTEGER)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  _chunk_id INTEGER;
  _removed INTEGER := 0;
BEGIN
  FOR _chunk_id IN
    SELECT id FROM _timescaledb_catalog.chunk
    WHERE hypertable_id = _hypertable_id
    AND NOT EXISTS (
        SELECT FROM information_schema.tables
        WHERE tables.table_schema = chunk.schema_name
        AND tables.table_name = chunk.table_name
    )
  LOOP
    _removed := _removed + 1;
    RAISE INFO 'Removing metadata of chunk % from hypertable %', _chunk_id, _hypertable_id;

    WITH _dimension_slice_remove AS (
        DELETE FROM _timescaledb_catalog.dimension_slice
        USING _timescaledb_catalog.chunk_constraint
        WHERE dimension_slice.id = chunk_constraint.dimension_slice_id
        AND chunk_constraint.chunk_id = _chunk_id
        AND NOT EXISTS (
            SELECT FROM _timescaledb_catalog.chunk_constraint cc
            WHERE cc.chunk_id <> _chunk_id
            AND cc.dimension_slice_id = dimension_slice.id
        )
        RETURNING _timescaledb_catalog.dimension_slice.id
    )
    DELETE FROM _timescaledb_catalog.chunk_constraint
    USING _dimension_slice_remove
    WHERE chunk_constraint.dimension_slice_id = _dimension_slice_remove.id;

    DELETE FROM _timescaledb_catalog.chunk_constraint
    WHERE chunk_constraint.chunk_id = _chunk_id;

    DELETE FROM _timescaledb_internal.bgw_policy_chunk_stats
    WHERE bgw_policy_chunk_stats.chunk_id = _chunk_id;

    DELETE FROM _timescaledb_catalog.compression_chunk_size
    WHERE compression_chunk_size.chunk_id = _chunk_id
    OR compression_chunk_size.compressed_chunk_id = _chunk_id;

    DELETE FROM _timescaledb_catalog.chunk
    WHERE chunk.id = _chunk_id
    OR chunk.compressed_chunk_id = _chunk_id;
  END LOOP;

  RETURN _removed;
END;
$$ SET search_path TO pg_catalog, pg_temp;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION @extschema@.timescaledb_pre_restore() RETURNS BOOL AS
$BODY$
DECLARE
    db text;
BEGIN
    SELECT current_database() INTO db;
    EXECUTE format($$ALTER DATABASE %I SET timescaledb.restoring ='on'$$, db);
    SET SESSION timescaledb.restoring = 'on';
    PERFORM _timescaledb_functions.stop_background_workers();
    RETURN true;
END
$BODY$
LANGUAGE PLPGSQL SET search_path TO pg_catalog, pg_temp;


CREATE OR REPLACE FUNCTION @extschema@.timescaledb_post_restore() RETURNS BOOL AS
$BODY$
DECLARE
    db text;
    catalog_version text;
BEGIN
    SELECT m.value INTO catalog_version FROM pg_extension x
    JOIN _timescaledb_catalog.metadata m ON m.key='timescaledb_version'
    WHERE x.extname='timescaledb' AND x.extversion <> m.value;

    -- check that a loaded dump is compatible with the currently running code
    IF FOUND THEN
        RAISE EXCEPTION 'catalog version mismatch, expected "%" seen "%"', '2.27.0-dev', catalog_version;
    END IF;

    SELECT current_database() INTO db;
    EXECUTE format($$ALTER DATABASE %I RESET timescaledb.restoring $$, db);
    -- we cannot use reset here because the reset_val might not be off
    SET timescaledb.restoring TO off;
    PERFORM _timescaledb_functions.restart_background_workers();

    RETURN true;
END
$BODY$
LANGUAGE PLPGSQL SET search_path TO pg_catalog, pg_temp;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION @extschema@.add_job(
  proc REGPROC,
  schedule_interval INTERVAL,
  config JSONB DEFAULT NULL,
  initial_start TIMESTAMPTZ DEFAULT NULL,
  scheduled BOOL DEFAULT true,
  check_config REGPROC DEFAULT NULL,
  fixed_schedule BOOL DEFAULT TRUE,
  timezone TEXT DEFAULT NULL,
  job_name TEXT DEFAULT NULL
) RETURNS INTEGER AS '$libdir/timescaledb-2.27.0-dev', 'ts_job_add' LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.delete_job(job_id INTEGER) RETURNS VOID AS '$libdir/timescaledb-2.27.0-dev', 'ts_job_delete' LANGUAGE C VOLATILE STRICT;
CREATE OR REPLACE PROCEDURE @extschema@.run_job(job_id INTEGER) AS '$libdir/timescaledb-2.27.0-dev', 'ts_job_run' LANGUAGE C;

-- Returns the updated job schedule values
CREATE OR REPLACE FUNCTION @extschema@.alter_job(
    job_id INTEGER,
    schedule_interval INTERVAL = NULL,
    max_runtime INTERVAL = NULL,
    max_retries INTEGER = NULL,
    retry_period INTERVAL = NULL,
    scheduled BOOL = NULL,
    config JSONB = NULL,
    next_start TIMESTAMPTZ = NULL,
    if_exists BOOL = FALSE,
    check_config REGPROC = NULL,
    fixed_schedule BOOL = NULL,
    initial_start TIMESTAMPTZ = NULL,
    timezone TEXT DEFAULT NULL,
    job_name TEXT DEFAULT NULL
)
RETURNS TABLE (job_id INTEGER, schedule_interval INTERVAL, max_runtime INTERVAL, max_retries INTEGER, retry_period INTERVAL, scheduled BOOL, config JSONB,
next_start TIMESTAMPTZ, check_config TEXT, fixed_schedule BOOL, initial_start TIMESTAMPTZ, timezone TEXT, application_name name)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_job_alter'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.alter_job_set_hypertable_id(
    job_id INTEGER,
    hypertable REGCLASS )
RETURNS INTEGER AS '$libdir/timescaledb-2.27.0-dev', 'ts_job_alter_set_hypertable_id'
LANGUAGE C VOLATILE;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- Add a retention policy to a hypertable or continuous aggregate.
-- The retention_window (typically an INTERVAL) determines the
-- window beyond which data is dropped at the time
-- of execution of the policy (e.g., '1 week'). Note that the retention
-- window will always align with chunk boundaries, thus the window
-- might be larger than the given one, but never smaller. In other
-- words, some data beyond the retention window
-- might be kept, but data within the window will never be deleted.
CREATE OR REPLACE FUNCTION @extschema@.add_retention_policy(
       relation REGCLASS,
       drop_after "any" = NULL,
       if_not_exists BOOL = false,
       schedule_interval INTERVAL = NULL,
       initial_start TIMESTAMPTZ = NULL,
       timezone TEXT = NULL,
       drop_created_before INTERVAL = NULL
)
RETURNS INTEGER AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_retention_add'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.remove_retention_policy(
    relation REGCLASS,
    if_exists BOOL = false
) RETURNS VOID
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_retention_remove'
LANGUAGE C VOLATILE STRICT;

/* reorder policy */
CREATE OR REPLACE FUNCTION @extschema@.add_reorder_policy(
    hypertable REGCLASS,
    index_name NAME,
    if_not_exists BOOL = false,
    initial_start timestamptz = NULL,
    timezone TEXT = NULL
) RETURNS INTEGER
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_reorder_add'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.remove_reorder_policy(hypertable REGCLASS, if_exists BOOL = false) RETURNS VOID
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_reorder_remove'
LANGUAGE C VOLATILE STRICT;

/* compression policy */
CREATE OR REPLACE FUNCTION @extschema@.add_compression_policy(
    hypertable REGCLASS,
    compress_after "any" = NULL,
    if_not_exists BOOL = false,
    schedule_interval INTERVAL = NULL,
    initial_start TIMESTAMPTZ = NULL,
    timezone TEXT = NULL,
    compress_created_before INTERVAL = NULL
)
RETURNS INTEGER
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_compression_add'
LANGUAGE C VOLATILE; -- not strict because we need to set different default values for schedule_interval

CREATE OR REPLACE PROCEDURE @extschema@.add_columnstore_policy(
    hypertable REGCLASS,
    after "any" = NULL,
    if_not_exists BOOL = false,
    schedule_interval INTERVAL = NULL,
    initial_start TIMESTAMPTZ = NULL,
    timezone TEXT = NULL,
    created_before INTERVAL = NULL
) LANGUAGE C AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_compression_add';

CREATE OR REPLACE FUNCTION @extschema@.remove_compression_policy(hypertable REGCLASS, if_exists BOOL = false) RETURNS BOOL
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_compression_remove'
LANGUAGE C VOLATILE STRICT;

CREATE OR REPLACE PROCEDURE @extschema@.remove_columnstore_policy(
       hypertable REGCLASS,
       if_exists BOOL = false
) LANGUAGE C AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_compression_remove';

/* continuous aggregates policy */
CREATE OR REPLACE FUNCTION @extschema@.add_continuous_aggregate_policy(
    continuous_aggregate REGCLASS,
    start_offset "any",
    end_offset "any",
    schedule_interval INTERVAL,
    if_not_exists BOOL = false,
    initial_start TIMESTAMPTZ = NULL,
    timezone TEXT = NULL,
    include_tiered_data BOOL = NULL,
    buckets_per_batch INTEGER = NULL,
    max_batches_per_execution INTEGER = NULL,
    refresh_newest_first BOOL = NULL
)
RETURNS INTEGER
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_refresh_cagg_add'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION @extschema@.remove_continuous_aggregate_policy(
    continuous_aggregate REGCLASS,
    if_not_exists BOOL = false, -- deprecating this argument, if_exists overrides it
    if_exists BOOL = NULL) -- when NULL get the value from if_not_exists

RETURNS VOID
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_refresh_cagg_remove'
LANGUAGE C VOLATILE;

/* 1 step policies */

/* Add policies */
/* Unsupported drop_created_before/compress_created_before in add/alter for caggs */
CREATE OR REPLACE FUNCTION timescaledb_experimental.add_policies(
    relation REGCLASS,
    if_not_exists BOOL = false,
    refresh_start_offset "any" = NULL,
    refresh_end_offset "any" = NULL,
    compress_after "any" = NULL,
    drop_after "any" = NULL
) RETURNS BOOL AS '$libdir/timescaledb-2.27.0-dev', 'ts_policies_add' LANGUAGE C VOLATILE;

/* Remove policies */
CREATE OR REPLACE FUNCTION timescaledb_experimental.remove_policies(
    relation REGCLASS,
    if_exists BOOL = false,
    VARIADIC policy_names TEXT[] = NULL)
RETURNS BOOL
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policies_remove'
LANGUAGE C VOLATILE;

/* Remove all policies */
CREATE OR REPLACE FUNCTION timescaledb_experimental.remove_all_policies(
    relation REGCLASS,
    if_exists BOOL = false)
RETURNS BOOL
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policies_remove_all'
LANGUAGE C VOLATILE;

/* Alter policies */
CREATE OR REPLACE FUNCTION timescaledb_experimental.alter_policies(
    relation REGCLASS,
    if_exists BOOL = false,
    refresh_start_offset "any" = NULL,
    refresh_end_offset "any" = NULL,
    compress_after "any" = NULL,
    drop_after "any" = NULL)
RETURNS BOOL
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policies_alter'
LANGUAGE C VOLATILE;

/* Show policies info */
CREATE OR REPLACE FUNCTION timescaledb_experimental.show_policies(
    relation REGCLASS)
RETURNS SETOF JSONB
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policies_show'
LANGUAGE C  VOLATILE;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE PROCEDURE _timescaledb_functions.policy_retention(job_id INTEGER, config JSONB)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_retention_proc'
LANGUAGE C;

CREATE OR REPLACE FUNCTION _timescaledb_functions.policy_retention_check(config JSONB)
RETURNS void AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_retention_check'
LANGUAGE C;

CREATE OR REPLACE PROCEDURE _timescaledb_functions.policy_reorder(job_id INTEGER, config JSONB)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_reorder_proc'
LANGUAGE C;

CREATE OR REPLACE FUNCTION _timescaledb_functions.policy_reorder_check(config JSONB)
RETURNS void AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_reorder_check'
LANGUAGE C;

CREATE OR REPLACE PROCEDURE _timescaledb_functions.policy_recompression(job_id INTEGER, config JSONB)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_recompression_proc'
LANGUAGE C;

CREATE OR REPLACE FUNCTION _timescaledb_functions.policy_compression_check(config JSONB)
RETURNS void AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_compression_check'
LANGUAGE C;

CREATE OR REPLACE PROCEDURE _timescaledb_functions.policy_refresh_continuous_aggregate(job_id INTEGER, config JSONB)
AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_refresh_cagg_proc'
LANGUAGE C;

CREATE OR REPLACE FUNCTION _timescaledb_functions.policy_refresh_continuous_aggregate_check(config JSONB)
RETURNS void AS '$libdir/timescaledb-2.27.0-dev', 'ts_policy_refresh_cagg_check'
LANGUAGE C;

CREATE OR REPLACE PROCEDURE
_timescaledb_functions.policy_compression_execute(
  job_id              INTEGER,
  htid                INTEGER,
  lag                 ANYELEMENT,
  maxchunks           INTEGER,
  verbose_log         BOOLEAN,
  recompress_enabled  BOOLEAN,
  reindex_enabled     BOOLEAN,
  use_creation_time   BOOLEAN
)
AS $$
DECLARE
  htoid       REGCLASS;
  chunk_rec   RECORD;
  idx_rec     RECORD;
  numchunks_compressed   INTEGER := 0;
  _message     text;
  _detail      text;
  _sqlstate    text;
  -- fully compressed chunk status
  status_fully_compressed int := 1;
  -- chunk status bits:
  bit_uncompressed int := 0;
  bit_frozen int := 4;
  bit_compressed_partial int := 8;
  creation_lag INTERVAL := NULL;
  chunks_failure INTEGER := 0;
BEGIN

  -- procedures with SET clause cannot execute transaction
  -- control so we adjust search_path in procedure body
  SET LOCAL search_path TO pg_catalog, pg_temp;

  SELECT format('%I.%I', schema_name, table_name) INTO htoid
  FROM _timescaledb_catalog.hypertable
  WHERE id = htid;

  -- for the integer cases, we have to compute the lag w.r.t
  -- the integer_now function and then pass on to show_chunks
  IF pg_typeof(lag) IN ('BIGINT'::regtype, 'INTEGER'::regtype, 'SMALLINT'::regtype) THEN
    -- cannot have use_creation_time set with this
    IF use_creation_time IS TRUE THEN
        RAISE EXCEPTION 'job % cannot use creation time with integer_now function', job_id;
    END IF;
    lag := _timescaledb_functions.subtract_integer_from_now(htoid, lag::BIGINT);
  END IF;

  -- if use_creation_time has been specified then the lag needs to be used with the
  -- "compress_created_before" argument. Otherwise the usual "older_than" argument
  -- is good enough
  IF use_creation_time IS TRUE THEN
    creation_lag := lag;
    lag := NULL;
  END IF;

  FOR chunk_rec IN
    SELECT
      show.oid, ch.schema_name, ch.table_name, ch.status
    FROM
      @extschema@.show_chunks(htoid, older_than => lag, created_before => creation_lag) AS show(oid)
      INNER JOIN pg_class pgc ON pgc.oid = show.oid
      INNER JOIN pg_namespace pgns ON pgc.relnamespace = pgns.oid
      INNER JOIN _timescaledb_catalog.chunk ch ON ch.table_name = pgc.relname AND ch.schema_name = pgns.nspname AND ch.hypertable_id = htid
    WHERE NOT ch.osm_chunk
    -- Checking for chunks which are not fully compressed and not frozen
    AND ch.status != status_fully_compressed
    AND ch.status & bit_frozen = 0
  LOOP
    BEGIN
      IF chunk_rec.status = bit_uncompressed OR recompress_enabled IS TRUE THEN
        PERFORM @extschema@.compress_chunk(chunk_rec.oid);
        numchunks_compressed := numchunks_compressed + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
          _message = MESSAGE_TEXT,
          _detail = PG_EXCEPTION_DETAIL,
          _sqlstate = RETURNED_SQLSTATE;
      RAISE WARNING 'converting chunk "%" to columnstore failed when recompress columnstore policy is executed', chunk_rec.oid::regclass::text
          USING DETAIL = format('Message: (%s), Detail: (%s).', _message, _detail),
                ERRCODE = _sqlstate;
      chunks_failure := chunks_failure + 1;
    END;
    COMMIT;

    -- went through recompression successfully now reindex indexes
    IF (chunk_rec.status & bit_compressed_partial = bit_compressed_partial) AND (reindex_enabled IS TRUE) THEN
      FOR idx_rec IN
        SELECT idx.schemaname, idx.indexname
        FROM pg_indexes idx
        JOIN _timescaledb_catalog.chunk ch ON ch.schema_name = idx.schemaname AND ch.table_name = idx.tablename
        WHERE idx.schemaname = chunk_rec.schema_name
          AND idx.tablename = chunk_rec.table_name
          AND ch.status = status_fully_compressed
      LOOP
        BEGIN
          EXECUTE format('REINDEX INDEX %I.%I;', idx_rec.schemaname, idx_rec.indexname);
        EXCEPTION WHEN OTHERS THEN
          GET STACKED DIAGNOSTICS
              _message = MESSAGE_TEXT,
              _detail = PG_EXCEPTION_DETAIL,
              _sqlstate = RETURNED_SQLSTATE;
          RAISE WARNING 'reindexing index "%.%" for chunk "%" to columnstore failed when columnstore policy is executed', idx_rec.schemaname, idx_rec.indexname, chunk_rec.oid::regclass::text
              USING DETAIL = format('Message: (%s), Detail: (%s).', _message, _detail),
                    ERRCODE = _sqlstate;
        END;
        COMMIT;
      END LOOP;
    END IF;

    -- SET LOCAL is only active until end of transaction.
    -- While we could use SET at the start of the function we do not
    -- want to bleed out search_path to caller, so we do SET LOCAL
    -- again after COMMIT
    SET LOCAL search_path TO pg_catalog, pg_temp;
    IF verbose_log THEN
       RAISE LOG 'job % completed processing chunk %.%', job_id, chunk_rec.schema_name, chunk_rec.table_name;
    END IF;
    IF maxchunks > 0 AND numchunks_compressed >= maxchunks THEN
         EXIT;
    END IF;
  END LOOP;

  IF chunks_failure > 0 THEN
    IF numchunks_compressed > 0 THEN
      RAISE WARNING 'columnstore policy completed with some failures'
        USING DETAIL = format('Failed to convert %L chunks to columnstore. Successfully converted %L chunks.', chunks_failure, numchunks_compressed);
    ELSE
      RAISE EXCEPTION 'columnstore policy failure'
        USING
          DETAIL = format('Failed to convert %L chunks to columnstore. Successfully converted %L chunks.', chunks_failure, numchunks_compressed),
          ERRCODE = 'data_exception';
    END IF;
  END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE PROCEDURE
_timescaledb_functions.policy_compression(job_id INTEGER, config JSONB)
AS $$
DECLARE
  dimtype             REGTYPE;
  dimtypeinput        REGPROC;
  compress_after      TEXT;
  compress_created_before TEXT;
  lag_value           TEXT;
  lag_bigint_value    BIGINT;
  htid                INTEGER;
  htoid               REGCLASS;
  chunk_rec           RECORD;
  verbose_log         BOOL;
  maxchunks           INTEGER := 0;
  numchunks           INTEGER := 1;
  recompress_enabled  BOOL;
  reindex_enabled     BOOL;
  use_creation_time   BOOL := FALSE;
BEGIN

  -- procedures with SET clause cannot execute transaction
  -- control so we adjust search_path in procedure body
  SET LOCAL search_path TO pg_catalog, pg_temp;

  IF config IS NULL THEN
    RAISE EXCEPTION 'job % has null config', job_id;
  END IF;

  htid := jsonb_object_field_text(config, 'hypertable_id')::INTEGER;
  IF htid is NULL THEN
    RAISE EXCEPTION 'job % config must have hypertable_id', job_id;
  END IF;

  verbose_log         := COALESCE(jsonb_object_field_text(config, 'verbose_log')::BOOLEAN, FALSE);
  maxchunks           := COALESCE(jsonb_object_field_text(config, 'maxchunks_to_compress')::INTEGER, 0);
  recompress_enabled  := COALESCE(jsonb_object_field_text(config, 'recompress')::BOOLEAN, TRUE);
  reindex_enabled     := COALESCE(jsonb_object_field_text(config, 'reindex')::BOOLEAN, TRUE);

  -- find primary dimension type --
  SELECT dim.column_type INTO dimtype
  FROM  _timescaledb_catalog.hypertable ht
        JOIN _timescaledb_catalog.dimension dim ON ht.id = dim.hypertable_id
  WHERE ht.id = htid
  ORDER BY dim.id
  LIMIT 1;

  compress_after      := jsonb_object_field_text(config, 'compress_after');
  IF compress_after IS NULL THEN
    compress_created_before := jsonb_object_field_text(config, 'compress_created_before');
    IF compress_created_before IS NULL THEN
        RAISE EXCEPTION 'job % config must have compress_after or compress_created_before', job_id;
    END IF;
    lag_value := compress_created_before;
    use_creation_time := true;
    dimtype := 'INTERVAL' ::regtype;
  ELSE
    lag_value := compress_after;
  END IF;

  -- execute the properly type casts for the lag value
  CASE dimtype
    WHEN 'TIMESTAMP'::regtype, 'TIMESTAMPTZ'::regtype, 'DATE'::regtype, 'INTERVAL' ::regtype, 'UUID'::regtype THEN
      CALL _timescaledb_functions.policy_compression_execute(job_id, htid, lag_value::INTERVAL, maxchunks, verbose_log, recompress_enabled, reindex_enabled, use_creation_time);
    WHEN 'BIGINT'::regtype THEN
      CALL _timescaledb_functions.policy_compression_execute(job_id, htid, lag_value::BIGINT, maxchunks, verbose_log, recompress_enabled, reindex_enabled, use_creation_time);
    WHEN 'INTEGER'::regtype THEN
      CALL _timescaledb_functions.policy_compression_execute(job_id, htid, lag_value::INTEGER, maxchunks, verbose_log, recompress_enabled, reindex_enabled, use_creation_time);
    WHEN 'SMALLINT'::regtype THEN
      CALL _timescaledb_functions.policy_compression_execute(job_id, htid, lag_value::SMALLINT, maxchunks, verbose_log, recompress_enabled, reindex_enabled, use_creation_time);
  END CASE;
  COMMIT;
END;
$$ LANGUAGE PLPGSQL;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION _timescaledb_functions.cagg_validate_query(
    query TEXT,
    OUT is_valid BOOLEAN,
    OUT error_level TEXT,
    OUT error_code TEXT,
    OUT error_message TEXT,
    OUT error_detail TEXT,
    OUT error_hint TEXT
) RETURNS RECORD AS '$libdir/timescaledb-2.27.0-dev', 'ts_continuous_agg_validate_query' LANGUAGE C STRICT VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.cagg_get_bucket_function_info(
    mat_hypertable_id INTEGER,
    -- The bucket function
    OUT bucket_func REGPROCEDURE,
    -- `bucket_width` argument of the function, e.g. "1 month"
    OUT bucket_width TEXT,
    -- optional `origin` argument of the function provided by the user
    OUT bucket_origin TEXT,
    -- optional `offset` argument of the function provided by the user
    OUT bucket_offset TEXT,
    -- optional `timezone` argument of the function provided by the user
    OUT bucket_timezone TEXT,
    -- fixed or variable sized bucket
    OUT bucket_fixed_width BOOLEAN
) RETURNS RECORD AS '$libdir/timescaledb-2.27.0-dev', 'ts_continuous_agg_get_bucket_function_info' LANGUAGE C STRICT VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.cagg_get_grouping_columns(
    cagg REGCLASS )
    RETURNS TEXT[] AS '$libdir/timescaledb-2.27.0-dev', 'ts_continuous_agg_get_grouping_columns'
LANGUAGE C STRICT VOLATILE;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- A retention policy is set up for the table _timescaledb_internal.job_errors (Error Log Retention Policy [2])
-- By default, it will run once a month and and drop rows older than a month.

CREATE OR REPLACE FUNCTION _timescaledb_functions.policy_job_stat_history_retention(job_id integer, config JSONB) RETURNS VOID
LANGUAGE PLPGSQL AS
$BODY$
BEGIN
  -- Delete rows older than the cutoff
  DELETE FROM _timescaledb_internal.bgw_job_stat_history
  WHERE execution_start < now() - (config->>'drop_after')::interval;

  -- Delete excess per-job entries beyond the configured limits
  WITH enumerated AS (
    SELECT id,
           row_number() OVER (
               PARTITION BY j.job_id, j.succeeded
               ORDER BY j.execution_start DESC
           ) AS rn,
           j.succeeded
      FROM _timescaledb_internal.bgw_job_stat_history j
  )
  DELETE FROM _timescaledb_internal.bgw_job_stat_history
  WHERE id IN (
    SELECT e.id FROM enumerated e
    WHERE (e.succeeded AND e.rn > (config->>'max_successes_per_job')::int)
       OR (NOT e.succeeded AND e.rn > (config->>'max_failures_per_job')::int)
  );
END
$BODY$ SET search_path TO pg_catalog, pg_temp;

CREATE OR REPLACE FUNCTION _timescaledb_functions.policy_job_stat_history_retention_check(config JSONB) RETURNS VOID
LANGUAGE PLPGSQL AS
$BODY$
BEGIN
    IF config IS NULL THEN
        RAISE EXCEPTION 'config cannot be NULL, and must contain drop_after';
    END IF;

    IF NOT (config ? 'drop_after') THEN
        RAISE EXCEPTION 'drop_after interval not provided';
    END IF;

    IF NOT (config ? 'max_successes_per_job') THEN
        RAISE EXCEPTION 'max_successes_per_job not provided';
    END IF;

    IF NOT (config ? 'max_failures_per_job') THEN
        RAISE EXCEPTION 'max_failures_per_job not provided';
    END IF;

    IF (config->>'max_successes_per_job')::integer < 10 THEN
        RAISE EXCEPTION 'max_successes_per_job has to be at least 10';
    END IF;

    IF (config->>'max_failures_per_job')::integer < 10 THEN
        RAISE EXCEPTION 'max_failures_per_job has to be at least 10';
    END IF;
END
$BODY$ SET search_path TO pg_catalog, pg_temp;

INSERT INTO _timescaledb_catalog.bgw_job (
    id,
    application_name,
    schedule_interval,
    max_runtime,
    max_retries,
    retry_period,
    proc_schema,
    proc_name,
    owner,
    scheduled,
    config,
    check_schema,
    check_name,
    fixed_schedule,
    initial_start
)
VALUES
(
    3,
    'Job History Log Retention Policy [3]',
    INTERVAL '6 hours',
    INTERVAL '1 hour',
    -1,
    INTERVAL '1h',
    '_timescaledb_functions',
    'policy_job_stat_history_retention',
    pg_catalog.quote_ident(current_role)::regrole,
    true,
    '{"drop_after":"1 month","max_successes_per_job":1000,"max_failures_per_job":1000}',
    '_timescaledb_functions',
    'policy_job_stat_history_retention_check',
    true,
    '2000-01-01 00:00:00+00'::timestamptz
) ON CONFLICT (id) DO NOTHING;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- This function updates the dimension slice range stored in the catalog with the min and max
-- values that the OSM chunk contains. Since there is only one OSM chunk per hypertable with
-- only a time dimension, the hypertable is used to determine the corresponding slice
CREATE OR REPLACE FUNCTION _timescaledb_functions.hypertable_osm_range_update(
    hypertable REGCLASS,
    range_start ANYELEMENT = NULL::bigint,
    range_end ANYELEMENT = NULL,
    empty BOOL = false
) RETURNS BOOL AS '$libdir/timescaledb-2.27.0-dev',
'ts_hypertable_osm_range_update' LANGUAGE C VOLATILE;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.


-- This function return a jsonb with the following keys:
-- - columns: an array of column names that shold be used for segment by
-- - confidence: a number between 0 and 10 (most confident) indicating how sure we are.
-- - message: a message that should be displayed to the user to evaluate the result.
CREATE OR REPLACE FUNCTION _timescaledb_functions.get_segmentby_defaults(
    relation regclass
)
    RETURNS JSONB LANGUAGE PLPGSQL AS
$BODY$
DECLARE
    _table_name NAME;
    _schema_name NAME;
    _hypertable_row _timescaledb_catalog.hypertable;
    _segmentby NAME;
    _cnt int;
BEGIN
    SELECT n.nspname, c.relname INTO STRICT _schema_name, _table_name
    FROM pg_class c
    INNER JOIN pg_namespace n ON (n.oid = c.relnamespace)
    WHERE c.oid = relation;

    SELECT * INTO STRICT _hypertable_row FROM _timescaledb_catalog.hypertable h WHERE h.table_name = _table_name AND h.schema_name = _schema_name;

    --STEP 1 if column stats exist use unique indexes.
    --Pick the column that comes first in any such indexes
    --Select the column such that tuples are segmented evenly across distinct values.
    --Note: this will only pick a column that is NOT unique in a multi-column unique index.
    with index_attr as (
      SELECT
        a.attnum, min(a.pos) as pos
      FROM (
        SELECT indkey, indnkeyatts
        FROM pg_catalog.pg_index
        WHERE indisunique AND indrelid = relation
      ) i
      INNER JOIN LATERAL (
        SELECT * FROM unnest(i.indkey) WITH ORDINALITY
      ) a(attnum, pos) ON TRUE
      WHERE a.pos <= i.indnkeyatts
      GROUP BY a.attnum
    ),
    stats_with_stddev as (
      SELECT
        a.attname,
        i.pos,
        ROUND(stddev_pop(freqs)::numeric, 5) as freq_stddev
      FROM index_attr i
      INNER JOIN pg_attribute a ON a.attnum = i.attnum AND a.attrelid = relation
      INNER JOIN pg_type t ON t.oid = a.atttypid
      INNER JOIN pg_stats s ON s.attname = a.attname
                            AND s.schemaname = _schema_name
                            AND s.tablename = _table_name
                            AND s.inherited = true
      LEFT JOIN LATERAL unnest(s.most_common_freqs) as freqs ON TRUE
      WHERE a.attname NOT IN (
        SELECT column_name
        FROM _timescaledb_catalog.dimension d
        WHERE d.hypertable_id = _hypertable_row.id
      )
      AND s.n_distinct > 1
      -- exclude date/time type category
      AND t.typcategory NOT IN ('D')
      GROUP BY a.attname, i.pos
    )
    SELECT attname
    INTO _segmentby
    FROM stats_with_stddev
    ORDER BY pos ASC, freq_stddev ASC NULLS LAST
    LIMIT 1;

    IF FOUND THEN
        return json_build_object('columns', json_build_array(_segmentby), 'confidence', 10);
    END IF;


    --STEP 2 if column stats exist and no unique indexes use non-unique indexes.
    --Pick the column that comes first in any such indexes
    --Select the column such that tuples are segmented evenly across distinct values.
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
            (select indkey, indnkeyatts from pg_catalog.pg_index where NOT indisunique and indrelid = relation) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos <= i.indnkeyatts
        GROUP BY 1
    ),
    stats_with_stddev as (
      SELECT
        a.attname,
        i.pos,
        ROUND(stddev_pop(freqs)::numeric, 5) as freq_stddev
      FROM index_attr i
      INNER JOIN pg_attribute a ON a.attnum = i.attnum AND a.attrelid = relation
      INNER JOIN pg_type t ON t.oid = a.atttypid
      INNER JOIN pg_stats s ON s.attname = a.attname
                            AND s.schemaname = _schema_name
                            AND s.tablename = _table_name
                            AND s.inherited = true
      LEFT JOIN LATERAL unnest(s.most_common_freqs) as freqs ON TRUE
      WHERE a.attname NOT IN (
        SELECT column_name
        FROM _timescaledb_catalog.dimension d
        WHERE d.hypertable_id = _hypertable_row.id
      )
      AND s.n_distinct > 1
      AND t.typcategory NOT IN ('D')
      GROUP BY a.attname, i.pos
    )
    SELECT attname
    INTO _segmentby
    FROM stats_with_stddev
    ORDER BY pos ASC, freq_stddev ASC NULLS LAST
    LIMIT 1;

    IF FOUND THEN
        return json_build_object('columns', json_build_array(_segmentby), 'confidence', 8);
    END IF;

    --STEP 3 if column stats exist but there are no indexes
    --Select the column such that tuples are segmented evenly across distinct values.
    with stats_with_stddev as (
      SELECT
        a.attname,
        ROUND(stddev_pop(freqs)::numeric, 5) as freq_stddev
      FROM pg_attribute a
      INNER JOIN pg_type t ON t.oid = a.atttypid
      INNER JOIN pg_stats s ON s.attname = a.attname
                            AND s.schemaname = _schema_name
                            AND s.tablename = _table_name
                            AND s.inherited = true
      LEFT JOIN LATERAL unnest(s.most_common_freqs) as freqs ON TRUE
      WHERE a.attrelid = relation
        AND a.attname NOT IN (
          SELECT column_name
          FROM _timescaledb_catalog.dimension d
          WHERE d.hypertable_id = _hypertable_row.id
        )
      AND s.n_distinct > 1
      AND t.typcategory NOT IN ('D')
      GROUP BY a.attname
    )
    SELECT attname
    INTO _segmentby
    FROM stats_with_stddev
    ORDER BY freq_stddev ASC NULLS LAST
    LIMIT 1;

    IF FOUND THEN
        return json_build_object('columns', json_build_array(_segmentby), 'confidence', 7);
    END IF;

    --STEP 4 if column stats do not exist use non-unique indexes. Pick the column that comes first in any such indexes. Ties are broken arbitrarily.
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
            (select indkey, indnkeyatts from pg_catalog.pg_index where NOT indisunique and indrelid = relation) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos <= i.indnkeyatts
        GROUP BY 1
    )
    SELECT
      a.attname INTO _segmentby
    FROM
      index_attr i
    INNER JOIN
      pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
    INNER JOIN
      pg_type t ON t.oid = a.atttypid
    LEFT JOIN
      pg_catalog.pg_attrdef ad ON (ad.adrelid = relation AND ad.adnum = a.attnum)
    LEFT JOIN pg_stats s ON s.attname = a.attname
                          AND s.schemaname = _schema_name
                          AND s.tablename = _table_name
                          AND s.inherited = true
    WHERE
      a.attname NOT IN (SELECT column_name FROM _timescaledb_catalog.dimension d WHERE d.hypertable_id = _hypertable_row.id)
      AND s.n_distinct is null
      AND a.attidentity = '' AND (ad.adbin IS NULL OR pg_get_expr(adbin, adrelid) not like 'nextval%')
      AND t.typcategory NOT IN ('D')
    ORDER BY i.pos
    LIMIT 1;

    IF FOUND THEN
        return json_build_object(
            'columns', json_build_array(_segmentby),
            'confidence', 5,
            'message',  'Please make sure '|| _segmentby||' is not a unique column and appropriate for a segment by');
    END IF;

    --STEP 5 if column stats do not exist and no non-unique indexes, use unique indexes. Pick the column that comes first in any such indexes. Ties are broken arbitrarily.
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
            (select indkey, indnkeyatts from pg_catalog.pg_index where indisunique and indrelid = relation) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos <= i.indnkeyatts
        GROUP BY 1
    )
    SELECT
      a.attname INTO _segmentby
    FROM
      index_attr i
    INNER JOIN
      pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
    INNER JOIN
      pg_type t ON t.oid = a.atttypid
    LEFT JOIN
      pg_catalog.pg_attrdef ad ON (ad.adrelid = relation AND ad.adnum = a.attnum)
    LEFT JOIN pg_stats s ON s.attname = a.attname
                          AND s.schemaname = _schema_name
                          AND s.tablename = _table_name
                          AND s.inherited = true
    WHERE
      a.attname NOT IN (SELECT column_name FROM _timescaledb_catalog.dimension d WHERE d.hypertable_id = _hypertable_row.id)
      AND s.n_distinct is null
      AND a.attidentity = '' AND (ad.adbin IS NULL OR pg_get_expr(adbin, adrelid) not like 'nextval%')
      AND t.typcategory NOT IN ('D')
    ORDER BY i.pos
    LIMIT 1;

    IF FOUND THEN
            return json_build_object(
            'columns', json_build_array(_segmentby),
            'confidence', 5,
            'message',  'Please make sure '|| _segmentby||' is not a unique column and appropriate for a segment by');
    END IF;


    --are there any indexed columns that are not dimemsions and are not serial/identity?
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
            (select indkey, indnkeyatts from pg_catalog.pg_index where indisunique and indrelid = relation) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos <= i.indnkeyatts
        GROUP BY 1
    )
    SELECT
      count(*) INTO STRICT _cnt
    FROM
      index_attr i
    INNER JOIN
      pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
    INNER JOIN
      pg_type t ON t.oid = a.atttypid
    LEFT JOIN
      pg_catalog.pg_attrdef ad ON (ad.adrelid = relation AND ad.adnum = a.attnum)
    WHERE
      a.attname NOT IN (SELECT column_name FROM _timescaledb_catalog.dimension d WHERE d.hypertable_id = _hypertable_row.id)
      AND a.attidentity = '' AND (ad.adbin IS NULL OR pg_get_expr(adbin, adrelid) not like 'nextval%')
      AND t.typcategory NOT IN ('D');

    IF _cnt > 0 THEN
        --there are many potential candidates. We do not have enough information to choose one.
        return json_build_object(
            'columns', json_build_array(),
            'confidence', 0,
            'message',  'Several columns are potential segment by candidates and we do not have enough information to choose one. Please use the segment_by option to explicitly specify the segment_by column');
    ELSE
        --there are no potential candidates. There is a good chance no segment by is the correct choice.
        return json_build_object(
            'columns', json_build_array(),
            'confidence', 5,
            'message',  'You do not have any indexes on columns that can be used for segment_by and thus we are not using segment_by for converting to columnstore. Please make sure you are not missing any indexes');
    END IF;
END
$BODY$ SET search_path TO pg_catalog, pg_temp;

-- This function return a jsonb with the following keys:
-- - clauses: an array of column names and sort order key words that shold be used for order by.
-- - confidence: a number between 0 and 10 (most confident) indicating how sure we are.
-- - message: a message that should be shown to the user to evaluate the result.
CREATE OR REPLACE FUNCTION _timescaledb_functions.get_orderby_defaults(
    relation regclass, segment_by_cols text[]
)
    RETURNS JSONB LANGUAGE PLPGSQL AS
$BODY$
DECLARE
    _table_name NAME;
    _schema_name NAME;
    _hypertable_row _timescaledb_catalog.hypertable;
    _orderby_names NAME[];
    _dimension_names NAME[];
    _first_index_attrs NAME[];
    _orderby_clauses text[];
    _confidence int;
BEGIN
    SELECT n.nspname, c.relname INTO STRICT _schema_name, _table_name
    FROM pg_class c
    INNER JOIN pg_namespace n ON (n.oid = c.relnamespace)
    WHERE c.oid = relation;

    SELECT * INTO STRICT _hypertable_row FROM _timescaledb_catalog.hypertable h WHERE h.table_name = _table_name AND h.schema_name = _schema_name;

    --start with the unique index columns minus the segment by columns
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
             --is there a better way to pick the right unique index if there are multiple?
            (select indkey, indnkeyatts from pg_catalog.pg_index where indisunique and indrelid = relation limit 1) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos <= i.indnkeyatts
        GROUP BY 1
    )
    SELECT
      array_agg(a.attname ORDER BY i.pos) INTO _orderby_names
    FROM
      index_attr i
    INNER JOIN
      pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
    WHERE
      NOT(a.attname::text = ANY (segment_by_cols));

    if _orderby_names is null then
        _orderby_names := array[]::name[];
        _confidence := 5;
    else
        _confidence := 8;
    end if;

    --add dimension colomns to the end. A dimension column like time should probably always be part of the order by.
    SELECT
      array_agg(d.column_name) INTO _dimension_names
    FROM _timescaledb_catalog.dimension d
    WHERE
      d.hypertable_id = _hypertable_row.id
      AND NOT(d.column_name::text = ANY (_orderby_names))
      AND NOT(d.column_name::text = ANY (segment_by_cols));
    _orderby_names := _orderby_names || _dimension_names;

    --add the first attribute of any index
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
            (select indkey, indnkeyatts from pg_catalog.pg_index where indrelid = relation) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos = 1
        GROUP BY 1
    )
    SELECT
      array_agg(a.attname ORDER BY i.pos) INTO _first_index_attrs
    FROM
      index_attr i
    INNER JOIN
      pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
    WHERE
          NOT(a.attname::text = ANY (_orderby_names))
      AND NOT(a.attname::text = ANY (segment_by_cols));

    _orderby_names := _orderby_names || _first_index_attrs;

    --add DESC to any dimensions
    SELECT
      coalesce(array_agg(
      CASE WHEN d.column_name IS NULL THEN
        format('%I', a.colname)
      ELSE
        format('%I DESC', a.colname)
      END ORDER BY pos), array[]::text[]) INTO STRICT _orderby_clauses
    FROM unnest(_orderby_names) WITH ORDINALITY as a(colname, pos)
    LEFT JOIN _timescaledb_catalog.dimension d ON (d.column_name = a.colname AND d.hypertable_id = _hypertable_row.id);


    return json_build_object('clauses', _orderby_clauses, 'confidence', _confidence);
END
$BODY$ SET search_path TO pg_catalog, pg_temp;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION _timescaledb_functions.bloom1_contains(_timescaledb_internal.bloom1, anyelement)
RETURNS bool
AS '$libdir/timescaledb-2.27.0-dev', 'ts_bloom1_contains'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.bloom1_contains_any(_timescaledb_internal.bloom1, anyarray)
RETURNS bool
AS '$libdir/timescaledb-2.27.0-dev', 'ts_bloom1_contains_any'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.jsonb_get_matching_index_entry(
    config jsonb,
    attr_name text,
    target_type text
) RETURNS jsonb AS $$
DECLARE
    elem jsonb;
    attr_count int := 0;
BEGIN
  -- Return NULL if any input is NULL
  IF config IS NULL OR attr_name IS NULL OR target_type IS NULL THEN
    RETURN NULL;
  END IF;

  FOR elem IN SELECT * FROM jsonb_array_elements(config)
  LOOP
    IF elem->>'column' =  attr_name THEN
      attr_count := attr_count + 1;

      IF elem->>'type' = target_type THEN
        IF attr_count > 2 THEN
          RAISE EXCEPTION 'Found % sparse index entries for attribute "%"', attr_count, attr_name;
        END IF;
        RETURN elem;
      END IF;
    END IF;
  END LOOP;

  IF attr_count > 2 THEN
    RAISE EXCEPTION 'Found % sparse index entries for attribute "%"', attr_count, attr_name;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE PLPGSQL
SET search_path TO pg_catalog, pg_temp;

-- Takes pre-computed hash array and checks if ANY of the hashes
-- match the bloom1 parameter. This function doesn't hash, it only compares.
-- Handles both single equality (1-element array) and ANY (N-element array).
-- Returns true if the bloom maybe-contains ANY of the given hashes.
--
-- This function is intentionally not STRICT, because in case of NULL in the first
-- parameter, we can't decide and will return TRUE.
--
CREATE OR REPLACE FUNCTION _timescaledb_functions.bloom1_contains_any_hashes(_timescaledb_internal.bloom1, bigint[])
RETURNS bool
AS '$libdir/timescaledb-2.27.0-dev', 'ts_bloom1_contains_any_hashes'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.bloom1_hash(anyelement)
RETURNS bigint
AS '$libdir/timescaledb-2.27.0-dev', 'ts_bloom1_hash'
LANGUAGE C IMMUTABLE PARALLEL SAFE;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- This file contains utility functions and views that are used for
-- debugging in release builds. These are all placed in the schema
-- _timescaledb_debug.

CREATE OR REPLACE FUNCTION _timescaledb_functions.extension_state() RETURNS TEXT
AS '$libdir/timescaledb-2.27.0-dev', 'ts_extension_get_state' LANGUAGE C;

-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION @extschema@.get_telemetry_report()
       RETURNS jsonb AS '$libdir/timescaledb-2.27.0-dev', 'ts_telemetry_get_report_jsonb'
       LANGUAGE C STABLE PARALLEL SAFE;

INSERT INTO _timescaledb_catalog.bgw_job (id, application_name, schedule_interval, max_runtime, max_retries, retry_period, proc_schema, proc_name, owner, scheduled, fixed_schedule) VALUES
(1, 'Telemetry Reporter [1]', INTERVAL '24h', INTERVAL '100s', -1, INTERVAL '1h', '_timescaledb_functions', 'policy_telemetry', pg_catalog.quote_ident(current_role)::regrole, true, false)
ON CONFLICT (id) DO NOTHING;
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- TimescaleDB 2.12 moved all functions present in _timescaledb_internal into
-- _timescaledb_functions. This file contains a compatibility layer to allow
-- for more flexibility when migrating for any users calling these internal
-- functions.
-- This compatibility layer will be removed in a future versions.


CREATE OR REPLACE FUNCTION _timescaledb_internal.alter_job_set_hypertable_id(job_id integer, hypertable regclass) RETURNS integer LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.alter_job_set_hypertable_id(integer,regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.alter_job_set_hypertable_id($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.attach_osm_table_chunk(hypertable regclass, chunk regclass) RETURNS boolean LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.attach_osm_table_chunk(regclass,regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.attach_osm_table_chunk($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.cagg_watermark(hypertable_id integer) RETURNS bigint LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.cagg_watermark(integer) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.cagg_watermark($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.cagg_watermark_materialized(hypertable_id integer) RETURNS bigint LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.cagg_watermark_materialized(integer) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.cagg_watermark_materialized($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.calculate_chunk_interval(dimension_id integer,dimension_coord bigint,chunk_target_size bigint) RETURNS bigint LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.calculate_chunk_interval(integer,bigint,bigint) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.calculate_chunk_interval($1,$2,$3);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.chunk_constraint_add_table_constraint(chunk_constraint_row _timescaledb_catalog.chunk_constraint) RETURNS void LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.chunk_constraint_add_table_constraint(_timescaledb_catalog.chunk_constraint) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  PERFORM _timescaledb_functions.chunk_constraint_add_table_constraint($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.chunk_id_from_relid(relid oid) RETURNS integer LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.chunk_id_from_relid(oid) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.chunk_id_from_relid($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.chunk_status(regclass) RETURNS integer LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.chunk_status(regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.chunk_status($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.chunks_local_size(schema_name_in name,table_name_in name) RETURNS TABLE (chunk_id integer, chunk_schema NAME, chunk_name  NAME, table_bytes bigint, index_bytes bigint, toast_bytes bigint, total_bytes bigint) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.chunks_local_size(name,name) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN QUERY SELECT * FROM _timescaledb_functions.chunks_local_size($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.compressed_chunk_local_stats(schema_name_in name,table_name_in name) RETURNS TABLE (chunk_schema name, chunk_name name, compression_status text, before_compression_table_bytes bigint, before_compression_index_bytes bigint, before_compression_toast_bytes bigint, before_compression_total_bytes bigint, after_compression_table_bytes bigint, after_compression_index_bytes bigint, after_compression_toast_bytes bigint, after_compression_total_bytes bigint) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.compressed_chunk_local_stats(name,name) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN QUERY SELECT * FROM _timescaledb_functions.compressed_chunk_local_stats($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.compressed_chunk_remote_stats(schema_name_in name,table_name_in name) RETURNS TABLE ( chunk_schema name, chunk_name name, compression_status text, before_compression_table_bytes bigint, before_compression_index_bytes bigint, before_compression_toast_bytes bigint, before_compression_total_bytes bigint, after_compression_table_bytes bigint, after_compression_index_bytes bigint, after_compression_toast_bytes bigint, after_compression_total_bytes bigint, node_name name) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.compressed_chunk_remote_stats(name,name) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN QUERY SELECT * FROM _timescaledb_functions.compressed_chunk_remote_stats($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;

-- we have to prefix slices, schema_name and table_name parameter with _ here to not clash with output names otherwise plpgsql will complain
CREATE OR REPLACE FUNCTION _timescaledb_internal.create_chunk(hypertable regclass,_slices jsonb,_schema_name name=NULL,_table_name name=NULL,chunk_table regclass=NULL) RETURNS TABLE(chunk_id INTEGER, hypertable_id INTEGER, schema_name NAME, table_name NAME, relkind "char", slices JSONB, created BOOLEAN) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.create_chunk(regclass,jsonb,name,name,regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN QUERY SELECT * FROM _timescaledb_functions.create_chunk($1,$2,$3,$4,$5);
END$$
SET search_path TO pg_catalog,pg_temp;

CREATE OR REPLACE FUNCTION _timescaledb_internal.create_compressed_chunk(chunk regclass,chunk_table regclass,uncompressed_heap_size bigint,uncompressed_toast_size bigint,uncompressed_index_size bigint,compressed_heap_size bigint,compressed_toast_size bigint,compressed_index_size bigint,numrows_pre_compression bigint,numrows_post_compression bigint) RETURNS regclass LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.create_compressed_chunk(regclass,regclass,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.create_compressed_chunk($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);
END$$
SET search_path TO pg_catalog,pg_temp;

CREATE OR REPLACE FUNCTION _timescaledb_internal.drop_chunk(chunk regclass) RETURNS boolean LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.drop_chunk(regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.drop_chunk($1);
END$$
SET search_path TO pg_catalog,pg_temp;

CREATE OR REPLACE FUNCTION _timescaledb_internal.freeze_chunk(chunk regclass) RETURNS boolean LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.freeze_chunk(regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.freeze_chunk($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.generate_uuid() RETURNS uuid LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.generate_uuid() is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.generate_uuid();
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.get_approx_row_count(relation regclass) RETURNS bigint LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.get_approx_row_count(regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.get_approx_row_count($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.get_compressed_chunk_index_for_recompression(uncompressed_chunk regclass) RETURNS regclass LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.get_compressed_chunk_index_for_recompression(regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.get_compressed_chunk_index_for_recompression($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.get_create_command(table_name name) RETURNS text LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.get_create_command(name) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.get_create_command($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.get_git_commit() RETURNS TABLE(commit_tag TEXT, commit_hash TEXT, commit_time TIMESTAMPTZ) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.get_git_commit() is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN QUERY SELECT * FROM _timescaledb_functions.get_git_commit();
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.get_os_info() RETURNS TABLE(sysname TEXT, version TEXT, release TEXT, version_pretty TEXT) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.get_os_info() is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN QUERY SELECT * FROM _timescaledb_functions.get_os_info();
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.get_partition_for_key(val anyelement) RETURNS integer LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.get_partition_for_key(anyelement) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.get_partition_for_key($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.get_partition_hash(val anyelement) RETURNS integer LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.get_partition_hash(anyelement) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.get_partition_hash($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.hypertable_local_size(schema_name_in name,table_name_in name) RETURNS TABLE ( table_bytes BIGINT, index_bytes BIGINT, toast_bytes BIGINT, total_bytes BIGINT) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.hypertable_local_size(name,name) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN QUERY SELECT * FROM _timescaledb_functions.hypertable_local_size($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.interval_to_usec(chunk_interval interval) RETURNS bigint LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.interval_to_usec(interval) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.interval_to_usec($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.policy_compression_check(config jsonb) RETURNS void LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.policy_compression_check(jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  PERFORM _timescaledb_functions.policy_compression_check($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.policy_job_stat_history_retention(job_id integer,config jsonb) RETURNS integer LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.policy_job_stat_history_retention(integer,jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.policy_job_stat_history_retention($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.policy_job_stat_history_retention_check(config jsonb) RETURNS void LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.policy_job_stat_history_retention_check(jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  PERFORM _timescaledb_functions.policy_job_stat_history_retention_check($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.policy_refresh_continuous_aggregate_check(config jsonb) RETURNS void LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.policy_refresh_continuous_aggregate_check(jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  PERFORM _timescaledb_functions.policy_refresh_continuous_aggregate_check($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.policy_reorder_check(config jsonb) RETURNS void LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.policy_reorder_check(jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  PERFORM _timescaledb_functions.policy_reorder_check($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.policy_retention_check(config jsonb) RETURNS void LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.policy_retention_check(jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  PERFORM _timescaledb_functions.policy_retention_check($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.process_ddl_event() RETURNS event_trigger LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.process_ddl_event() is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.process_ddl_event();
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.range_value_to_pretty(time_value bigint,column_type regtype) RETURNS text LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.range_value_to_pretty(bigint,regtype) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.range_value_to_pretty($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.recompress_chunk_segmentwise(uncompressed_chunk regclass,if_compressed boolean=false) RETURNS regclass LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.recompress_chunk_segmentwise(regclass,boolean) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.recompress_chunk_segmentwise($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.relation_size(relation regclass) RETURNS TABLE (total_size BIGINT, heap_size BIGINT, index_size BIGINT, toast_size BIGINT) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.relation_size(regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN QUERY SELECT * FROM _timescaledb_functions.relation_size($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.restart_background_workers() RETURNS boolean LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.restart_background_workers() is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.restart_background_workers();
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.show_chunk(chunk regclass) RETURNS TABLE(chunk_id INTEGER, hypertable_id INTEGER, schema_name NAME, table_name NAME, relkind "char", slices JSONB) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.show_chunk(regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN QUERY SELECT * FROM _timescaledb_functions.show_chunk($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.start_background_workers() RETURNS boolean LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.start_background_workers() is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.start_background_workers();
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.stop_background_workers() RETURNS boolean LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.stop_background_workers() is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.stop_background_workers();
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.subtract_integer_from_now(hypertable_relid regclass,lag bigint) RETURNS bigint LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.subtract_integer_from_now(regclass,bigint) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.subtract_integer_from_now($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.time_to_internal(time_val anyelement) RETURNS bigint LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.time_to_internal(anyelement) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.time_to_internal($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.to_date(unixtime_us bigint) RETURNS date LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.to_date(bigint) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.to_date($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.to_interval(unixtime_us bigint) RETURNS interval LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.to_interval(bigint) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.to_interval($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.to_timestamp(unixtime_us bigint) RETURNS timestamp with time zone LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.to_timestamp(bigint) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.to_timestamp($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.to_timestamp_without_timezone(unixtime_us bigint) RETURNS timestamp without time zone LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.to_timestamp_without_timezone(bigint) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.to_timestamp_without_timezone($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.to_unix_microseconds(ts timestamp with time zone) RETURNS bigint LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.to_unix_microseconds(timestamp with time zone) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.to_unix_microseconds($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.tsl_loaded() RETURNS boolean LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.tsl_loaded() is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.tsl_loaded();
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE FUNCTION _timescaledb_internal.unfreeze_chunk(chunk regclass) RETURNS boolean LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'function _timescaledb_internal.unfreeze_chunk(regclass) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  RETURN _timescaledb_functions.unfreeze_chunk($1);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE PROCEDURE _timescaledb_internal.policy_compression(job_id integer,config jsonb) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'procedure _timescaledb_internal.policy_compression(integer,jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  CALL _timescaledb_functions.policy_compression($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE PROCEDURE _timescaledb_internal.policy_recompression(job_id integer,config jsonb) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'procedure _timescaledb_internal.policy_recompression(integer,jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  CALL _timescaledb_functions.policy_recompression($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE PROCEDURE _timescaledb_internal.policy_refresh_continuous_aggregate(job_id integer,config jsonb) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'procedure _timescaledb_internal.policy_refresh_continuous_aggregate(integer,jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  CALL _timescaledb_functions.policy_refresh_continuous_aggregate($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE PROCEDURE _timescaledb_internal.policy_reorder(job_id integer,config jsonb) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'procedure _timescaledb_internal.policy_reorder(integer,jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  CALL _timescaledb_functions.policy_reorder($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


CREATE OR REPLACE PROCEDURE _timescaledb_internal.policy_retention(job_id integer,config jsonb) LANGUAGE PLPGSQL AS $$
BEGIN
  IF current_setting('timescaledb.enable_deprecation_warnings', true)::bool THEN
    RAISE WARNING 'procedure _timescaledb_internal.policy_retention(integer,jsonb) is deprecated and has been moved to _timescaledb_functions schema. this compatibility function will be removed in a future version.';
  END IF;
  CALL _timescaledb_functions.policy_retention($1,$2);
END$$
SET search_path TO pg_catalog,pg_temp;


-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

SELECT _timescaledb_functions.restart_background_workers();
-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

COMMENT ON EXTENSION timescaledb IS 'Enables scalable inserts and complex queries for time-series data (Community Edition)';
-- For objects that are newly created, we need to set the initprivs to
-- the initprivs for some table that was created in the installation
-- of the TimescaleDB extension and not as part of any update.
--
-- We chose the "chunk" catalog table for this since that is created
-- in the first version of TimescaleDB and should have the correct
-- initprivs, but we could use any other table that existed in the
-- first installation.
INSERT INTO _timescaledb_internal.saved_privs
     SELECT nspname, relname, relacl,
       (SELECT tmpini FROM _timescaledb_internal.saved_privs
        WHERE tmpnsp = '_timescaledb_catalog' AND tmpname = 'chunk')
       FROM pg_class JOIN pg_namespace ns ON ns.oid = relnamespace
         LEFT JOIN _timescaledb_internal.saved_privs ON tmpnsp = nspname AND tmpname = relname
      WHERE relkind IN ('r', 'v') AND nspname IN ('_timescaledb_catalog', '_timescaledb_config')
        OR nspname = '_timescaledb_internal'
        AND relname IN ('hypertable_chunk_local_size', 'compressed_chunk_stats',
                        'bgw_job_stat', 'bgw_policy_chunk_stats', 'job_errors')
ON CONFLICT DO NOTHING;

-- The above is good enough for tables and views. However sequences need to
-- use the "chunk_id_seq" catalog sequence as a template
INSERT INTO _timescaledb_internal.saved_privs
     SELECT nspname, relname, relacl,
        (SELECT tmpini FROM _timescaledb_internal.saved_privs
	     WHERE tmpnsp = '_timescaledb_catalog' AND tmpname = 'chunk_id_seq')
        FROM pg_class JOIN pg_namespace ns ON ns.oid = relnamespace
		    LEFT JOIN _timescaledb_internal.saved_privs ON tmpnsp = nspname AND tmpname = relname
      WHERE relkind IN ('S') AND nspname IN ('_timescaledb_catalog', '_timescaledb_config')
        OR nspname = '_timescaledb_internal'
        AND relname IN ('hypertable_chunk_local_size', 'compressed_chunk_stats',
                        'bgw_job_stat', 'bgw_policy_chunk_stats')
ON CONFLICT DO NOTHING;

-- We can now copy back saved initprivs.
WITH to_update AS (
     SELECT objoid, tmpini
     FROM pg_class cl JOIN pg_namespace ns ON ns.oid = relnamespace
        JOIN pg_init_privs ip ON ip.objoid = cl.oid AND ip.objsubid = 0
        JOIN _timescaledb_internal.saved_privs ON tmpnsp = nspname AND tmpname = relname)
UPDATE pg_init_privs
   SET initprivs = tmpini
  FROM to_update
 WHERE to_update.objoid = pg_init_privs.objoid
   AND classoid = 'pg_class'::regclass
   AND objsubid = 0;

-- Can only restore permissions on views after they have been rebuilt,
-- so we restore for all types of objects here.
WITH to_update AS (
     SELECT cl.oid, tmpacl
     FROM pg_class cl JOIN pg_namespace ns ON ns.oid = relnamespace
                      JOIN _timescaledb_internal.saved_privs ON tmpnsp = nspname AND tmpname = relname)
UPDATE pg_class cl SET relacl = tmpacl
  FROM to_update WHERE cl.oid = to_update.oid;

DROP TABLE _timescaledb_internal.saved_privs;

