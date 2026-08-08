-- citus--10.2-5--11.0-1
-- bump version to 11.0-1
DROP FUNCTION pg_catalog.citus_disable_node(nodename text, nodeport integer);
CREATE FUNCTION pg_catalog.citus_disable_node(nodename text, nodeport integer, force bool default false)
 RETURNS void
 LANGUAGE C STRICT
 AS 'MODULE_PATHNAME', $$citus_disable_node$$;
COMMENT ON FUNCTION pg_catalog.citus_disable_node(nodename text, nodeport integer, force bool)
 IS 'removes node from the cluster temporarily';
REVOKE ALL ON FUNCTION pg_catalog.citus_disable_node(text,int, bool) FROM PUBLIC;
DROP FUNCTION pg_catalog.create_distributed_function(regprocedure, text, text);
CREATE OR REPLACE FUNCTION pg_catalog.create_distributed_function(function_name regprocedure,
             distribution_arg_name text DEFAULT NULL,
             colocate_with text DEFAULT 'default',
             force_delegation bool DEFAULT NULL)
  RETURNS void
  LANGUAGE C CALLED ON NULL INPUT
  AS 'MODULE_PATHNAME', $$create_distributed_function$$;
COMMENT ON FUNCTION pg_catalog.create_distributed_function(function_name regprocedure,
      distribution_arg_name text,
      colocate_with text,
      force_delegation bool)
  IS 'creates a distributed function';
CREATE FUNCTION pg_catalog.citus_check_connection_to_node (
    nodename text,
    nodeport integer DEFAULT 5432)
    RETURNS bool
    LANGUAGE C
    STRICT
    AS 'MODULE_PATHNAME', $$citus_check_connection_to_node$$;
COMMENT ON FUNCTION pg_catalog.citus_check_connection_to_node (
    nodename text, nodeport integer)
    IS 'checks connection to another node';
CREATE FUNCTION pg_catalog.citus_check_cluster_node_health (
    OUT from_nodename text,
    OUT from_nodeport int,
    OUT to_nodename text,
    OUT to_nodeport int,
    OUT result bool )
    RETURNS SETOF RECORD
    LANGUAGE C
    STRICT
    AS 'MODULE_PATHNAME', $$citus_check_cluster_node_health$$;
COMMENT ON FUNCTION pg_catalog.citus_check_cluster_node_health ()
    IS 'checks connections between all nodes in the cluster';
CREATE OR REPLACE FUNCTION pg_catalog.citus_shards_on_worker(
     OUT schema_name name,
     OUT shard_name name,
     OUT table_type text,
     OUT owner_name name)
 RETURNS SETOF record
 LANGUAGE plpgsql
 SET citus.hide_shards_from_app_name_prefixes = ''
 AS $$
BEGIN
  -- this is the query that \d produces, except pg_table_is_visible
  -- is replaced with pg_catalog.relation_is_a_known_shard(c.oid)
  RETURN QUERY
 SELECT n.nspname as "Schema",
   c.relname as "Name",
   CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized view' WHEN 'i' THEN 'index' WHEN 'S' THEN 'sequence' WHEN 's' THEN 'special' WHEN 'f' THEN 'foreign table' WHEN 'p' THEN 'table' END as "Type",
   pg_catalog.pg_get_userbyid(c.relowner) as "Owner"
 FROM pg_catalog.pg_class c
      LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
 WHERE c.relkind IN ('r','p','v','m','S','f','')
       AND n.nspname <> 'pg_catalog'
       AND n.nspname <> 'information_schema'
       AND n.nspname !~ '^pg_toast'
      AND pg_catalog.relation_is_a_known_shard(c.oid)
 ORDER BY 1,2;
END;
$$;
CREATE OR REPLACE VIEW pg_catalog.citus_shards_on_worker AS
 SELECT schema_name as "Schema",
   shard_name as "Name",
   table_type as "Type",
   owner_name as "Owner"
 FROM pg_catalog.citus_shards_on_worker() s;
CREATE OR REPLACE FUNCTION pg_catalog.citus_shard_indexes_on_worker(
     OUT schema_name name,
     OUT index_name name,
     OUT table_type text,
     OUT owner_name name,
     OUT shard_name name)
 RETURNS SETOF record
 LANGUAGE plpgsql
 SET citus.hide_shards_from_app_name_prefixes = ''
 AS $$
BEGIN
  -- this is the query that \di produces, except pg_table_is_visible
  -- is replaced with pg_catalog.relation_is_a_known_shard(c.oid)
  RETURN QUERY
    SELECT n.nspname as "Schema",
      c.relname as "Name",
      CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized view' WHEN 'i' THEN 'index' WHEN 'S' THEN 'sequence' WHEN 's' THEN 'special' WHEN 'f' THEN 'foreign table' WHEN 'p' THEN 'table' END as "Type",
      pg_catalog.pg_get_userbyid(c.relowner) as "Owner",
      c2.relname as "Table"
    FROM pg_catalog.pg_class c
      LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      LEFT JOIN pg_catalog.pg_index i ON i.indexrelid = c.oid
      LEFT JOIN pg_catalog.pg_class c2 ON i.indrelid = c2.oid
    WHERE c.relkind IN ('i','')
      AND n.nspname <> 'pg_catalog'
      AND n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_toast'
      AND pg_catalog.relation_is_a_known_shard(c.oid)
    ORDER BY 1,2;
END;
$$;
CREATE OR REPLACE VIEW pg_catalog.citus_shard_indexes_on_worker AS
 SELECT schema_name as "Schema",
   index_name as "Name",
   table_type as "Type",
   owner_name as "Owner",
   shard_name as "Table"
 FROM pg_catalog.citus_shard_indexes_on_worker() s;
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
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_delete_colocation_metadata(
       colocation_id int)
    RETURNS void
    LANGUAGE C
    STRICT
    AS 'MODULE_PATHNAME';
COMMENT ON FUNCTION pg_catalog.citus_internal_delete_colocation_metadata(int) IS
    'deletes a co-location group from pg_dist_colocation';
CREATE OR REPLACE FUNCTION pg_catalog.citus_run_local_command(command text)
RETURNS void AS $$
BEGIN
    EXECUTE $1;
END;
$$ LANGUAGE PLPGSQL;
COMMENT ON FUNCTION pg_catalog.citus_run_local_command(text)
    IS 'citus_run_local_command executes the input command';
DROP FUNCTION IF EXISTS pg_catalog.worker_drop_sequence_dependency(table_name text);
CREATE OR REPLACE FUNCTION pg_catalog.worker_drop_sequence_dependency(table_name text)
    RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_drop_sequence_dependency$$;
COMMENT ON FUNCTION pg_catalog.worker_drop_sequence_dependency(table_name text)
    IS 'drop the Citus tables sequence dependency';
CREATE FUNCTION pg_catalog.worker_drop_shell_table(table_name text)
    RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_drop_shell_table$$;
COMMENT ON FUNCTION worker_drop_shell_table(table_name text)
    IS 'drop the distributed table only without the metadata';
DROP FUNCTION IF EXISTS pg_catalog.get_all_active_transactions();
CREATE OR REPLACE FUNCTION pg_catalog.get_all_active_transactions(OUT datid oid, OUT process_id int, OUT initiator_node_identifier int4,
                                                                  OUT worker_query BOOL, OUT transaction_number int8, OUT transaction_stamp timestamptz,
                                                                  OUT global_pid int8)
RETURNS SETOF RECORD
LANGUAGE C STRICT AS 'MODULE_PATHNAME',
$$get_all_active_transactions$$;
COMMENT ON FUNCTION pg_catalog.get_all_active_transactions(OUT datid oid, OUT datname text, OUT process_id int, OUT initiator_node_identifier int4,
                                                           OUT worker_query BOOL, OUT transaction_number int8, OUT transaction_stamp timestamptz,
                                                           OUT global_pid int8)
IS 'returns transaction information for all Citus initiated transactions';
DROP FUNCTION IF EXISTS pg_catalog.get_global_active_transactions();
CREATE OR REPLACE FUNCTION pg_catalog.get_global_active_transactions(OUT datid oid, OUT process_id int, OUT initiator_node_identifier int4, OUT worker_query BOOL,
                                                              OUT transaction_number int8, OUT transaction_stamp timestamptz, OUT global_pid int8)
  RETURNS SETOF RECORD
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$get_global_active_transactions$$;
COMMENT ON FUNCTION pg_catalog.get_global_active_transactions(OUT datid oid, OUT process_id int, OUT initiator_node_identifier int4, OUT worker_query BOOL,
                 OUT transaction_number int8, OUT transaction_stamp timestamptz, OUT global_pid int8)
     IS 'returns transaction information for all Citus initiated transactions from each node of the cluster';
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
DROP FUNCTION IF EXISTS pg_catalog.run_command_on_all_nodes;
CREATE FUNCTION pg_catalog.run_command_on_all_nodes(command text, parallel bool default true, give_warning_for_connection_errors bool default false,
             OUT nodeid int, OUT success bool, OUT result text)
 RETURNS SETOF record
 LANGUAGE plpgsql
 AS $function$
DECLARE
 nodenames text[];
 ports int[];
 commands text[];
 current_node_is_in_metadata boolean;
 command_result_of_current_node text;
BEGIN
 WITH citus_nodes AS (
  SELECT * FROM pg_dist_node
  WHERE isactive = 't' AND nodecluster = current_setting('citus.cluster_name')
  AND (
   (current_setting('citus.use_secondary_nodes') = 'never' AND noderole = 'primary')
   OR
   (current_setting('citus.use_secondary_nodes') = 'always' AND noderole = 'secondary')
  )
  ORDER BY nodename, nodeport
 )
 SELECT array_agg(citus_nodes.nodename), array_agg(citus_nodes.nodeport), array_agg(command)
 INTO nodenames, ports, commands
 FROM citus_nodes;
 SELECT count(*) > 0 FROM pg_dist_node
 WHERE isactive = 't'
 AND nodecluster = current_setting('citus.cluster_name')
 AND groupid IN (SELECT groupid FROM pg_dist_local_group)
 INTO current_node_is_in_metadata;
 -- This will happen when we call this function on coordinator and
 -- the coordinator is not added to the metadata.
 -- We'll manually add current node to the lists to actually run on all nodes.
 -- But when the coordinator is not added to metadata and this function
 -- is called from a worker node, this will not be enough and we'll
 -- not be able run on all nodes.
 IF NOT current_node_is_in_metadata THEN
  SELECT
  array_append(nodenames, current_setting('citus.local_hostname')),
  array_append(ports, current_setting('port')::int),
  array_append(commands, command)
  INTO nodenames, ports, commands;
 END IF;
 FOR nodeid, success, result IN
  SELECT coalesce(pg_dist_node.nodeid, 0) AS nodeid, mrow.success, mrow.result
  FROM master_run_on_worker(nodenames, ports, commands, parallel) mrow
  LEFT JOIN pg_dist_node ON mrow.node_name = pg_dist_node.nodename AND mrow.node_port = pg_dist_node.nodeport
 LOOP
  IF give_warning_for_connection_errors AND NOT success THEN
   RAISE WARNING 'Error on node with node id %: %', nodeid, result;
  END IF;
  RETURN NEXT;
 END LOOP;
END;
$function$;
-- citus_stat_activity combines the pg_stat_activity views from all nodes and adds global_pid, nodeid and is_worker_query columns.
-- The columns of citus_stat_activity don't change based on the Postgres version, however the pg_stat_activity's columns do.
-- Both Postgres 13 and 14 added one more column to pg_stat_activity (leader_pid and query_id).
-- citus_stat_activity has the most expansive column set, including the newly added columns.
-- If citus_stat_activity is queried in a Postgres version where pg_stat_activity doesn't have some columns citus_stat_activity has
-- the values for those columns will be NULL
CREATE OR REPLACE FUNCTION pg_catalog.citus_stat_activity(OUT global_pid bigint, OUT nodeid int, OUT is_worker_query boolean, OUT datid oid, OUT datname name, OUT pid integer,
                                                          OUT leader_pid integer, OUT usesysid oid, OUT usename name, OUT application_name text, OUT client_addr inet, OUT client_hostname text,
                                                          OUT client_port integer, OUT backend_start timestamp with time zone, OUT xact_start timestamp with time zone,
                                                          OUT query_start timestamp with time zone, OUT state_change timestamp with time zone, OUT wait_event_type text, OUT wait_event text,
                                                          OUT state text, OUT backend_xid xid, OUT backend_xmin xid, OUT query_id bigint, OUT query text, OUT backend_type text)
    RETURNS SETOF record
    LANGUAGE plpgsql
    AS $function$
BEGIN
    RETURN QUERY SELECT * FROM jsonb_to_recordset((
        SELECT jsonb_agg(all_csa_rows_as_jsonb.csa_row_as_jsonb)::JSONB FROM (
            SELECT jsonb_array_elements(run_command_on_all_nodes.result::JSONB)::JSONB || ('{"nodeid":' || run_command_on_all_nodes.nodeid || '}')::JSONB AS csa_row_as_jsonb
            FROM run_command_on_all_nodes($$
                SELECT coalesce(to_jsonb(array_agg(csa_from_one_node.*)), '[{}]'::JSONB)
                FROM (
                    SELECT global_pid, worker_query AS is_worker_query, pg_stat_activity.* FROM
                    pg_stat_activity LEFT JOIN get_all_active_transactions() ON process_id = pid
                ) AS csa_from_one_node;
            $$, parallel:=true, give_warning_for_connection_errors:=true)
            WHERE success = 't'
        ) AS all_csa_rows_as_jsonb
    ))
    AS (global_pid bigint, nodeid int, is_worker_query boolean, datid oid, datname name, pid integer,
        leader_pid integer, usesysid oid, usename name, application_name text, client_addr inet, client_hostname text,
        client_port integer, backend_start timestamp with time zone, xact_start timestamp with time zone,
        query_start timestamp with time zone, state_change timestamp with time zone, wait_event_type text, wait_event text,
        state text, backend_xid xid, backend_xmin xid, query_id bigint, query text, backend_type text);
END;
$function$;
CREATE OR REPLACE VIEW citus.citus_stat_activity AS
SELECT * FROM pg_catalog.citus_stat_activity();
ALTER VIEW citus.citus_stat_activity SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_stat_activity TO PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.worker_create_or_replace_object(statement text)
  RETURNS bool
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$worker_create_or_replace_object$$;
COMMENT ON FUNCTION pg_catalog.worker_create_or_replace_object(statement text)
    IS 'takes a sql CREATE statement, before executing the create it will check if an object with that name already exists and safely replaces that named object with the new object';
CREATE OR REPLACE FUNCTION pg_catalog.worker_create_or_replace_object(statements text[])
  RETURNS bool
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$worker_create_or_replace_object_array$$;
COMMENT ON FUNCTION pg_catalog.worker_create_or_replace_object(statements text[])
    IS 'takes an array of sql statements, before executing these it will check if the object already exists in that exact state otherwise replaces that named object with the new object';
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
    ) OR EXISTS (
      -- Check on the workers if any logical replication job spawned by the
      -- current PID is blocked, by checking it's application name
      -- Query is heavily based on: https:
      SELECT result FROM run_command_on_workers($two$
        SELECT blocked_activity.application_name AS blocked_application
           FROM pg_catalog.pg_locks blocked_locks
            JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
            JOIN pg_catalog.pg_locks blocking_locks
                ON blocking_locks.locktype = blocked_locks.locktype
                AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
                AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
                AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
                AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
                AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
                AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
                AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
                AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
                AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
                AND blocking_locks.pid != blocked_locks.pid
            JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
           WHERE NOT blocked_locks.GRANTED AND blocked_activity.application_name LIKE 'citus_shard_move_subscription_%'
        $two$) where result LIKE 'citus_shard_move_subscription_%_' || pBlockedPid);
  END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION citus_isolation_test_session_is_blocked(integer,integer[]) FROM PUBLIC;
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
        SELECT blocking_global_pid FROM citus_internal_global_blocked_processes()
        WHERE waiting_global_pid = mLocalGlobalPid
      )
      SELECT activeTransactions.global_pid FROM activeTransactions, blockingTransactions
      WHERE activeTransactions.global_pid = blockingTransactions.blocking_global_pid
    ) AS sub;
    RETURN mRemoteBlockingPids;
  END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION citus_blocking_pids(integer) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_calculate_gpid(nodeid integer,
                                                pid integer)
    RETURNS BIGINT
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME',$$citus_calculate_gpid$$;
COMMENT ON FUNCTION pg_catalog.citus_calculate_gpid(nodeid integer, pid integer)
    IS 'calculate gpid of a backend running on any node';
GRANT EXECUTE ON FUNCTION pg_catalog.citus_calculate_gpid(integer, integer) TO PUBLIC;
CREATE FUNCTION pg_catalog.citus_backend_gpid()
    RETURNS BIGINT
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME',$$citus_backend_gpid$$;
COMMENT ON FUNCTION pg_catalog.citus_backend_gpid()
    IS 'returns gpid of the current backend';
GRANT EXECUTE ON FUNCTION pg_catalog.citus_backend_gpid() TO PUBLIC;
DROP VIEW IF EXISTS pg_catalog.citus_lock_waits;
DROP VIEW IF EXISTS pg_catalog.citus_dist_stat_activity;
DROP VIEW IF EXISTS pg_catalog.citus_worker_stat_activity;
DROP FUNCTION IF EXISTS pg_catalog.citus_dist_stat_activity();
DROP FUNCTION IF EXISTS pg_catalog.citus_worker_stat_activity();
DROP VIEW IF EXISTS pg_catalog.citus_dist_stat_activity;
CREATE OR REPLACE VIEW citus.citus_dist_stat_activity AS
SELECT * FROM citus_stat_activity
WHERE is_worker_query = false;
ALTER VIEW citus.citus_dist_stat_activity SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_dist_stat_activity TO PUBLIC;
-- a very simple helper function defined for citus_lock_waits
CREATE OR REPLACE FUNCTION get_nodeid_for_groupid(groupIdInput int) RETURNS int AS $$
DECLARE
 returnNodeNodeId int := 0;
begin
 SELECT nodeId into returnNodeNodeId FROM pg_dist_node WHERE groupid = groupIdInput and nodecluster = current_setting('citus.cluster_name');
 RETURN returnNodeNodeId;
end
$$ LANGUAGE plpgsql;
SET search_path = 'pg_catalog';
CREATE VIEW citus.citus_lock_waits AS
WITH
unique_global_wait_edges_with_calculated_gpids AS (
SELECT
   -- if global_pid is NULL, it is most likely that a backend is blocked on a DDL
   -- also for legacy reasons citus_internal_global_blocked_processes() returns groupId, we replace that with nodeIds
   case WHEN waiting_global_pid !=0 THEN waiting_global_pid ELSE citus_calculate_gpid(get_nodeid_for_groupid(waiting_node_id), waiting_pid) END waiting_global_pid,
   case WHEN blocking_global_pid !=0 THEN blocking_global_pid ELSE citus_calculate_gpid(get_nodeid_for_groupid(blocking_node_id), blocking_pid) END blocking_global_pid,
   -- citus_internal_global_blocked_processes returns groupId, we replace it here with actual
   -- nodeId to be consisten with the other views
   get_nodeid_for_groupid(blocking_node_id) as blocking_node_id,
   get_nodeid_for_groupid(waiting_node_id) as waiting_node_id,
   blocking_transaction_waiting
   FROM citus_internal_global_blocked_processes()
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
DROP FUNCTION pg_catalog.worker_partition_query_result(text, text, int, citus.distribution_type, text[], text[], boolean);
CREATE OR REPLACE FUNCTION pg_catalog.worker_partition_query_result(
    result_prefix text,
    query text,
    partition_column_index int,
    partition_method citus.distribution_type,
    partition_min_values text[],
    partition_max_values text[],
    binary_copy boolean,
    allow_null_partition_column boolean DEFAULT false,
    generate_empty_results boolean DEFAULT false,
    OUT partition_index int,
    OUT rows_written bigint,
    OUT bytes_written bigint)
RETURNS SETOF record
LANGUAGE C STRICT VOLATILE
AS 'MODULE_PATHNAME', $$worker_partition_query_result$$;
COMMENT ON FUNCTION pg_catalog.worker_partition_query_result(text, text, int, citus.distribution_type, text[], text[], boolean, boolean, boolean)
IS 'execute a query and partitions its results in set of local result files';
DROP FUNCTION pg_catalog.master_apply_delete_command(text);
DROP FUNCTION pg_catalog.master_get_table_metadata(text);
DROP FUNCTION pg_catalog.master_append_table_to_shard(bigint, text, text, integer);
-- all existing citus local tables are auto converted
-- none of the other tables can have auto-converted as true
ALTER TABLE pg_catalog.pg_dist_partition ADD COLUMN autoconverted boolean DEFAULT false;
ALTER TABLE citus.pg_dist_object ADD COLUMN force_delegation bool DEFAULT NULL;
UPDATE pg_catalog.pg_dist_partition SET autoconverted = TRUE WHERE partmethod = 'n' AND repmodel = 's';
REVOKE ALL ON FUNCTION start_metadata_sync_to_node(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION stop_metadata_sync_to_node(text, integer,bool) FROM PUBLIC;
DO LANGUAGE plpgsql
$$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_dist_shard where shardstorage = 'c') THEN
     RAISE EXCEPTION 'cstore_fdw tables are deprecated as of Citus 11.0'
        USING HINT = 'Install Citus 10.2 and convert your cstore_fdw tables to the columnar access method before upgrading further';
 END IF;
END;
$$;
-- Here we keep track of partitioned tables that exists before Citus 11
-- where we need to call fix_all_partition_shard_index_names() before
-- metadata is synced. Note that after citus-11, we automatically
-- adjust the indexes so we only need to fix existing indexes
DO LANGUAGE plpgsql
$$
DECLARE
  partitioned_table_exists bool :=false;
BEGIN
      SELECT count(*) > 0 INTO partitioned_table_exists FROM pg_dist_partition p JOIN pg_class c ON p.logicalrelid = c.oid WHERE c.relkind = 'p';
      UPDATE pg_dist_node_metadata SET metadata=jsonb_set(metadata, '{partitioned_citus_table_exists_pre_11}', to_jsonb(partitioned_table_exists), true);
END;
$$;
-- citus_finalize_upgrade_to_citus11() is a helper UDF ensures
-- the upgrade to Citus 11 is finished successfully. Upgrade to
-- Citus 11 requires all active primary worker nodes to get the
-- metadata. And, this function's job is to sync the metadata to
-- the nodes that does not already have
-- once the function finishes without any errors and returns true
-- the cluster is ready for running distributed queries from
-- the worker nodes. When debug is enabled, the function provides
-- more information to the user.
CREATE OR REPLACE FUNCTION pg_catalog.citus_finalize_upgrade_to_citus11(enforce_version_check bool default true)
  RETURNS bool
  LANGUAGE plpgsql
  AS $$
BEGIN
  ---------------------------------------------
  -- This script consists of N stages
  -- Each step is documented, and if log level
  -- is reduced to DEBUG1, each step is logged
  -- as well
  ---------------------------------------------
------------------------------------------------------------------------------------------
  -- STAGE 0: Ensure no concurrent node metadata changing operation happens while this
  -- script is running via acquiring a strong lock on the pg_dist_node
------------------------------------------------------------------------------------------
BEGIN
  LOCK TABLE pg_dist_node IN EXCLUSIVE MODE NOWAIT;
  EXCEPTION WHEN OTHERS THEN
  RAISE 'Another node metadata changing operation is in progress, try again.';
END;
------------------------------------------------------------------------------------------
  -- STAGE 1: We want all the commands to run in the same transaction block. Without
  -- sequential mode, metadata syncing cannot be done in a transaction block along with
  -- other commands
------------------------------------------------------------------------------------------
  SET LOCAL citus.multi_shard_modify_mode TO 'sequential';
------------------------------------------------------------------------------------------
  -- STAGE 2: Ensure we have the prerequisites
  -- (a) only superuser can run this script
  -- (b) cannot be executed when enable_ddl_propagation is False
  -- (c) can only be executed from the coordinator
------------------------------------------------------------------------------------------
DECLARE
  is_superuser_running boolean := False;
  enable_ddl_prop boolean:= False;
  local_group_id int := 0;
BEGIN
      SELECT rolsuper INTO is_superuser_running FROM pg_roles WHERE rolname = current_user;
      IF is_superuser_running IS NOT True THEN
                RAISE EXCEPTION 'This operation can only be initiated by superuser';
      END IF;
      SELECT current_setting('citus.enable_ddl_propagation') INTO enable_ddl_prop;
      IF enable_ddl_prop IS NOT True THEN
                RAISE EXCEPTION 'This operation cannot be completed when citus.enable_ddl_propagation is False.';
      END IF;
      SELECT groupid INTO local_group_id FROM pg_dist_local_group;
      IF local_group_id != 0 THEN
                RAISE EXCEPTION 'Operation is not allowed on this node. Connect to the coordinator and run it again.';
      ELSE
                RAISE DEBUG 'We are on the coordinator, continue to sync metadata';
      END IF;
END;
  ------------------------------------------------------------------------------------------
    -- STAGE 3: Ensure all primary nodes are active
  ------------------------------------------------------------------------------------------
  DECLARE
    primary_disabled_worker_node_count int := 0;
  BEGIN
        SELECT count(*) INTO primary_disabled_worker_node_count FROM pg_dist_node
                WHERE groupid != 0 AND noderole = 'primary' AND NOT isactive;
        IF primary_disabled_worker_node_count != 0 THEN
                  RAISE EXCEPTION 'There are inactive primary worker nodes, you need to activate the nodes first.'
                                  'Use SELECT citus_activate_node() to activate the disabled nodes';
        ELSE
                  RAISE DEBUG 'There are no disabled worker nodes, continue to sync metadata';
        END IF;
  END;
  ------------------------------------------------------------------------------------------
    -- STAGE 4: Ensure there is no connectivity issues in the cluster
  ------------------------------------------------------------------------------------------
  DECLARE
    all_nodes_can_connect_to_each_other boolean := False;
  BEGIN
       SELECT bool_and(coalesce(result, false)) INTO all_nodes_can_connect_to_each_other FROM citus_check_cluster_node_health();
        IF all_nodes_can_connect_to_each_other != True THEN
                  RAISE EXCEPTION 'There are unhealth primary nodes, you need to ensure all '
                                  'nodes are up and running. Also, make sure that all nodes can connect '
                                  'to each other. Use SELECT * FROM citus_check_cluster_node_health(); '
                                  'to check the cluster health';
        ELSE
                  RAISE DEBUG 'Cluster is healthy, all nodes can connect to each other';
        END IF;
  END;
  ------------------------------------------------------------------------------------------
    -- STAGE 5: Ensure all nodes are on the same version
  ------------------------------------------------------------------------------------------
    DECLARE
      coordinator_version text := '';
      worker_node_version text := '';
      worker_node_version_count int := 0;
    BEGIN
         SELECT extversion INTO coordinator_version from pg_extension WHERE extname = 'citus';
         -- first, check if all nodes have the same versions
          SELECT
            count(distinct result) INTO worker_node_version_count
          FROM
            run_command_on_workers('SELECT extversion from pg_extension WHERE extname = ''citus''');
          IF enforce_version_check AND worker_node_version_count != 1 THEN
                    RAISE EXCEPTION 'All nodes should have the same Citus version installed. Currently '
                                     'some of the workers have different versions.';
          ELSE
                    RAISE DEBUG 'All worker nodes have the same Citus version';
          END IF;
         -- second, check if all nodes have the same versions
         SELECT
            result INTO worker_node_version
         FROM
            run_command_on_workers('SELECT extversion from pg_extension WHERE extname = ''citus'';')
          GROUP BY result;
          IF enforce_version_check AND coordinator_version != worker_node_version THEN
                    RAISE EXCEPTION 'All nodes should have the same Citus version installed. Currently '
                                     'the coordinator has version % and the worker(s) has %',
                                     coordinator_version, worker_node_version;
          ELSE
                    RAISE DEBUG 'All nodes have the same Citus version';
          END IF;
    END;
  ------------------------------------------------------------------------------------------
    -- STAGE 6: Ensure all the partitioned tables have the proper naming structure
    -- As described on https:
    -- existing indexes on partitioned distributed tables can collide
    -- with the index names exists on the shards
    -- luckily, we know how to fix it.
    -- And, note that we should do this even if the cluster is a basic plan
    -- (e.g., single node Citus) such that when cluster scaled out, everything
    -- works as intended
    -- And, this should be done only ONCE for a cluster as it can be a pretty
    -- time consuming operation. Thus, even if the function is called multiple time,
    -- we keep track of it and do not re-execute this part if not needed.
  ------------------------------------------------------------------------------------------
  DECLARE
      partitioned_table_exists_pre_11 boolean:=False;
  BEGIN
    -- we recorded if partitioned tables exists during upgrade to Citus 11
    SELECT metadata->>'partitioned_citus_table_exists_pre_11' INTO partitioned_table_exists_pre_11
    FROM pg_dist_node_metadata;
    IF partitioned_table_exists_pre_11 IS NOT NULL AND partitioned_table_exists_pre_11 THEN
      -- this might take long depending on the number of partitions and shards...
      RAISE NOTICE 'Preparing all the existing partitioned table indexes';
      PERFORM pg_catalog.fix_all_partition_shard_index_names();
      -- great, we are done with fixing the existing wrong index names
      -- so, lets remove this
      UPDATE pg_dist_node_metadata
      SET metadata=jsonb_delete(metadata, 'partitioned_citus_table_exists_pre_11');
    ELSE
        RAISE DEBUG 'There are no partitioned tables that should be fixed';
    END IF;
  END;
  ------------------------------------------------------------------------------------------
  -- STAGE 7: Return early if there are no primary worker nodes
  -- We don't strictly need this step, but it gives a nicer notice message
  ------------------------------------------------------------------------------------------
  DECLARE
    primary_worker_node_count bigint :=0;
  BEGIN
        SELECT count(*) INTO primary_worker_node_count FROM pg_dist_node WHERE groupid != 0 AND noderole = 'primary';
        IF primary_worker_node_count = 0 THEN
                  RAISE NOTICE 'There are no primary worker nodes, no need to sync metadata to any node';
                  RETURN true;
        ELSE
                  RAISE DEBUG 'There are % primary worker nodes, continue to sync metadata', primary_worker_node_count;
        END IF;
  END;
  ------------------------------------------------------------------------------------------
  -- STAGE 8: Do the actual metadata & object syncing to the worker nodes
  -- For the "already synced" metadata nodes, we do not strictly need to
  -- sync the objects & metadata, but there is no harm to do it anyway
  -- it'll only cost some execution time but makes sure that we have a
  -- a consistent metadata & objects across all the nodes
  ------------------------------------------------------------------------------------------
  DECLARE
  BEGIN
    -- this might take long depending on the number of tables & objects ...
    RAISE NOTICE 'Preparing to sync the metadata to all nodes';
    PERFORM start_metadata_sync_to_node(nodename,nodeport)
    FROM
      pg_dist_node WHERE groupid != 0 AND noderole = 'primary';
  END;
  RETURN true;
END;
$$;
COMMENT ON FUNCTION pg_catalog.citus_finalize_upgrade_to_citus11(bool)
  IS 'finalizes upgrade to Citus';
REVOKE ALL ON FUNCTION pg_catalog.citus_finalize_upgrade_to_citus11(bool) FROM PUBLIC;
ALTER TABLE citus.pg_dist_object SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.pg_dist_object TO public;
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
    -- set dependencies for columnar table access method
    PERFORM citus_internal.columnar_ensure_am_depends_catalog();
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
CREATE OR REPLACE FUNCTION pg_catalog.citus_nodename_for_nodeid(nodeid integer)
    RETURNS text
    LANGUAGE C STABLE STRICT
    AS 'MODULE_PATHNAME', $$citus_nodename_for_nodeid$$;
COMMENT ON FUNCTION pg_catalog.citus_nodename_for_nodeid(nodeid integer)
    IS 'returns node name for the node with given node id';
CREATE OR REPLACE FUNCTION pg_catalog.citus_nodeport_for_nodeid(nodeid integer)
    RETURNS integer
    LANGUAGE C STABLE STRICT
    AS 'MODULE_PATHNAME', $$citus_nodeport_for_nodeid$$;
COMMENT ON FUNCTION pg_catalog.citus_nodeport_for_nodeid(nodeid integer)
    IS 'returns node port for the node with given node id';
CREATE OR REPLACE FUNCTION pg_catalog.citus_nodeid_for_gpid(global_pid bigint)
    RETURNS integer
    LANGUAGE C STABLE STRICT
    AS 'MODULE_PATHNAME', $$citus_nodeid_for_gpid$$;
COMMENT ON FUNCTION pg_catalog.citus_nodeid_for_gpid(global_pid bigint)
    IS 'returns node id for the global process with given global pid';
CREATE OR REPLACE FUNCTION pg_catalog.citus_pid_for_gpid(global_pid bigint)
    RETURNS integer
    LANGUAGE C STABLE STRICT
    AS 'MODULE_PATHNAME', $$citus_pid_for_gpid$$;
COMMENT ON FUNCTION pg_catalog.citus_pid_for_gpid(global_pid bigint)
    IS 'returns process id for the global process with given global pid';
CREATE OR REPLACE FUNCTION pg_catalog.citus_coordinator_nodeid()
    RETURNS integer
    LANGUAGE C STABLE STRICT
    AS 'MODULE_PATHNAME', $$citus_coordinator_nodeid$$;
COMMENT ON FUNCTION pg_catalog.citus_coordinator_nodeid()
    IS 'returns node id of the coordinator node';
