CREATE OR REPLACE FUNCTION pg_catalog.citus_shards_on_worker(
     OUT schema_name name,
     OUT shard_name name,
     OUT table_type text,
     OUT owner_name name)
 RETURNS SETOF record
 LANGUAGE plpgsql
 SET citus.show_shards_for_app_name_prefixes = '*'
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
 SET citus.show_shards_for_app_name_prefixes = '*'
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
CREATE FUNCTION pg_catalog.citus_is_coordinator()
 RETURNS bool
 LANGUAGE c
 STRICT
AS 'MODULE_PATHNAME', $$citus_is_coordinator$$;
COMMENT ON FUNCTION pg_catalog.citus_is_coordinator()
 IS 'returns whether the current node is a coordinator';
DROP FUNCTION pg_catalog.citus_disable_node(nodename text, nodeport integer, force bool);
CREATE FUNCTION pg_catalog.citus_disable_node(nodename text, nodeport integer, synchronous bool default false)
 RETURNS void
 LANGUAGE C STRICT
 AS 'MODULE_PATHNAME', $$citus_disable_node$$;
COMMENT ON FUNCTION pg_catalog.citus_disable_node(nodename text, nodeport integer, synchronous bool)
 IS 'removes node from the cluster temporarily';
REVOKE ALL ON FUNCTION pg_catalog.citus_disable_node(text,int, bool) FROM PUBLIC;
-- run_command_on_coordinator tries to closely follow the semantics of run_command_on_all_nodes,
-- but only runs the command on the coordinator
CREATE FUNCTION pg_catalog.run_command_on_coordinator(command text, give_warning_for_connection_errors bool default false,
               OUT nodeid int, OUT success bool, OUT result text)
 RETURNS SETOF record
 LANGUAGE plpgsql
 AS $function$
DECLARE
 nodenames text[];
 ports int[];
 commands text[];
 coordinator_is_in_metadata boolean;
 parallel boolean := false;
BEGIN
 WITH citus_nodes AS (
  SELECT * FROM pg_dist_node
  WHERE isactive AND nodecluster = current_setting('citus.cluster_name') AND groupid = 0
  AND (
   (current_setting('citus.use_secondary_nodes') = 'never' AND noderole = 'primary')
   OR
   (current_setting('citus.use_secondary_nodes') = 'always' AND noderole = 'secondary')
  )
  ORDER BY nodename, nodeport
 )
 SELECT array_agg(citus_nodes.nodename), array_agg(citus_nodes.nodeport), array_agg(command), count(*) > 0
 FROM citus_nodes
 INTO nodenames, ports, commands, coordinator_is_in_metadata;
 IF NOT coordinator_is_in_metadata THEN
  -- This will happen when we call this function on coordinator and
  -- the coordinator is not added to the metadata.
  -- We'll manually add current node to the lists to actually run on all nodes.
  -- But when the coordinator is not added to metadata and this function
  -- is called from a worker node, this will not be enough and we'll
  -- not be able run on all nodes.
  IF citus_is_coordinator() THEN
   SELECT
    array_append(nodenames, current_setting('citus.local_hostname')),
    array_append(ports, current_setting('port')::int),
    array_append(commands, command)
   INTO nodenames, ports, commands;
  ELSE
   RAISE EXCEPTION 'the coordinator is not added to the metadata'
   USING HINT = 'Add the node as a coordinator by using: SELECT citus_set_coordinator_host(''<hostname>'')';
  END IF;
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
CREATE OR REPLACE FUNCTION pg_catalog.start_metadata_sync_to_all_nodes()
 RETURNS bool
 LANGUAGE C
 STRICT
AS 'MODULE_PATHNAME', $$start_metadata_sync_to_all_nodes$$;
COMMENT ON FUNCTION pg_catalog.start_metadata_sync_to_all_nodes()
 IS 'sync metadata to all active primary nodes';
REVOKE ALL ON FUNCTION pg_catalog.start_metadata_sync_to_all_nodes() FROM PUBLIC;
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
    PERFORM start_metadata_sync_to_all_nodes();
  END;
  RETURN true;
END;
$$;
COMMENT ON FUNCTION pg_catalog.citus_finalize_upgrade_to_citus11(bool)
  IS 'finalizes upgrade to Citus';
REVOKE ALL ON FUNCTION pg_catalog.citus_finalize_upgrade_to_citus11(bool) FROM PUBLIC;
CREATE OR REPLACE PROCEDURE pg_catalog.citus_finish_citus_upgrade()
    LANGUAGE plpgsql
    SET search_path = pg_catalog
    AS $cppu$
DECLARE
    current_version_string text;
    last_upgrade_version_string text;
    last_upgrade_major_version int;
    last_upgrade_minor_version int;
    last_upgrade_sqlpatch_version int;
    performed_upgrade bool := false;
BEGIN
 SELECT extversion INTO current_version_string
 FROM pg_extension WHERE extname = 'citus';
 -- assume some arbitrarily old version when no last upgrade version is defined
 SELECT coalesce(metadata->>'last_upgrade_version', '8.0-1') INTO last_upgrade_version_string
 FROM pg_dist_node_metadata;
 SELECT r[1], r[2], r[3]
 FROM regexp_matches(last_upgrade_version_string,'([0-9]+)\.([0-9]+)-([0-9]+)','') r
 INTO last_upgrade_major_version, last_upgrade_minor_version, last_upgrade_sqlpatch_version;
 IF last_upgrade_major_version IS NULL OR last_upgrade_minor_version IS NULL OR last_upgrade_sqlpatch_version IS NULL THEN
  -- version string is not valid, use an arbitrarily old version number
  last_upgrade_major_version := 8;
  last_upgrade_minor_version := 0;
  last_upgrade_sqlpatch_version := 1;
 END IF;
 IF last_upgrade_major_version < 11 THEN
  PERFORM citus_finalize_upgrade_to_citus11();
  performed_upgrade := true;
 END IF;
 -- add new upgrade steps here
 IF NOT performed_upgrade THEN
  RAISE NOTICE 'already at the latest distributed schema version (%)', last_upgrade_version_string;
  RETURN;
 END IF;
 UPDATE pg_dist_node_metadata
 SET metadata = jsonb_set(metadata, array['last_upgrade_version'], to_jsonb(current_version_string));
END;
$cppu$;
COMMENT ON PROCEDURE pg_catalog.citus_finish_citus_upgrade()
    IS 'after upgrading Citus on all nodes call this function to upgrade the distributed schema';
