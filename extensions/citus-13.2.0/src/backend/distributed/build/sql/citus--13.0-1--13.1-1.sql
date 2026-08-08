-- citus--13.0-1--13.1-1
-- bump version to 13.1-1
--
-- citus_internal.database_command run given database command without transaction block restriction.
CREATE OR REPLACE FUNCTION citus_internal.database_command(command text)
 RETURNS void
 LANGUAGE C
 VOLATILE
AS 'MODULE_PATHNAME', $$citus_internal_database_command$$;
COMMENT ON FUNCTION citus_internal.database_command(text) IS
 'run a database command without transaction block restrictions';
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
            minimum_threshold,
            improvement_threshold
        ) VALUES (
            name,
            shard_cost_function,
            node_capacity_function,
            shard_allowed_on_node_function,
            default_threshold,
            minimum_threshold,
            improvement_threshold
        );
    $$ LANGUAGE sql;
COMMENT ON FUNCTION pg_catalog.citus_add_rebalance_strategy(name,regproc,regproc,regproc,float4, float4, float4)
  IS 'adds a new rebalance strategy which can be used when rebalancing shards or draining nodes';
DROP FUNCTION pg_catalog.citus_unmark_object_distributed(oid, oid, int);
CREATE FUNCTION pg_catalog.citus_unmark_object_distributed(classid oid, objid oid, objsubid int, checkobjectexistence boolean DEFAULT true)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_unmark_object_distributed$$;
COMMENT ON FUNCTION pg_catalog.citus_unmark_object_distributed(classid oid, objid oid, objsubid int, checkobjectexistence boolean)
    IS 'Removes an object from citus.pg_dist_object after deletion. If checkobjectexistence is true, object existence check performed.'
       'Otherwise, object existence check is skipped.';
ALTER TABLE pg_catalog.pg_dist_transaction ADD COLUMN outer_xid xid8;
CREATE OR REPLACE FUNCTION citus_internal.acquire_citus_advisory_object_class_lock(objectClass int, qualifiedObjectName cstring)
 RETURNS void
 LANGUAGE C
 VOLATILE
AS 'MODULE_PATHNAME', $$citus_internal_acquire_citus_advisory_object_class_lock$$;
GRANT USAGE ON SCHEMA citus_internal TO PUBLIC;
REVOKE ALL ON FUNCTION citus_internal.find_groupid_for_node FROM PUBLIC;
REVOKE ALL ON FUNCTION citus_internal.pg_dist_node_trigger_func FROM PUBLIC;
REVOKE ALL ON FUNCTION citus_internal.pg_dist_rebalance_strategy_trigger_func FROM PUBLIC;
REVOKE ALL ON FUNCTION citus_internal.pg_dist_shard_placement_trigger_func FROM PUBLIC;
REVOKE ALL ON FUNCTION citus_internal.refresh_isolation_tester_prepared_statement FROM PUBLIC;
REVOKE ALL ON FUNCTION citus_internal.replace_isolation_tester_func FROM PUBLIC;
REVOKE ALL ON FUNCTION citus_internal.restore_isolation_tester_func FROM PUBLIC;
CREATE OR REPLACE FUNCTION citus_internal.add_colocation_metadata(
       colocation_id int,
                            shard_count int,
                            replication_factor int,
       distribution_column_type regtype,
                            distribution_column_collation oid)
    RETURNS void
    LANGUAGE C
    STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_add_colocation_metadata$$;
COMMENT ON FUNCTION citus_internal.add_colocation_metadata(int,int,int,regtype,oid) IS
    'Inserts a co-location group into pg_dist_colocation';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_colocation_metadata(
       colocation_id int,
                            shard_count int,
                            replication_factor int,
       distribution_column_type regtype,
                            distribution_column_collation oid)
    RETURNS void
    LANGUAGE C
    STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_add_colocation_metadata(int,int,int,regtype,oid) IS
    'Inserts a co-location group into pg_dist_colocation';
CREATE OR REPLACE FUNCTION citus_internal.add_object_metadata(
       typeText text,
                            objNames text[],
                            objArgs text[],
       distribution_argument_index int,
                            colocationid int,
                            force_delegation bool)
    RETURNS void
    LANGUAGE C
    STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_add_object_metadata$$;
COMMENT ON FUNCTION citus_internal.add_object_metadata(text,text[],text[],int,int,bool) IS
    'Inserts distributed object into pg_dist_object';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_object_metadata(
       typeText text,
                            objNames text[],
                            objArgs text[],
       distribution_argument_index int,
                            colocationid int,
                            force_delegation bool)
    RETURNS void
    LANGUAGE C
    STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_add_object_metadata(text,text[],text[],int,int,bool) IS
    'Inserts distributed object into pg_dist_object';
CREATE OR REPLACE FUNCTION citus_internal.add_partition_metadata(
       relation_id regclass, distribution_method "char",
       distribution_column text, colocation_id integer,
       replication_model "char")
    RETURNS void
    LANGUAGE C
    AS 'MODULE_PATHNAME', $$citus_internal_add_partition_metadata$$;
COMMENT ON FUNCTION citus_internal.add_partition_metadata(regclass, "char", text, integer, "char") IS
    'Inserts into pg_dist_partition with user checks';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_partition_metadata(
       relation_id regclass, distribution_method "char",
       distribution_column text, colocation_id integer,
       replication_model "char")
    RETURNS void
    LANGUAGE C
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_add_partition_metadata(regclass, "char", text, integer, "char") IS
    'Inserts into pg_dist_partition with user checks';
-- create a new function, without shardstate
CREATE OR REPLACE FUNCTION citus_internal.add_placement_metadata(
       shard_id bigint,
       shard_length bigint, group_id integer,
       placement_id bigint)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_add_placement_metadata$$;
COMMENT ON FUNCTION citus_internal.add_placement_metadata(bigint, bigint, integer, bigint) IS
    'Inserts into pg_dist_shard_placement with user checks';
-- create a new function, without shardstate
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_placement_metadata(
       shard_id bigint,
       shard_length bigint, group_id integer,
       placement_id bigint)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_add_placement_metadata$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_add_placement_metadata(bigint, bigint, integer, bigint) IS
    'Inserts into pg_dist_shard_placement with user checks';
-- replace the old one so it would call the old C function with shard_state
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_placement_metadata(
       shard_id bigint, shard_state integer,
       shard_length bigint, group_id integer,
       placement_id bigint)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_add_placement_metadata_legacy$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_add_placement_metadata(bigint, integer, bigint, integer, bigint) IS
    'Inserts into pg_dist_shard_placement with user checks';
CREATE OR REPLACE FUNCTION citus_internal.add_shard_metadata(
       relation_id regclass, shard_id bigint,
       storage_type "char", shard_min_value text,
       shard_max_value text
       )
    RETURNS void
    LANGUAGE C
    AS 'MODULE_PATHNAME', $$citus_internal_add_shard_metadata$$;
COMMENT ON FUNCTION citus_internal.add_shard_metadata(regclass, bigint, "char", text, text) IS
    'Inserts into pg_dist_shard with user checks';
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
CREATE OR REPLACE FUNCTION citus_internal.add_tenant_schema(schema_id Oid, colocation_id int)
    RETURNS void
    LANGUAGE C
    VOLATILE
    AS 'MODULE_PATHNAME', $$citus_internal_add_tenant_schema$$;
COMMENT ON FUNCTION citus_internal.add_tenant_schema(Oid, int) IS
    'insert given tenant schema into pg_dist_schema with given colocation id';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_add_tenant_schema(schema_id Oid, colocation_id int)
    RETURNS void
    LANGUAGE C
    VOLATILE
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_add_tenant_schema(Oid, int) IS
    'insert given tenant schema into pg_dist_schema with given colocation id';
CREATE OR REPLACE FUNCTION citus_internal.adjust_local_clock_to_remote(pg_catalog.cluster_clock)
    RETURNS void
    LANGUAGE C STABLE PARALLEL SAFE STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_adjust_local_clock_to_remote$$;
COMMENT ON FUNCTION citus_internal.adjust_local_clock_to_remote(pg_catalog.cluster_clock)
    IS 'Internal UDF used to adjust the local clock to the maximum of nodes in the cluster';
REVOKE ALL ON FUNCTION citus_internal.adjust_local_clock_to_remote(pg_catalog.cluster_clock) FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_adjust_local_clock_to_remote(pg_catalog.cluster_clock)
    RETURNS void
    LANGUAGE C STABLE PARALLEL SAFE STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_adjust_local_clock_to_remote$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_adjust_local_clock_to_remote(pg_catalog.cluster_clock)
    IS 'Internal UDF used to adjust the local clock to the maximum of nodes in the cluster';
REVOKE ALL ON FUNCTION pg_catalog.citus_internal_adjust_local_clock_to_remote(pg_catalog.cluster_clock) FROM PUBLIC;
CREATE OR REPLACE FUNCTION citus_internal.delete_colocation_metadata(
       colocation_id int)
    RETURNS void
    LANGUAGE C
    STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_delete_colocation_metadata$$;
COMMENT ON FUNCTION citus_internal.delete_colocation_metadata(int) IS
    'deletes a co-location group from pg_dist_colocation';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_delete_colocation_metadata(
       colocation_id int)
    RETURNS void
    LANGUAGE C
    STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_delete_colocation_metadata(int) IS
    'deletes a co-location group from pg_dist_colocation';
CREATE OR REPLACE FUNCTION citus_internal.delete_partition_metadata(table_name regclass)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_delete_partition_metadata$$;
COMMENT ON FUNCTION citus_internal.delete_partition_metadata(regclass) IS
    'Deletes a row from pg_dist_partition with table ownership checks';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_delete_partition_metadata(table_name regclass)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_delete_partition_metadata(regclass) IS
    'Deletes a row from pg_dist_partition with table ownership checks';
CREATE OR REPLACE FUNCTION citus_internal.delete_placement_metadata(
    placement_id bigint)
RETURNS void
LANGUAGE C
VOLATILE
AS 'MODULE_PATHNAME',
$$citus_internal_delete_placement_metadata$$;
COMMENT ON FUNCTION citus_internal.delete_placement_metadata(bigint)
    IS 'Delete placement with given id from pg_dist_placement metadata table.';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_delete_placement_metadata(
    placement_id bigint)
RETURNS void
LANGUAGE C
VOLATILE
AS 'MODULE_PATHNAME',
$$citus_internal_delete_placement_metadata$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_delete_placement_metadata(bigint)
    IS 'Delete placement with given id from pg_dist_placement metadata table.';
CREATE OR REPLACE FUNCTION citus_internal.delete_shard_metadata(shard_id bigint)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_delete_shard_metadata$$;
COMMENT ON FUNCTION citus_internal.delete_shard_metadata(bigint) IS
    'Deletes rows from pg_dist_shard and pg_dist_shard_placement with user checks';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_delete_shard_metadata(shard_id bigint)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_delete_shard_metadata(bigint) IS
    'Deletes rows from pg_dist_shard and pg_dist_shard_placement with user checks';
CREATE OR REPLACE FUNCTION citus_internal.delete_tenant_schema(schema_id Oid)
    RETURNS void
    LANGUAGE C
    VOLATILE
    AS 'MODULE_PATHNAME', $$citus_internal_delete_tenant_schema$$;
COMMENT ON FUNCTION citus_internal.delete_tenant_schema(Oid) IS
    'delete given tenant schema from pg_dist_schema';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_delete_tenant_schema(schema_id Oid)
    RETURNS void
    LANGUAGE C
    VOLATILE
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_delete_tenant_schema(Oid) IS
    'delete given tenant schema from pg_dist_schema';
CREATE OR REPLACE FUNCTION citus_internal.local_blocked_processes(
      OUT waiting_global_pid int8,
                    OUT waiting_pid int4,
                    OUT waiting_node_id int4,
                    OUT waiting_transaction_num int8,
                    OUT waiting_transaction_stamp timestamptz,
                    OUT blocking_global_pid int8,
                    OUT blocking_pid int4,
                    OUT blocking_node_id int4,
                    OUT blocking_transaction_num int8,
                    OUT blocking_transaction_stamp timestamptz,
                    OUT blocking_transaction_waiting bool)
RETURNS SETOF RECORD
LANGUAGE C STRICT
AS $$MODULE_PATHNAME$$, $$citus_internal_local_blocked_processes$$;
COMMENT ON FUNCTION citus_internal.local_blocked_processes()
IS 'returns all local lock wait chains, that start from any citus backend';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_local_blocked_processes(
      OUT waiting_global_pid int8,
                    OUT waiting_pid int4,
                    OUT waiting_node_id int4,
                    OUT waiting_transaction_num int8,
                    OUT waiting_transaction_stamp timestamptz,
                    OUT blocking_global_pid int8,
                    OUT blocking_pid int4,
                    OUT blocking_node_id int4,
                    OUT blocking_transaction_num int8,
                    OUT blocking_transaction_stamp timestamptz,
                    OUT blocking_transaction_waiting bool)
RETURNS SETOF RECORD
LANGUAGE C STRICT
AS $$MODULE_PATHNAME$$, $$citus_internal_local_blocked_processes$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_local_blocked_processes()
IS 'returns all local lock wait chains, that start from any citus backend';
CREATE OR REPLACE FUNCTION citus_internal.global_blocked_processes(
    OUT waiting_global_pid int8,
                    OUT waiting_pid int4,
                    OUT waiting_node_id int4,
                    OUT waiting_transaction_num int8,
                    OUT waiting_transaction_stamp timestamptz,
    OUT blocking_global_pid int8,
                    OUT blocking_pid int4,
                    OUT blocking_node_id int4,
                    OUT blocking_transaction_num int8,
                    OUT blocking_transaction_stamp timestamptz,
                    OUT blocking_transaction_waiting bool)
RETURNS SETOF RECORD
LANGUAGE C STRICT
AS $$MODULE_PATHNAME$$, $$citus_internal_global_blocked_processes$$;
COMMENT ON FUNCTION citus_internal.global_blocked_processes()
IS 'returns a global list of blocked backends originating from this node';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_global_blocked_processes(
    OUT waiting_global_pid int8,
                    OUT waiting_pid int4,
                    OUT waiting_node_id int4,
                    OUT waiting_transaction_num int8,
                    OUT waiting_transaction_stamp timestamptz,
    OUT blocking_global_pid int8,
                    OUT blocking_pid int4,
                    OUT blocking_node_id int4,
                    OUT blocking_transaction_num int8,
                    OUT blocking_transaction_stamp timestamptz,
                    OUT blocking_transaction_waiting bool)
RETURNS SETOF RECORD
LANGUAGE C STRICT
AS $$MODULE_PATHNAME$$, $$citus_internal_global_blocked_processes$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_global_blocked_processes()
IS 'returns a global list of blocked backends originating from this node';
DROP FUNCTION pg_catalog.citus_blocking_pids;
CREATE FUNCTION pg_catalog.citus_blocking_pids(pBlockedPid integer)
RETURNS int4[] AS $$
  DECLARE
    mLocalBlockingPids int4[];
    mRemoteBlockingPids int4[];
    mLocalGlobalPid int8;
  BEGIN
    SELECT pg_catalog.old_pg_blocking_pids(pBlockedPid) INTO mLocalBlockingPids;
    IF (array_length(mLocalBlockingPids, 1) > 0) THEN
      RETURN mLocalBlockingPids;
    END IF;
    -- pg says we're not blocked locally; check whether we're blocked globally.
    SELECT global_pid INTO mLocalGlobalPid
      FROM get_all_active_transactions() WHERE process_id = pBlockedPid;
    SELECT array_agg(global_pid) INTO mRemoteBlockingPids FROM (
      WITH activeTransactions AS (
        SELECT global_pid FROM get_all_active_transactions()
      ), blockingTransactions AS (
        SELECT blocking_global_pid FROM citus_internal.global_blocked_processes()
        WHERE waiting_global_pid = mLocalGlobalPid
      )
      SELECT activeTransactions.global_pid FROM activeTransactions, blockingTransactions
      WHERE activeTransactions.global_pid = blockingTransactions.blocking_global_pid
    ) AS sub;
    RETURN mRemoteBlockingPids;
  END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION citus_blocking_pids(integer) FROM PUBLIC;
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
    -- We convert the blocking_global_pid to a regular pid and only look at
    -- blocks caused by the interesting pids, or the workerProcessPid. If we
    -- don't do that we might find unrelated blocks caused by some random
    -- other processes that are not involved in this isolation test. Because we
    -- run our isolation tests on a single physical machine, the PID part of
    -- the GPID is known to be unique within the whole cluster.
    RETURN EXISTS (
      SELECT 1 FROM citus_internal.global_blocked_processes()
        WHERE waiting_global_pid = mBlockedGlobalPid
        AND (
          citus_pid_for_gpid(blocking_global_pid) in (
              select * from unnest(pInterestingPids)
          )
          OR citus_pid_for_gpid(blocking_global_pid) = workerProcessId
        )
    );
  END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION citus_isolation_test_session_is_blocked(integer,integer[]) FROM PUBLIC;
DROP VIEW IF EXISTS pg_catalog.citus_lock_waits;
SET search_path = 'pg_catalog';
CREATE VIEW citus.citus_lock_waits AS
WITH
unique_global_wait_edges_with_calculated_gpids AS (
SELECT
   -- if global_pid is NULL, it is most likely that a backend is blocked on a DDL
   -- also for legacy reasons citus_internal.global_blocked_processes() returns groupId, we replace that with nodeIds
   case WHEN waiting_global_pid !=0 THEN waiting_global_pid ELSE citus_calculate_gpid(get_nodeid_for_groupid(waiting_node_id), waiting_pid) END waiting_global_pid,
   case WHEN blocking_global_pid !=0 THEN blocking_global_pid ELSE citus_calculate_gpid(get_nodeid_for_groupid(blocking_node_id), blocking_pid) END blocking_global_pid,
   -- citus_internal.global_blocked_processes returns groupId, we replace it here with actual
   -- nodeId to be consisten with the other views
   get_nodeid_for_groupid(blocking_node_id) as blocking_node_id,
   get_nodeid_for_groupid(waiting_node_id) as waiting_node_id,
   blocking_transaction_waiting
   FROM citus_internal.global_blocked_processes()
),
unique_global_wait_edges AS
(
 SELECT DISTINCT ON(waiting_global_pid, blocking_global_pid) * FROM unique_global_wait_edges_with_calculated_gpids
),
citus_dist_stat_activity_with_calculated_gpids AS
(
 -- if global_pid is NULL, it is most likely that a backend is blocked on a DDL
 SELECT CASE WHEN global_pid != 0 THEN global_pid ELSE citus_calculate_gpid(nodeid, pid) END global_pid, nodeid, pid, query FROM citus_dist_stat_activity
)
SELECT
 waiting.global_pid as waiting_gpid,
 blocking.global_pid as blocking_gpid,
 waiting.query AS blocked_statement,
 blocking.query AS current_statement_in_blocking_process,
 waiting.nodeid AS waiting_nodeid,
 blocking.nodeid AS blocking_nodeid
FROM
 unique_global_wait_edges
  JOIN
 citus_dist_stat_activity_with_calculated_gpids waiting ON (unique_global_wait_edges.waiting_global_pid = waiting.global_pid)
  JOIN
 citus_dist_stat_activity_with_calculated_gpids blocking ON (unique_global_wait_edges.blocking_global_pid = blocking.global_pid);
ALTER VIEW citus.citus_lock_waits SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_lock_waits TO PUBLIC;
RESET search_path;
CREATE OR REPLACE FUNCTION citus_internal.mark_node_not_synced(parent_pid int, nodeid int)
    RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_mark_node_not_synced$$;
COMMENT ON FUNCTION citus_internal.mark_node_not_synced(int, int)
    IS 'marks given node not synced by unsetting metadatasynced column at the start of the nontransactional sync.';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_mark_node_not_synced(parent_pid int, nodeid int)
    RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_mark_node_not_synced$$;
COMMENT ON FUNCTION citus_internal_mark_node_not_synced(int, int)
    IS 'marks given node not synced by unsetting metadatasynced column at the start of the nontransactional sync.';
CREATE OR REPLACE FUNCTION citus_internal.unregister_tenant_schema_globally(schema_id Oid, schema_name text)
    RETURNS void
    LANGUAGE C
    VOLATILE
    AS 'MODULE_PATHNAME', $$citus_internal_unregister_tenant_schema_globally$$;
COMMENT ON FUNCTION citus_internal.unregister_tenant_schema_globally(schema_id Oid, schema_name text) IS
    'Delete a tenant schema and the corresponding colocation group from metadata tables.';
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
            PERFORM citus_internal.unregister_tenant_schema_globally(v_obj.objid, v_obj.object_name);
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
CREATE OR REPLACE FUNCTION citus_internal.update_none_dist_table_metadata(
    relation_id oid,
    replication_model "char",
    colocation_id bigint,
    auto_converted boolean)
RETURNS void
LANGUAGE C
VOLATILE
AS 'MODULE_PATHNAME', $$citus_internal_update_none_dist_table_metadata$$;
COMMENT ON FUNCTION citus_internal.update_none_dist_table_metadata(oid, "char", bigint, boolean)
    IS 'Update pg_dist_partition metadata table for given none-distributed table, to convert it to another type of none-distributed table.';
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
CREATE OR REPLACE FUNCTION citus_internal.update_placement_metadata(
       shard_id bigint, source_group_id integer,
       target_group_id integer)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_update_placement_metadata$$;
COMMENT ON FUNCTION citus_internal.update_placement_metadata(bigint, integer, integer) IS
    'Updates into pg_dist_placement with user checks';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_update_placement_metadata(
       shard_id bigint, source_group_id integer,
       target_group_id integer)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_update_placement_metadata(bigint, integer, integer) IS
    'Updates into pg_dist_placement with user checks';
CREATE OR REPLACE FUNCTION citus_internal.update_relation_colocation(relation_id Oid, target_colocation_id int)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_update_relation_colocation$$;
COMMENT ON FUNCTION citus_internal.update_relation_colocation(oid, int) IS
    'Updates colocationId field of pg_dist_partition for the relation_id';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_update_relation_colocation(relation_id Oid, target_colocation_id int)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_update_relation_colocation(oid, int) IS
    'Updates colocationId field of pg_dist_partition for the relation_id';
CREATE OR REPLACE FUNCTION citus_internal.start_replication_origin_tracking()
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_internal_start_replication_origin_tracking$$;
COMMENT ON FUNCTION citus_internal.start_replication_origin_tracking()
    IS 'To start replication origin tracking for skipping publishing of duplicated events during internal data movements for CDC';
CREATE OR REPLACE FUNCTION citus_internal.stop_replication_origin_tracking()
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_internal_stop_replication_origin_tracking$$;
COMMENT ON FUNCTION citus_internal.stop_replication_origin_tracking()
    IS 'To stop replication origin tracking for skipping publishing of duplicated events during internal data movements for CDC';
CREATE OR REPLACE FUNCTION citus_internal.is_replication_origin_tracking_active()
RETURNS boolean
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_internal_is_replication_origin_tracking_active$$;
COMMENT ON FUNCTION citus_internal.is_replication_origin_tracking_active()
    IS 'To check if replication origin tracking is active for skipping publishing of duplicated events during internal data movements for CDC';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_start_replication_origin_tracking()
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_internal_start_replication_origin_tracking$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_start_replication_origin_tracking()
    IS 'To start replication origin tracking for skipping publishing of duplicated events during internal data movements for CDC';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_stop_replication_origin_tracking()
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_internal_stop_replication_origin_tracking$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_stop_replication_origin_tracking()
    IS 'To stop replication origin tracking for skipping publishing of duplicated events during internal data movements for CDC';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_is_replication_origin_tracking_active()
RETURNS boolean
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_internal_is_replication_origin_tracking_active$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_is_replication_origin_tracking_active()
    IS 'To check if replication origin tracking is active for skipping publishing of duplicated events during internal data movements for CDC';
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
CREATE FUNCTION pg_catalog.citus_is_primary_node()
 RETURNS bool
 LANGUAGE c
 STRICT
AS 'MODULE_PATHNAME', $$citus_is_primary_node$$;
COMMENT ON FUNCTION pg_catalog.citus_is_primary_node()
 IS 'returns whether the current node is the primary node in the group';
-- See the comments for the function in
-- src/backend/distributed/stats/stat_counters.c for more details.
CREATE OR REPLACE FUNCTION pg_catalog.citus_stat_counters(
 database_id oid DEFAULT 0,
 -- must always be the first column or you should accordingly update
 -- StoreDatabaseStatsIntoTupStore() function in src/backend/distributed/stats/stat_counters.c
 OUT database_id oid,
 -- Following stat counter columns must be in the same order as the
 -- StatType enum defined in src/include/distributed/stats/stat_counters.h
 OUT connection_establishment_succeeded bigint,
 OUT connection_establishment_failed bigint,
 OUT connection_reused bigint,
 OUT query_execution_single_shard bigint,
 OUT query_execution_multi_shard bigint,
 -- must always be the last column or you should accordingly update
 -- StoreDatabaseStatsIntoTupStore() function in src/backend/distributed/stats/stat_counters.c
 OUT stats_reset timestamp with time zone
)
RETURNS SETOF RECORD
LANGUAGE C STRICT VOLATILE PARALLEL SAFE
AS 'MODULE_PATHNAME', $$citus_stat_counters$$;
COMMENT ON FUNCTION pg_catalog.citus_stat_counters(oid) IS 'Returns Citus stat counters for the given database OID, or for all databases if 0 is passed. Includes only databases with at least one connection since last restart, including dropped ones.';
-- returns the stat counters for all the databases in local node
CREATE VIEW citus.citus_stat_counters AS
SELECT pg_database.oid,
    pg_database.datname as name,
    -- We always COALESCE the counters to 0 because the LEFT JOIN
    -- will bring the databases that have never been connected to
    -- since the last restart with NULL counters, but we want to
    -- show them with 0 counters in the view.
    COALESCE(citus_stat_counters.connection_establishment_succeeded, 0) as connection_establishment_succeeded,
    COALESCE(citus_stat_counters.connection_establishment_failed, 0) as connection_establishment_failed,
    COALESCE(citus_stat_counters.connection_reused, 0) as connection_reused,
    COALESCE(citus_stat_counters.query_execution_single_shard, 0) as query_execution_single_shard,
    COALESCE(citus_stat_counters.query_execution_multi_shard, 0) as query_execution_multi_shard,
    citus_stat_counters.stats_reset
FROM pg_catalog.pg_database
LEFT JOIN (SELECT (pg_catalog.citus_stat_counters(0)).*) citus_stat_counters
ON (oid = database_id);
ALTER VIEW citus.citus_stat_counters SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_stat_counters TO PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_stat_counters_reset(database_oid oid DEFAULT 0)
RETURNS VOID
LANGUAGE C STRICT PARALLEL SAFE
AS 'MODULE_PATHNAME', $$citus_stat_counters_reset$$;
COMMENT ON FUNCTION pg_catalog.citus_stat_counters_reset(oid) IS 'Resets Citus stat counters for the given database OID or for the current database if nothing or 0 is provided.';
-- Rather than using explicit superuser() check in the function, we use
-- the GRANT system to REVOKE access to it when creating the extension.
-- Administrators can later change who can access it, or leave them as
-- only available to superuser / database cluster owner, if they choose.
REVOKE ALL ON FUNCTION pg_catalog.citus_stat_counters_reset(oid) FROM PUBLIC;
SET search_path = 'pg_catalog';
DROP VIEW IF EXISTS pg_catalog.citus_nodes;
CREATE OR REPLACE VIEW citus.citus_nodes AS
SELECT
    nodename,
    nodeport,
    CASE
        WHEN groupid = 0 THEN 'coordinator'
        ELSE 'worker'
    END AS role,
    isactive AS active
FROM pg_dist_node;
ALTER VIEW citus.citus_nodes SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_nodes TO PUBLIC;
RESET search_path;
-- Since shard_name/13.1-1.sql first drops the function and then creates it, we first
-- need to drop citus_shards view since that view depends on this function. And immediately
-- after creating the function, we recreate citus_shards view again.
DROP VIEW pg_catalog.citus_shards;
-- skip_qualify_public is set to true by default just for backward compatibility
DROP FUNCTION pg_catalog.shard_name(object_name regclass, shard_id bigint);
CREATE FUNCTION pg_catalog.shard_name(object_name regclass, shard_id bigint, skip_qualify_public boolean DEFAULT true)
    RETURNS text
    LANGUAGE C STABLE STRICT
    AS 'MODULE_PATHNAME', $$shard_name$$;
COMMENT ON FUNCTION pg_catalog.shard_name(object_name regclass, shard_id bigint, skip_qualify_public boolean)
    IS 'returns schema-qualified, shard-extended identifier of object name';
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
