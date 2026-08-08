-- citus--9.5-1--10.0-4
-- This migration file aims to fix the issues with upgrades on clusters without public schema.
-- This file is created by the following command, and some more changes in a separate commit
-- cat citus--9.5-1--10.0-1.sql citus--10.0-1--10.0-2.sql citus--10.0-2--10.0-3.sql > citus--9.5-1--10.0-4.sql
-- copy of citus--9.5-1--10.0-1
DROP FUNCTION pg_catalog.upgrade_to_reference_table(regclass);
DROP FUNCTION IF EXISTS pg_catalog.citus_total_relation_size(regclass);
CREATE FUNCTION pg_catalog.citus_total_relation_size(logicalrelid regclass, fail_on_error boolean default true)
    RETURNS bigint
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_total_relation_size$$;
COMMENT ON FUNCTION pg_catalog.citus_total_relation_size(logicalrelid regclass, boolean)
    IS 'get total disk space used by the specified table';
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
    PERFORM citus_internal.columnar_ensure_objects_exist();
END;
$cppu$;
COMMENT ON FUNCTION pg_catalog.citus_finish_pg_upgrade()
    IS 'perform tasks to restore citus settings from a location that has been prepared before pg_upgrade';
CREATE OR REPLACE FUNCTION pg_catalog.alter_distributed_table(
    table_name regclass, distribution_column text DEFAULT NULL, shard_count int DEFAULT NULL, colocate_with text DEFAULT NULL, cascade_to_colocated boolean DEFAULT NULL)
    RETURNS VOID
    LANGUAGE C
AS 'MODULE_PATHNAME', $$alter_distributed_table$$;
COMMENT ON FUNCTION pg_catalog.alter_distributed_table(
    table_name regclass, distribution_column text, shard_count int, colocate_with text, cascade_to_colocated boolean)
    IS 'alters a distributed table';
CREATE OR REPLACE FUNCTION pg_catalog.alter_table_set_access_method(
    table_name regclass, access_method text)
    RETURNS VOID
    LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$alter_table_set_access_method$$;
COMMENT ON FUNCTION pg_catalog.alter_table_set_access_method(
    table_name regclass, access_method text)
    IS 'alters a table''s access method';
DROP FUNCTION pg_catalog.undistribute_table(regclass);
CREATE OR REPLACE FUNCTION pg_catalog.undistribute_table(
    table_name regclass, cascade_via_foreign_keys boolean default false)
    RETURNS VOID
    LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$undistribute_table$$;
COMMENT ON FUNCTION pg_catalog.undistribute_table(
    table_name regclass, cascade_via_foreign_keys boolean)
    IS 'undistributes a distributed table';
DROP FUNCTION pg_catalog.create_citus_local_table(regclass);
CREATE OR REPLACE FUNCTION pg_catalog.citus_add_local_table_to_metadata(table_name regclass, cascade_via_foreign_keys boolean default false)
 RETURNS void
 LANGUAGE C STRICT
 AS 'MODULE_PATHNAME', $$citus_add_local_table_to_metadata$$;
COMMENT ON FUNCTION pg_catalog.citus_add_local_table_to_metadata(table_name regclass, cascade_via_foreign_keys boolean)
 IS 'create a citus local table';
CREATE FUNCTION pg_catalog.citus_set_coordinator_host(
    host text,
    port integer default current_setting('port')::int,
    node_role noderole default 'primary',
    node_cluster name default 'default')
RETURNS VOID
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_set_coordinator_host$$;
COMMENT ON FUNCTION pg_catalog.citus_set_coordinator_host(text,integer,noderole,name)
IS 'set the host and port of the coordinator';
REVOKE ALL ON FUNCTION pg_catalog.citus_set_coordinator_host(text,int,noderole,name) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_add_node(nodename text,
                                          nodeport integer,
                                          groupid integer default -1,
                                          noderole noderole default 'primary',
                                          nodecluster name default 'default')
  RETURNS INTEGER
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$citus_add_node$$;
COMMENT ON FUNCTION pg_catalog.citus_add_node(nodename text, nodeport integer,
                                              groupid integer, noderole noderole, nodecluster name)
  IS 'add node to the cluster';
REVOKE ALL ON FUNCTION pg_catalog.citus_add_node(text,int,int,noderole,name) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_activate_node(nodename text,
                                               nodeport integer)
    RETURNS INTEGER
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME',$$citus_activate_node$$;
COMMENT ON FUNCTION pg_catalog.citus_activate_node(nodename text, nodeport integer)
    IS 'activate a node which is in the cluster';
REVOKE ALL ON FUNCTION pg_catalog.citus_activate_node(text, integer) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_add_inactive_node(nodename text,
                                                   nodeport integer,
                                        groupid integer default -1,
                                        noderole noderole default 'primary',
                                        nodecluster name default 'default')
  RETURNS INTEGER
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME',$$citus_add_inactive_node$$;
COMMENT ON FUNCTION pg_catalog.citus_add_inactive_node(nodename text,nodeport integer,
                                            groupid integer, noderole noderole,
                                            nodecluster name)
  IS 'prepare node by adding it to pg_dist_node';
REVOKE ALL ON FUNCTION pg_catalog.citus_add_inactive_node(text,int,int,noderole,name) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_add_secondary_node(nodename text,
                                         nodeport integer,
                                         primaryname text,
                                         primaryport integer,
                                         nodecluster name default 'default')
  RETURNS INTEGER
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$citus_add_secondary_node$$;
COMMENT ON FUNCTION pg_catalog.citus_add_secondary_node(nodename text, nodeport integer,
                                             primaryname text, primaryport integer,
                                             nodecluster name)
  IS 'add a secondary node to the cluster';
REVOKE ALL ON FUNCTION pg_catalog.citus_add_secondary_node(text,int,text,int,name) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_disable_node(nodename text, nodeport integer)
 RETURNS void
 LANGUAGE C STRICT
 AS 'MODULE_PATHNAME', $$citus_disable_node$$;
COMMENT ON FUNCTION pg_catalog.citus_disable_node(nodename text, nodeport integer)
 IS 'removes node from the cluster temporarily';
REVOKE ALL ON FUNCTION pg_catalog.citus_disable_node(text,int) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_drain_node(
    nodename text,
    nodeport integer,
    shard_transfer_mode citus.shard_transfer_mode default 'auto',
    rebalance_strategy name default NULL
  )
  RETURNS VOID
  LANGUAGE C
  AS 'MODULE_PATHNAME', $$citus_drain_node$$;
COMMENT ON FUNCTION pg_catalog.citus_drain_node(text,int,citus.shard_transfer_mode,name)
  IS 'mark a node to be drained of data and actually drain it as well';
REVOKE ALL ON FUNCTION pg_catalog.citus_drain_node(text,int,citus.shard_transfer_mode,name) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_remove_node(nodename text, nodeport integer)
 RETURNS void
 LANGUAGE C STRICT
 AS 'MODULE_PATHNAME', $$citus_remove_node$$;
COMMENT ON FUNCTION pg_catalog.citus_remove_node(nodename text, nodeport integer)
 IS 'remove node from the cluster';
REVOKE ALL ON FUNCTION pg_catalog.citus_remove_node(text,int) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_set_node_property(
    nodename text,
    nodeport integer,
    property text,
    value boolean)
  RETURNS VOID
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', 'citus_set_node_property';
COMMENT ON FUNCTION pg_catalog.citus_set_node_property(
    nodename text,
    nodeport integer,
    property text,
    value boolean)
  IS 'set a property of a node in pg_dist_node';
REVOKE ALL ON FUNCTION pg_catalog.citus_set_node_property(
    nodename text,
    nodeport integer,
    property text,
    value boolean)
  FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_unmark_object_distributed(classid oid, objid oid, objsubid int)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_unmark_object_distributed$$;
COMMENT ON FUNCTION pg_catalog.citus_unmark_object_distributed(classid oid, objid oid, objsubid int)
    IS 'remove an object address from citus.pg_dist_object once the object has been deleted';
CREATE FUNCTION pg_catalog.citus_update_node(node_id int,
                                              new_node_name text,
                                              new_node_port int,
                                              force bool DEFAULT false,
                                              lock_cooldown int DEFAULT 10000)
  RETURNS void
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$citus_update_node$$;
COMMENT ON FUNCTION pg_catalog.citus_update_node(node_id int,
                                       new_node_name text,
                                       new_node_port int,
                                       force bool,
                                       lock_cooldown int)
  IS 'change the location of a node. when force => true it will wait lock_cooldown ms before killing competing locks';
REVOKE ALL ON FUNCTION pg_catalog.citus_update_node(int,text,int,bool,int) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_update_shard_statistics(shard_id bigint)
    RETURNS bigint
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_update_shard_statistics$$;
COMMENT ON FUNCTION pg_catalog.citus_update_shard_statistics(bigint)
    IS 'updates shard statistics and returns the updated shard size';
CREATE FUNCTION pg_catalog.citus_update_table_statistics(relation regclass)
RETURNS VOID AS $$
DECLARE
 colocated_tables regclass[];
BEGIN
 SELECT get_colocated_table_array(relation) INTO colocated_tables;
 PERFORM
  master_update_shard_statistics(shardid)
 FROM
  pg_dist_shard
 WHERE
  logicalrelid = ANY (colocated_tables);
END;
$$ LANGUAGE 'plpgsql';
COMMENT ON FUNCTION pg_catalog.citus_update_table_statistics(regclass)
 IS 'updates shard statistics of the given table and its colocated tables';
CREATE FUNCTION pg_catalog.citus_copy_shard_placement(
 shard_id bigint,
 source_node_name text,
 source_node_port integer,
 target_node_name text,
 target_node_port integer,
 do_repair bool DEFAULT true,
 transfer_mode citus.shard_transfer_mode default 'auto')
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_copy_shard_placement$$;
COMMENT ON FUNCTION pg_catalog.citus_copy_shard_placement(shard_id bigint,
 source_node_name text,
 source_node_port integer,
 target_node_name text,
 target_node_port integer,
 do_repair bool,
 shard_transfer_mode citus.shard_transfer_mode)
IS 'copy a shard from the source node to the destination node';
CREATE FUNCTION pg_catalog.citus_move_shard_placement(
 shard_id bigint,
 source_node_name text,
 source_node_port integer,
 target_node_name text,
 target_node_port integer,
 shard_transfer_mode citus.shard_transfer_mode default 'auto')
RETURNS void LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_move_shard_placement$$;
COMMENT ON FUNCTION pg_catalog.citus_move_shard_placement(
 shard_id bigint,
 source_node_name text,
 source_node_port integer,
 target_node_name text,
 target_node_port integer,
 shard_transfer_mode citus.shard_transfer_mode)
IS 'move a shard from a the source node to the destination node';
CREATE OR REPLACE FUNCTION pg_catalog.notify_constraint_dropped()
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$notify_constraint_dropped$$;
CREATE OR REPLACE FUNCTION pg_catalog.citus_drop_trigger()
    RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path = pg_catalog
    AS $cdbdt$
DECLARE
    constraint_event_count INTEGER;
    v_obj record;
    sequence_names text[] := '{}';
    table_colocation_id integer;
    propagate_drop boolean := false;
BEGIN
    FOR v_obj IN SELECT * FROM pg_event_trigger_dropped_objects()
                 WHERE object_type IN ('table', 'foreign table')
    LOOP
        -- first drop the table and metadata on the workers
        -- then drop all the shards on the workers
        -- finally remove the pg_dist_partition entry on the coordinator
        PERFORM master_remove_distributed_table_metadata_from_workers(v_obj.objid, v_obj.schema_name, v_obj.object_name);
        PERFORM citus_drop_all_shards(v_obj.objid, v_obj.schema_name, v_obj.object_name);
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
CREATE OR REPLACE FUNCTION pg_catalog.worker_change_sequence_dependency(
    sequence regclass,
    source_table regclass,
    target_table regclass)
    RETURNS VOID
    LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$worker_change_sequence_dependency$$;
COMMENT ON FUNCTION pg_catalog.worker_change_sequence_dependency(
    sequence regclass,
    source_table regclass,
    target_table regclass)
    IS 'changes sequence''s dependency from source table to target table';
CREATE OR REPLACE FUNCTION pg_catalog.remove_local_tables_from_metadata()
 RETURNS void
 LANGUAGE C STRICT
 AS 'MODULE_PATHNAME', $$remove_local_tables_from_metadata$$;
COMMENT ON FUNCTION pg_catalog.remove_local_tables_from_metadata()
 IS 'undistribute citus local tables that are not chained with any reference tables via foreign keys';
--#include "../../columnar/sql/columnar--9.5-1--10.0-1.sql"
DO $check_columnar$
BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension AS e
             INNER JOIN pg_catalog.pg_depend AS d ON (d.refobjid = e.oid)
             INNER JOIN pg_catalog.pg_proc AS p ON (p.oid = d.objid)
             WHERE e.extname='citus_columnar' and p.proname = 'columnar_handler'
  ) THEN
-- columnar--9.5-1--10.0-1.sql
CREATE SCHEMA columnar;
SET search_path TO columnar;
CREATE SEQUENCE storageid_seq MINVALUE 10000000000 NO CYCLE;
CREATE TABLE options (
    regclass regclass NOT NULL PRIMARY KEY,
    chunk_group_row_limit int NOT NULL,
    stripe_row_limit int NOT NULL,
    compression_level int NOT NULL,
    compression name NOT NULL
) WITH (user_catalog_table = true);
COMMENT ON TABLE options IS 'columnar table specific options, maintained by alter_columnar_table_set';
CREATE TABLE stripe (
    storage_id bigint NOT NULL,
    stripe_num bigint NOT NULL,
    file_offset bigint NOT NULL,
    data_length bigint NOT NULL,
    column_count int NOT NULL,
    chunk_row_count int NOT NULL,
    row_count bigint NOT NULL,
    chunk_group_count int NOT NULL,
    PRIMARY KEY (storage_id, stripe_num)
) WITH (user_catalog_table = true);
COMMENT ON TABLE stripe IS 'Columnar per stripe metadata';
CREATE TABLE chunk_group (
    storage_id bigint NOT NULL,
    stripe_num bigint NOT NULL,
    chunk_group_num int NOT NULL,
    row_count bigint NOT NULL,
    PRIMARY KEY (storage_id, stripe_num, chunk_group_num),
    FOREIGN KEY (storage_id, stripe_num) REFERENCES stripe(storage_id, stripe_num) ON DELETE CASCADE
);
COMMENT ON TABLE chunk_group IS 'Columnar chunk group metadata';
CREATE TABLE chunk (
    storage_id bigint NOT NULL,
    stripe_num bigint NOT NULL,
    attr_num int NOT NULL,
    chunk_group_num int NOT NULL,
    minimum_value bytea,
    maximum_value bytea,
    value_stream_offset bigint NOT NULL,
    value_stream_length bigint NOT NULL,
    exists_stream_offset bigint NOT NULL,
    exists_stream_length bigint NOT NULL,
    value_compression_type int NOT NULL,
    value_compression_level int NOT NULL,
    value_decompressed_length bigint NOT NULL,
    value_count bigint NOT NULL,
    PRIMARY KEY (storage_id, stripe_num, attr_num, chunk_group_num),
    FOREIGN KEY (storage_id, stripe_num, chunk_group_num) REFERENCES chunk_group(storage_id, stripe_num, chunk_group_num) ON DELETE CASCADE
) WITH (user_catalog_table = true);
COMMENT ON TABLE chunk IS 'Columnar per chunk metadata';
DO $proc$
BEGIN
-- from version 12 and up we have support for tableam's if installed on pg11 we can't
-- create the objects here. Instead we rely on citus_finish_pg_upgrade to be called by the
-- user instead to add the missing objects
IF substring(current_Setting('server_version'), '\d+')::int >= 12 THEN
  EXECUTE $$
CREATE OR REPLACE FUNCTION columnar.columnar_handler(internal)
    RETURNS table_am_handler
    LANGUAGE C
AS 'MODULE_PATHNAME', 'columnar_handler';
COMMENT ON FUNCTION columnar.columnar_handler(internal)
    IS 'internal function returning the handler for columnar tables';
-- postgres 11.8 does not support the syntax for table am, also it is seemingly trying
-- to parse the upgrade file and erroring on unknown syntax.
-- normally this section would not execute on postgres 11 anyway. To trick it to pass on
-- 11.8 we wrap the statement in a plpgsql block together with an EXECUTE. This is valid
-- syntax on 11.8 and will execute correctly in 12
DO $create_table_am$
BEGIN
EXECUTE 'CREATE ACCESS METHOD columnar TYPE TABLE HANDLER columnar.columnar_handler';
END $create_table_am$;
CREATE OR REPLACE FUNCTION pg_catalog.alter_columnar_table_set(
    table_name regclass,
    chunk_group_row_limit int DEFAULT NULL,
    stripe_row_limit int DEFAULT NULL,
    compression name DEFAULT null,
    compression_level int DEFAULT NULL)
    RETURNS void
    LANGUAGE C
AS 'MODULE_PATHNAME', 'alter_columnar_table_set';
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
    LANGUAGE C
AS 'MODULE_PATHNAME', 'alter_columnar_table_reset';
COMMENT ON FUNCTION pg_catalog.alter_columnar_table_reset(
    table_name regclass,
    chunk_group_row_limit bool,
    stripe_row_limit bool,
    compression bool,
    compression_level bool)
IS 'reset on or more options on a columnar table to the system defaults';
  $$;
END IF;
END$proc$;
-- citus_internal.columnar_ensure_objects_exist is an internal helper function to create
-- missing objects, anything related to the table access methods.
-- Since the API for table access methods is only available in PG12 we can't create these
-- objects when Citus is installed in PG11. Once citus is installed on PG11 the user can
-- upgrade their database to PG12. Now they require the table access method objects that
-- we couldn't create before.
-- This internal function is called from `citus_finish_pg_upgrade` which the user is
-- required to call after a PG major upgrade.
CREATE OR REPLACE FUNCTION citus_internal.columnar_ensure_objects_exist()
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = pg_catalog
AS $ceoe$
BEGIN
-- when postgres is version 12 or above we need to create the tableam. If the tableam
-- exist we assume all objects have been created.
IF substring(current_Setting('server_version'), '\d+')::int >= 12 THEN
IF NOT EXISTS (SELECT 1 FROM pg_am WHERE amname = 'columnar') THEN
CREATE OR REPLACE FUNCTION columnar.columnar_handler(internal)
    RETURNS table_am_handler
    LANGUAGE C
AS 'MODULE_PATHNAME', 'columnar_handler';
COMMENT ON FUNCTION columnar.columnar_handler(internal)
    IS 'internal function returning the handler for columnar tables';
-- postgres 11.8 does not support the syntax for table am, also it is seemingly trying
-- to parse the upgrade file and erroring on unknown syntax.
-- normally this section would not execute on postgres 11 anyway. To trick it to pass on
-- 11.8 we wrap the statement in a plpgsql block together with an EXECUTE. This is valid
-- syntax on 11.8 and will execute correctly in 12
DO $create_table_am$
BEGIN
EXECUTE 'CREATE ACCESS METHOD columnar TYPE TABLE HANDLER columnar.columnar_handler';
END $create_table_am$;
CREATE OR REPLACE FUNCTION pg_catalog.alter_columnar_table_set(
    table_name regclass,
    chunk_group_row_limit int DEFAULT NULL,
    stripe_row_limit int DEFAULT NULL,
    compression name DEFAULT null,
    compression_level int DEFAULT NULL)
    RETURNS void
    LANGUAGE C
AS 'MODULE_PATHNAME', 'alter_columnar_table_set';
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
    LANGUAGE C
AS 'MODULE_PATHNAME', 'alter_columnar_table_reset';
COMMENT ON FUNCTION pg_catalog.alter_columnar_table_reset(
    table_name regclass,
    chunk_group_row_limit bool,
    stripe_row_limit bool,
    compression bool,
    compression_level bool)
IS 'reset on or more options on a columnar table to the system defaults';
    -- add the missing objects to the extension
    ALTER EXTENSION citus ADD FUNCTION columnar.columnar_handler(internal);
    ALTER EXTENSION citus ADD ACCESS METHOD columnar;
    ALTER EXTENSION citus ADD FUNCTION pg_catalog.alter_columnar_table_set(
        table_name regclass,
        chunk_group_row_limit int,
        stripe_row_limit int,
        compression name,
        compression_level int);
    ALTER EXTENSION citus ADD FUNCTION pg_catalog.alter_columnar_table_reset(
        table_name regclass,
        chunk_group_row_limit bool,
        stripe_row_limit bool,
        compression bool,
        compression_level bool);
END IF;
END IF;
END;
$ceoe$;
COMMENT ON FUNCTION citus_internal.columnar_ensure_objects_exist()
    IS 'internal function to be called by pg_catalog.citus_finish_pg_upgrade responsible for creating the columnar objects';
RESET search_path;
END IF;
END;
$check_columnar$;
CREATE OR REPLACE FUNCTION pg_catalog.time_partition_range(
    table_name regclass,
    OUT lower_bound text,
    OUT upper_bound text)
RETURNS record
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$time_partition_range$$;
COMMENT ON FUNCTION pg_catalog.time_partition_range(regclass)
IS 'returns the start and end of partition boundaries';
CREATE VIEW citus.time_partitions AS
SELECT partrelid AS parent_table, attname AS partition_column, relid AS partition, lower_bound AS from_value, upper_bound AS to_value, amname AS access_method
FROM (
  SELECT partrelid::regclass AS partrelid, attname, c.oid::regclass AS relid, lower_bound, upper_bound, amname
  FROM pg_class c
  JOIN pg_inherits i ON (c.oid = inhrelid)
  JOIN pg_partitioned_table p ON (inhparent = partrelid)
  JOIN pg_attribute a ON (partrelid = attrelid)
  JOIN pg_type t ON (atttypid = t.oid)
  JOIN pg_namespace tn ON (t.typnamespace = tn.oid)
  LEFT JOIN pg_am am ON (c.relam = am.oid),
  pg_catalog.time_partition_range(c.oid)
  WHERE c.relpartbound IS NOT NULL AND p.partstrat = 'r' AND p.partnatts = 1
  AND a.attnum = ANY(partattrs::int2[])
) partitions
ORDER BY partrelid::text, lower_bound;
ALTER VIEW citus.time_partitions SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.time_partitions TO public;
CREATE OR REPLACE PROCEDURE pg_catalog.alter_old_partitions_set_access_method(
  parent_table_name regclass,
  older_than timestamptz,
  new_access_method name)
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
 -- first check whether we can convert all the to_value's to timestamptz
 BEGIN
  PERFORM
  FROM pg_catalog.time_partitions
  WHERE parent_table = parent_table_name
  AND to_value IS NOT NULL
  AND to_value::timestamptz <= older_than
  AND access_method <> new_access_method;
 EXCEPTION WHEN invalid_datetime_format THEN
  RAISE 'partition column of % cannot be cast to a timestamptz', parent_table_name;
 END;
 -- now convert the partitions in separate transactions
    FOR r IN
  SELECT partition, from_value, to_value
  FROM pg_catalog.time_partitions
  WHERE parent_table = parent_table_name
  AND to_value IS NOT NULL
  AND to_value::timestamptz <= older_than
  AND access_method <> new_access_method
  ORDER BY to_value::timestamptz
    LOOP
        RAISE NOTICE 'converting % with start time % and end time %', r.partition, r.from_value, r.to_value;
        PERFORM pg_catalog.alter_table_set_access_method(r.partition, new_access_method);
        COMMIT;
    END LOOP;
END;
$$;
COMMENT ON PROCEDURE pg_catalog.alter_old_partitions_set_access_method(
  parent_table_name regclass,
  older_than timestamptz,
  new_access_method name)
IS 'convert old partitions of a time-partitioned table to a new access method';
ALTER FUNCTION pg_catalog.master_conninfo_cache_invalidate()
RENAME TO citus_conninfo_cache_invalidate;
ALTER FUNCTION pg_catalog.master_dist_local_group_cache_invalidate()
RENAME TO citus_dist_local_group_cache_invalidate;
ALTER FUNCTION pg_catalog.master_dist_node_cache_invalidate()
RENAME TO citus_dist_node_cache_invalidate;
ALTER FUNCTION pg_catalog.master_dist_object_cache_invalidate()
RENAME TO citus_dist_object_cache_invalidate;
ALTER FUNCTION pg_catalog.master_dist_partition_cache_invalidate()
RENAME TO citus_dist_partition_cache_invalidate;
ALTER FUNCTION pg_catalog.master_dist_placement_cache_invalidate()
RENAME TO citus_dist_placement_cache_invalidate;
ALTER FUNCTION pg_catalog.master_dist_shard_cache_invalidate()
RENAME TO citus_dist_shard_cache_invalidate;
CREATE OR REPLACE FUNCTION pg_catalog.citus_conninfo_cache_invalidate()
    RETURNS trigger
    LANGUAGE C
    AS 'MODULE_PATHNAME', $$citus_conninfo_cache_invalidate$$;
COMMENT ON FUNCTION pg_catalog.citus_conninfo_cache_invalidate()
    IS 'register relcache invalidation for changed rows';
CREATE OR REPLACE FUNCTION pg_catalog.citus_dist_local_group_cache_invalidate()
    RETURNS trigger
    LANGUAGE C
    AS 'MODULE_PATHNAME', $$citus_dist_local_group_cache_invalidate$$;
COMMENT ON FUNCTION pg_catalog.citus_dist_local_group_cache_invalidate()
    IS 'register node cache invalidation for changed rows';
CREATE OR REPLACE FUNCTION pg_catalog.citus_dist_node_cache_invalidate()
    RETURNS trigger
    LANGUAGE C
    AS 'MODULE_PATHNAME', $$citus_dist_node_cache_invalidate$$;
COMMENT ON FUNCTION pg_catalog.citus_dist_node_cache_invalidate()
    IS 'register relcache invalidation for changed rows';
CREATE OR REPLACE FUNCTION pg_catalog.citus_dist_object_cache_invalidate()
    RETURNS trigger
    LANGUAGE C
    AS 'MODULE_PATHNAME', $$citus_dist_object_cache_invalidate$$;
COMMENT ON FUNCTION pg_catalog.citus_dist_object_cache_invalidate()
    IS 'register relcache invalidation for changed rows';
CREATE OR REPLACE FUNCTION pg_catalog.citus_dist_partition_cache_invalidate()
    RETURNS trigger
    LANGUAGE C
    AS 'citus', $$citus_dist_partition_cache_invalidate$$;
COMMENT ON FUNCTION pg_catalog.citus_dist_partition_cache_invalidate()
    IS 'register relcache invalidation for changed rows';
CREATE OR REPLACE FUNCTION pg_catalog.citus_dist_placement_cache_invalidate()
    RETURNS trigger
    LANGUAGE C
    AS 'MODULE_PATHNAME', $$citus_dist_placement_cache_invalidate$$;
COMMENT ON FUNCTION pg_catalog.citus_dist_placement_cache_invalidate()
    IS 'register relcache invalidation for changed rows';
CREATE OR REPLACE FUNCTION pg_catalog.citus_dist_shard_cache_invalidate()
    RETURNS trigger
    LANGUAGE C
    AS 'MODULE_PATHNAME', $$citus_dist_shard_cache_invalidate$$;
COMMENT ON FUNCTION pg_catalog.citus_dist_shard_cache_invalidate()
    IS 'register relcache invalidation for changed rows';
ALTER FUNCTION pg_catalog.master_drop_all_shards(regclass, text, text)
RENAME TO citus_drop_all_shards;
DROP FUNCTION pg_catalog.master_modify_multiple_shards(text);
DROP FUNCTION pg_catalog.master_create_distributed_table(regclass, text, citus.distribution_type);
DROP FUNCTION pg_catalog.master_create_worker_shards(text, integer, integer);
DROP FUNCTION pg_catalog.mark_tables_colocated(regclass, regclass[]);
CREATE FUNCTION pg_catalog.citus_shard_sizes(OUT table_name text, OUT size bigint)
  RETURNS SETOF RECORD
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$citus_shard_sizes$$;
 COMMENT ON FUNCTION pg_catalog.citus_shard_sizes(OUT table_name text, OUT size bigint)
     IS 'returns shards sizes across citus cluster';
CREATE OR REPLACE VIEW citus.citus_shards AS
WITH shard_sizes AS (SELECT * FROM pg_catalog.citus_shard_sizes())
SELECT
     pg_dist_shard.logicalrelid AS table_name,
     pg_dist_shard.shardid,
     shard_name(pg_dist_shard.logicalrelid, pg_dist_shard.shardid) as shard_name,
     CASE WHEN partkey IS NOT NULL THEN 'distributed' WHEN repmodel = 't' THEN 'reference' ELSE 'local' END AS citus_table_type,
     colocationid AS colocation_id,
     pg_dist_node.nodename,
     pg_dist_node.nodeport,
     (SELECT size FROM shard_sizes WHERE
       shard_name(pg_dist_shard.logicalrelid, pg_dist_shard.shardid) = table_name
       OR
       'public.' || shard_name(pg_dist_shard.logicalrelid, pg_dist_shard.shardid) = table_name
      LIMIT 1) as shard_size
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
ORDER BY
   pg_dist_shard.logicalrelid::text, shardid
;
ALTER VIEW citus.citus_shards SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_shards TO public;
CREATE FUNCTION pg_catalog.fix_pre_citus10_partitioned_table_constraint_names(table_name regclass)
  RETURNS void
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$fix_pre_citus10_partitioned_table_constraint_names$$;
COMMENT ON FUNCTION pg_catalog.fix_pre_citus10_partitioned_table_constraint_names(table_name regclass)
  IS 'fix constraint names on partition shards';
CREATE OR REPLACE FUNCTION pg_catalog.fix_pre_citus10_partitioned_table_constraint_names()
  RETURNS SETOF regclass
  LANGUAGE plpgsql
  AS $$
DECLARE
 oid regclass;
BEGIN
    FOR oid IN SELECT c.oid
            FROM pg_dist_partition p
            JOIN pg_class c ON p.logicalrelid = c.oid
   JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'p'
  ORDER BY n.nspname, c.relname
    LOOP
        EXECUTE 'SELECT fix_pre_citus10_partitioned_table_constraint_names( ' || quote_literal(oid) || ' )';
        RETURN NEXT oid;
    END LOOP;
    RETURN;
END;
$$;
COMMENT ON FUNCTION pg_catalog.fix_pre_citus10_partitioned_table_constraint_names()
  IS 'fix constraint names on all partition shards';
CREATE FUNCTION pg_catalog.worker_fix_pre_citus10_partitioned_table_constraint_names(table_name regclass,
               shardid bigint,
               constraint_name text)
  RETURNS void
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$worker_fix_pre_citus10_partitioned_table_constraint_names$$;
COMMENT ON FUNCTION pg_catalog.worker_fix_pre_citus10_partitioned_table_constraint_names(table_name regclass,
                shardid bigint,
                constraint_name text)
  IS 'fix constraint names on partition shards on worker nodes';
DROP FUNCTION pg_catalog.citus_dist_stat_activity CASCADE;
CREATE OR REPLACE FUNCTION pg_catalog.citus_dist_stat_activity(OUT query_hostname text, OUT query_hostport int, OUT distributed_query_host_name text, OUT distributed_query_host_port int,
                                                    OUT transaction_number int8, OUT transaction_stamp timestamptz, OUT datid oid, OUT datname name,
                                                    OUT pid int, OUT usesysid oid, OUT usename name, OUT application_name text, OUT client_addr INET,
                                                    OUT client_hostname TEXT, OUT client_port int, OUT backend_start timestamptz, OUT xact_start timestamptz,
                                                    OUT query_start timestamptz, OUT state_change timestamptz, OUT wait_event_type text, OUT wait_event text,
                                                    OUT state text, OUT backend_xid xid, OUT backend_xmin xid, OUT query text, OUT backend_type text)
RETURNS SETOF RECORD
LANGUAGE C STRICT AS 'MODULE_PATHNAME',
$$citus_dist_stat_activity$$;
COMMENT ON FUNCTION pg_catalog.citus_dist_stat_activity(OUT query_hostname text, OUT query_hostport int, OUT distributed_query_host_name text, OUT distributed_query_host_port int,
                                             OUT transaction_number int8, OUT transaction_stamp timestamptz, OUT datid oid, OUT datname name,
                                             OUT pid int, OUT usesysid oid, OUT usename name, OUT application_name text, OUT client_addr INET,
                                             OUT client_hostname TEXT, OUT client_port int, OUT backend_start timestamptz, OUT xact_start timestamptz,
                                             OUT query_start timestamptz, OUT state_change timestamptz, OUT wait_event_type text, OUT wait_event text,
                                             OUT state text, OUT backend_xid xid, OUT backend_xmin xid, OUT query text, OUT backend_type text)
IS 'returns distributed transaction activity on distributed tables';
CREATE VIEW citus.citus_dist_stat_activity AS
SELECT * FROM pg_catalog.citus_dist_stat_activity();
ALTER VIEW citus.citus_dist_stat_activity SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_dist_stat_activity TO PUBLIC;
SET search_path = 'pg_catalog';
CREATE VIEW citus.citus_lock_waits AS
WITH
citus_dist_stat_activity AS
(
  SELECT * FROM citus_dist_stat_activity
),
unique_global_wait_edges AS
(
 SELECT DISTINCT ON(waiting_node_id, waiting_transaction_num, blocking_node_id, blocking_transaction_num) * FROM dump_global_wait_edges()
),
citus_dist_stat_activity_with_node_id AS
(
  SELECT
  citus_dist_stat_activity.*, (CASE citus_dist_stat_activity.distributed_query_host_name WHEN 'coordinator_host' THEN 0 ELSE pg_dist_node.nodeid END) as initiator_node_id
  FROM
  citus_dist_stat_activity LEFT JOIN pg_dist_node
  ON
  citus_dist_stat_activity.distributed_query_host_name = pg_dist_node.nodename AND
  citus_dist_stat_activity.distributed_query_host_port = pg_dist_node.nodeport
)
SELECT
 waiting.pid AS waiting_pid,
 blocking.pid AS blocking_pid,
 waiting.query AS blocked_statement,
 blocking.query AS current_statement_in_blocking_process,
 waiting.initiator_node_id AS waiting_node_id,
 blocking.initiator_node_id AS blocking_node_id,
 waiting.distributed_query_host_name AS waiting_node_name,
 blocking.distributed_query_host_name AS blocking_node_name,
 waiting.distributed_query_host_port AS waiting_node_port,
 blocking.distributed_query_host_port AS blocking_node_port
FROM
 unique_global_wait_edges
JOIN
 citus_dist_stat_activity_with_node_id waiting ON (unique_global_wait_edges.waiting_transaction_num = waiting.transaction_number AND unique_global_wait_edges.waiting_node_id = waiting.initiator_node_id)
JOIN
 citus_dist_stat_activity_with_node_id blocking ON (unique_global_wait_edges.blocking_transaction_num = blocking.transaction_number AND unique_global_wait_edges.blocking_node_id = blocking.initiator_node_id);
ALTER VIEW citus.citus_lock_waits SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_lock_waits TO PUBLIC;
DROP FUNCTION citus_worker_stat_activity CASCADE;
CREATE OR REPLACE FUNCTION citus_worker_stat_activity(OUT query_hostname text, OUT query_hostport int, OUT distributed_query_host_name text, OUT distributed_query_host_port int,
                                                      OUT transaction_number int8, OUT transaction_stamp timestamptz, OUT datid oid, OUT datname name,
                                                      OUT pid int, OUT usesysid oid, OUT usename name, OUT application_name text, OUT client_addr INET,
                                                      OUT client_hostname TEXT, OUT client_port int, OUT backend_start timestamptz, OUT xact_start timestamptz,
                                                      OUT query_start timestamptz, OUT state_change timestamptz, OUT wait_event_type text, OUT wait_event text,
                                                      OUT state text, OUT backend_xid xid, OUT backend_xmin xid, OUT query text, OUT backend_type text)
RETURNS SETOF RECORD
LANGUAGE C STRICT AS 'MODULE_PATHNAME',
$$citus_worker_stat_activity$$;
COMMENT ON FUNCTION citus_worker_stat_activity(OUT query_hostname text, OUT query_hostport int, OUT distributed_query_host_name text, OUT distributed_query_host_port int,
                                               OUT transaction_number int8, OUT transaction_stamp timestamptz, OUT datid oid, OUT datname name,
                                               OUT pid int, OUT usesysid oid, OUT usename name, OUT application_name text, OUT client_addr INET,
                                               OUT client_hostname TEXT, OUT client_port int, OUT backend_start timestamptz, OUT xact_start timestamptz,
                                               OUT query_start timestamptz, OUT state_change timestamptz, OUT wait_event_type text, OUT wait_event text,
                                               OUT state text, OUT backend_xid xid, OUT backend_xmin xid, OUT query text, OUT backend_type text)
IS 'returns distributed transaction activity on shards of distributed tables';
CREATE VIEW citus.citus_worker_stat_activity AS
SELECT * FROM pg_catalog.citus_worker_stat_activity();
ALTER VIEW citus.citus_worker_stat_activity SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_worker_stat_activity TO PUBLIC;
-- copy of citus--10.0-1--10.0-2
--#include "../../columnar/sql/columnar--10.0-1--10.0-2.sql"
DO $check_columnar$
BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension AS e
             INNER JOIN pg_catalog.pg_depend AS d ON (d.refobjid = e.oid)
             INNER JOIN pg_catalog.pg_proc AS p ON (p.oid = d.objid)
             WHERE e.extname='citus_columnar' and p.proname = 'columnar_handler'
  ) THEN
-- columnar--10.0-1--10.0-2.sql
-- grant read access for columnar metadata tables to unprivileged user
GRANT USAGE ON SCHEMA columnar TO PUBLIC;
GRANT SELECT ON ALL tables IN SCHEMA columnar TO PUBLIC ;
END IF;
END;
$check_columnar$;
-- copy of citus--10.0-2--10.0-3
CREATE OR REPLACE FUNCTION pg_catalog.citus_update_table_statistics(relation regclass)
 RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_update_table_statistics$$;
COMMENT ON FUNCTION pg_catalog.citus_update_table_statistics(regclass)
 IS 'updates shard statistics of the given table';
CREATE OR REPLACE FUNCTION master_update_table_statistics(relation regclass)
RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_update_table_statistics$$;
COMMENT ON FUNCTION pg_catalog.master_update_table_statistics(regclass)
 IS 'updates shard statistics of the given table';
CREATE OR REPLACE FUNCTION pg_catalog.citus_get_active_worker_nodes(OUT node_name text, OUT node_port bigint)
    RETURNS SETOF record
    LANGUAGE C STRICT ROWS 100
    AS 'MODULE_PATHNAME', $$citus_get_active_worker_nodes$$;
COMMENT ON FUNCTION pg_catalog.citus_get_active_worker_nodes()
    IS 'fetch set of active worker nodes';
-- copy of citus--10.0-3--10.0-4
-- This migration file aims to fix 2 issues with upgrades on clusters
-- 1. a bug in public schema dependency for citus_tables view.
--
-- Users who do not have public schema in their clusters were unable to upgrade
-- to Citus 10.x due to the citus_tables view that used to be created in public
-- schema
DO $$
declare
citus_tables_create_query text;
BEGIN
citus_tables_create_query=$CTCQ$
    CREATE OR REPLACE VIEW %I.citus_tables AS
    SELECT
        logicalrelid AS table_name,
        CASE WHEN partkey IS NOT NULL THEN 'distributed' ELSE 'reference' END AS citus_table_type,
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
        partkey IS NOT NULL OR repmodel = 't'
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
-- 2. a bug in our PG upgrade functions
--
-- Users who took the 9.5-2--10.0-1 upgrade path already have the fix, but users
-- who took the 9.5-1--10.0-1 upgrade path do not. Hence, we repeat the CREATE OR
-- REPLACE from the 9.5-2 definition for citus_prepare_pg_upgrade.
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
        minimum_threshold
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
    PERFORM citus_internal.columnar_ensure_objects_exist();
END;
$cppu$;
COMMENT ON FUNCTION pg_catalog.citus_finish_pg_upgrade()
    IS 'perform tasks to restore citus settings from a location that has been prepared before pg_upgrade';
RESET search_path;
