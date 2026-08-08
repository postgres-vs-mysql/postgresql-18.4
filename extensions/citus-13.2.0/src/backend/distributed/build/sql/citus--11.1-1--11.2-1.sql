-- citus--11.1-1--11.2-1
DROP FUNCTION pg_catalog.worker_append_table_to_shard(text, text, text, integer);
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
                operation_type text,
                source_lsn pg_lsn,
                target_lsn pg_lsn,
                status text
            )
  AS 'MODULE_PATHNAME'
  LANGUAGE C STRICT;
COMMENT ON FUNCTION pg_catalog.get_rebalance_progress()
    IS 'provides progress information about the ongoing rebalance operations';
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
      SELECT 1 FROM citus_internal_global_blocked_processes()
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
--
-- cluster_clock base type is a combination of
-- uint64 cluster clock logical timestamp at the commit
-- uint32 cluster clock counter(ticks with in the logical clock)
--
CREATE TYPE citus.cluster_clock;
CREATE FUNCTION pg_catalog.cluster_clock_in(cstring)
    RETURNS citus.cluster_clock
    AS 'MODULE_PATHNAME',$$cluster_clock_in$$
    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pg_catalog.cluster_clock_out(citus.cluster_clock)
    RETURNS cstring
    AS 'MODULE_PATHNAME',$$cluster_clock_out$$
    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pg_catalog.cluster_clock_recv(internal)
   RETURNS citus.cluster_clock
   AS 'MODULE_PATHNAME',$$cluster_clock_recv$$
   LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pg_catalog.cluster_clock_send(citus.cluster_clock)
   RETURNS bytea
   AS 'MODULE_PATHNAME',$$cluster_clock_send$$
   LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pg_catalog.cluster_clock_logical(citus.cluster_clock)
    RETURNS bigint
    AS 'MODULE_PATHNAME',$$cluster_clock_logical$$
    LANGUAGE C IMMUTABLE STRICT;
CREATE TYPE citus.cluster_clock (
    internallength = 12, -- specifies the size of the memory block required to hold the type uint64 + uint32
    input = cluster_clock_in,
    output = cluster_clock_out,
    receive = cluster_clock_recv,
    send = cluster_clock_send
);
ALTER TYPE citus.cluster_clock SET SCHEMA pg_catalog;
COMMENT ON TYPE cluster_clock IS 'combination of (logical, counter): 42 bits + 22 bits';
--
-- Define the required operators
--
CREATE FUNCTION pg_catalog.cluster_clock_lt(cluster_clock, cluster_clock) RETURNS bool
    AS 'MODULE_PATHNAME',$$cluster_clock_lt$$
    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pg_catalog.cluster_clock_le(cluster_clock, cluster_clock) RETURNS bool
    AS 'MODULE_PATHNAME',$$cluster_clock_le$$
    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pg_catalog.cluster_clock_eq(cluster_clock, cluster_clock) RETURNS bool
    AS 'MODULE_PATHNAME',$$cluster_clock_eq$$
    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pg_catalog.cluster_clock_ne(cluster_clock, cluster_clock) RETURNS bool
    AS 'MODULE_PATHNAME',$$cluster_clock_ne$$
    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pg_catalog.cluster_clock_ge(cluster_clock, cluster_clock) RETURNS bool
    AS 'MODULE_PATHNAME',$$cluster_clock_ge$$
    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pg_catalog.cluster_clock_gt(cluster_clock, cluster_clock) RETURNS bool
    AS 'MODULE_PATHNAME',$$cluster_clock_gt$$
    LANGUAGE C IMMUTABLE STRICT;
CREATE OPERATOR < (
   leftarg = cluster_clock, rightarg = cluster_clock, procedure = cluster_clock_lt,
   commutator = > , negator = >= ,
   restrict = scalarltsel, join = scalarltjoinsel
);
CREATE OPERATOR <= (
   leftarg = cluster_clock, rightarg = cluster_clock, procedure = cluster_clock_le,
   commutator = >= , negator = > ,
   restrict = scalarlesel, join = scalarlejoinsel
);
CREATE OPERATOR = (
   leftarg = cluster_clock, rightarg = cluster_clock, procedure = cluster_clock_eq,
   commutator = = ,
   negator = <> ,
   restrict = eqsel, join = eqjoinsel
);
CREATE OPERATOR <> (
   leftarg = cluster_clock, rightarg = cluster_clock, procedure = cluster_clock_ne,
   commutator = <> ,
   negator = = ,
   restrict = neqsel, join = neqjoinsel
);
CREATE OPERATOR >= (
   leftarg = cluster_clock, rightarg = cluster_clock, procedure = cluster_clock_ge,
   commutator = <= , negator = < ,
   restrict = scalargesel, join = scalargejoinsel
);
CREATE OPERATOR > (
   leftarg = cluster_clock, rightarg = cluster_clock, procedure = cluster_clock_gt,
   commutator = < , negator = <= ,
   restrict = scalargtsel, join = scalargtjoinsel
);
-- Create the support function too
CREATE FUNCTION pg_catalog.cluster_clock_cmp(cluster_clock, cluster_clock) RETURNS int4
    AS 'MODULE_PATHNAME',$$cluster_clock_cmp$$
    LANGUAGE C IMMUTABLE STRICT;
-- Define operator class to be be used by an index for type cluster_clock.
CREATE OPERATOR CLASS pg_catalog.cluster_clock_ops
    DEFAULT FOR TYPE cluster_clock USING btree AS
        OPERATOR 1 < ,
        OPERATOR 2 <= ,
        OPERATOR 3 = ,
        OPERATOR 4 >= ,
        OPERATOR 5 > ,
        FUNCTION 1 cluster_clock_cmp(cluster_clock, cluster_clock);
--
-- Create sequences for logical and counter fields of the type cluster_clock, to
-- be used as a storage.
--
CREATE SEQUENCE citus.pg_dist_clock_logical_seq START 1;
ALTER SEQUENCE citus.pg_dist_clock_logical_seq SET SCHEMA pg_catalog;
REVOKE UPDATE ON SEQUENCE pg_catalog.pg_dist_clock_logical_seq FROM public;
CREATE OR REPLACE FUNCTION pg_catalog.citus_get_node_clock()
    RETURNS pg_catalog.cluster_clock
    LANGUAGE C VOLATILE PARALLEL UNSAFE STRICT
    AS 'MODULE_PATHNAME',$$citus_get_node_clock$$;
COMMENT ON FUNCTION pg_catalog.citus_get_node_clock()
    IS 'Returns monotonically increasing timestamp with logical clock value as close to epoch value (in milli seconds) as possible, and a counter for ticks(maximum of 4 million) within the logical clock';
CREATE OR REPLACE FUNCTION pg_catalog.citus_get_transaction_clock()
    RETURNS pg_catalog.cluster_clock
    LANGUAGE C VOLATILE PARALLEL UNSAFE STRICT
    AS 'MODULE_PATHNAME',$$citus_get_transaction_clock$$;
COMMENT ON FUNCTION pg_catalog.citus_get_transaction_clock()
    IS 'Returns a transaction timestamp logical clock';
CREATE OR REPLACE FUNCTION pg_catalog.citus_is_clock_after(clock_one pg_catalog.cluster_clock, clock_two pg_catalog.cluster_clock)
    RETURNS BOOL
    LANGUAGE C STABLE PARALLEL SAFE STRICT
    AS 'MODULE_PATHNAME',$$citus_is_clock_after$$;
COMMENT ON FUNCTION pg_catalog.citus_is_clock_after(pg_catalog.cluster_clock, pg_catalog.cluster_clock)
    IS 'Accepts logical clock timestamps of two causally related events and returns true if the argument1 happened before argument2';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_adjust_local_clock_to_remote(pg_catalog.cluster_clock)
    RETURNS void
    LANGUAGE C STABLE PARALLEL SAFE STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_adjust_local_clock_to_remote$$;
COMMENT ON FUNCTION pg_catalog.citus_internal_adjust_local_clock_to_remote(pg_catalog.cluster_clock)
    IS 'Internal UDF used to adjust the local clock to the maximum of nodes in the cluster';
REVOKE ALL ON FUNCTION pg_catalog.citus_internal_adjust_local_clock_to_remote(pg_catalog.cluster_clock) FROM PUBLIC;
CREATE OR REPLACE FUNCTION pg_catalog.citus_job_list ()
    RETURNS TABLE (
            job_id bigint,
            state pg_catalog.citus_job_status,
            job_type name,
            description text,
            started_at timestamptz,
            finished_at timestamptz
)
    LANGUAGE SQL
    AS $fn$
    SELECT
        job_id,
        state,
        job_type,
        description,
        started_at,
        finished_at
    FROM
        pg_dist_background_job
    ORDER BY
        job_id
$fn$;
CREATE OR REPLACE FUNCTION pg_catalog.citus_job_status (
    job_id bigint,
    raw boolean DEFAULT FALSE
)
    RETURNS TABLE (
            job_id bigint,
            state pg_catalog.citus_job_status,
            job_type name,
            description text,
            started_at timestamptz,
            finished_at timestamptz,
            details jsonb
    )
    LANGUAGE SQL
    STRICT
    AS $fn$
    WITH rp AS MATERIALIZED (
        SELECT
            sessionid,
            sum(source_shard_size) as source_shard_size,
            sum(target_shard_size) as target_shard_size,
            any_value(status) as status,
            any_value(sourcename) as sourcename,
            any_value(sourceport) as sourceport,
            any_value(targetname) as targetname,
            any_value(targetport) as targetport,
            max(source_lsn) as source_lsn,
            min(target_lsn) as target_lsn
        FROM get_rebalance_progress()
        GROUP BY sessionid
    ),
    task_state_occurence_counts AS (
        SELECT t.status, count(task_id)
        FROM pg_dist_background_job j
            JOIN pg_dist_background_task t ON t.job_id = j.job_id
        WHERE j.job_id = $1
        GROUP BY t.status
    ),
    running_task_details AS (
        SELECT jsonb_agg(jsonb_build_object(
                'state', t.status,
                'retried', coalesce(t.retry_count,0),
                'phase', rp.status,
                'size' , jsonb_build_object(
                    'source', rp.source_shard_size,
                    'target', rp.target_shard_size),
                'hosts', jsonb_build_object(
                    'source', rp.sourcename || ':' || rp.sourceport,
                    'target', rp.targetname || ':' || rp.targetport),
                'message', t.message,
                'command', t.command,
                'task_id', t.task_id ) ||
            CASE
                WHEN ($2) THEN jsonb_build_object(
                    'size', jsonb_build_object(
                        'source', rp.source_shard_size,
                        'target', rp.target_shard_size),
                    'LSN', jsonb_build_object(
                        'source', rp.source_lsn,
                        'target', rp.target_lsn,
                        'lag', rp.source_lsn - rp.target_lsn))
                ELSE jsonb_build_object(
                    'size', jsonb_build_object(
                        'source', pg_size_pretty(rp.source_shard_size),
                        'target', pg_size_pretty(rp.target_shard_size)),
                    'LSN', jsonb_build_object(
                        'source', rp.source_lsn,
                        'target', rp.target_lsn,
                        'lag', pg_size_pretty(rp.source_lsn - rp.target_lsn)))
            END) AS tasks
        FROM
            rp JOIN pg_dist_background_task t ON rp.sessionid = t.pid
            JOIN pg_dist_background_job j ON t.job_id = j.job_id
        WHERE j.job_id = $1
            AND t.status = 'running'
    ),
    errored_or_retried_task_details AS (
        SELECT jsonb_agg(jsonb_build_object(
                'state', t.status,
                'retried', coalesce(t.retry_count,0),
                'message', t.message,
                'command', t.command,
                'task_id', t.task_id )) AS tasks
        FROM
            pg_dist_background_task t JOIN pg_dist_background_job j ON t.job_id = j.job_id
        WHERE j.job_id = $1
            AND NOT EXISTS (SELECT 1 FROM rp WHERE rp.sessionid = t.pid)
            AND (t.status = 'error' OR (t.status = 'runnable' AND t.retry_count > 0))
    )
    SELECT
        job_id,
        state,
        job_type,
        description,
        started_at,
        finished_at,
        jsonb_build_object(
            'task_state_counts', (SELECT jsonb_object_agg(status, count) FROM task_state_occurence_counts),
            'tasks', (COALESCE((SELECT tasks FROM running_task_details),'[]'::jsonb) ||
                      COALESCE((SELECT tasks FROM errored_or_retried_task_details),'[]'::jsonb))) AS details
    FROM pg_dist_background_job j
    WHERE j.job_id = $1
$fn$;
CREATE OR REPLACE FUNCTION pg_catalog.citus_rebalance_status (
    raw boolean DEFAULT FALSE
)
    RETURNS TABLE (
            job_id bigint,
            state pg_catalog.citus_job_status,
            job_type name,
            description text,
            started_at timestamptz,
            finished_at timestamptz,
            details jsonb
)
    LANGUAGE SQL
    STRICT
    AS $fn$
    SELECT
        job_status.*
    FROM
        pg_dist_background_job j,
        citus_job_status (j.job_id, $1) job_status
    WHERE
        j.job_id IN (
            SELECT job_id
            FROM pg_dist_background_job
            WHERE job_type = 'rebalance'
            ORDER BY job_id DESC
            LIMIT 1
        );
$fn$;
DROP FUNCTION pg_catalog.worker_split_shard_replication_setup(pg_catalog.split_shard_info[]);
CREATE OR REPLACE FUNCTION pg_catalog.worker_split_shard_replication_setup(
    splitShardInfo pg_catalog.split_shard_info[], operation_id bigint)
RETURNS setof pg_catalog.replication_slot_info
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$worker_split_shard_replication_setup$$;
COMMENT ON FUNCTION pg_catalog.worker_split_shard_replication_setup(splitShardInfo pg_catalog.split_shard_info[], operation_id bigint)
    IS 'Replication setup for splitting a shard';
REVOKE ALL ON FUNCTION pg_catalog.worker_split_shard_replication_setup(pg_catalog.split_shard_info[], bigint) FROM PUBLIC;
CREATE FUNCTION pg_catalog.citus_task_wait(taskid bigint, desired_status pg_catalog.citus_task_status DEFAULT NULL)
    RETURNS VOID
    LANGUAGE C
    AS 'MODULE_PATHNAME',$$citus_task_wait$$;
COMMENT ON FUNCTION pg_catalog.citus_task_wait(taskid bigint, desired_status pg_catalog.citus_task_status)
    IS 'blocks till the task identified by taskid is at the specified status, or reached a terminal status. Only waits for terminal status when no desired_status was specified. The return value indicates if the desired status was reached or not. When no desired status was specified it will assume any terminal status was desired';
GRANT EXECUTE ON FUNCTION pg_catalog.citus_task_wait(taskid bigint, desired_status pg_catalog.citus_task_status) TO PUBLIC;
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
-- citus_copy_shard_placement, but with nodeid
CREATE FUNCTION pg_catalog.citus_copy_shard_placement(
 shard_id bigint,
 source_node_id integer,
 target_node_id integer,
 transfer_mode citus.shard_transfer_mode default 'auto')
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_copy_shard_placement_with_nodeid$$;
COMMENT ON FUNCTION pg_catalog.citus_copy_shard_placement(
 shard_id bigint,
 source_node_id integer,
 target_node_id integer,
 transfer_mode citus.shard_transfer_mode)
IS 'copy a shard from the source node to the destination node';
CREATE OR REPLACE FUNCTION pg_catalog.citus_copy_shard_placement(
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
-- citus_move_shard_placement, but with nodeid
CREATE FUNCTION pg_catalog.citus_move_shard_placement(
 shard_id bigint,
 source_node_id integer,
 target_node_id integer,
 transfer_mode citus.shard_transfer_mode default 'auto')
RETURNS void
LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_move_shard_placement_with_nodeid$$;
COMMENT ON FUNCTION pg_catalog.citus_move_shard_placement(
 shard_id bigint,
 source_node_id integer,
 target_node_id integer,
 transfer_mode citus.shard_transfer_mode)
IS 'move a shard from the source node to the destination node';
CREATE OR REPLACE FUNCTION pg_catalog.citus_move_shard_placement(
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
-- drop orphaned shards after inserting records for them into pg_dist_cleanup
INSERT INTO pg_dist_cleanup
    SELECT nextval('pg_dist_cleanup_recordid_seq'), 0, 1, shard_name(sh.logicalrelid, sh.shardid) AS object_name, plc.groupid AS node_group_id, 0
        FROM pg_dist_placement plc
        JOIN pg_dist_shard sh ON sh.shardid = plc.shardid
        WHERE plc.shardstate = 4;
DELETE FROM pg_dist_placement WHERE shardstate = 4;
