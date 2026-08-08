-- citus--11.2-1--11.3-1
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
ALTER TABLE pg_catalog.pg_dist_authinfo REPLICA IDENTITY USING INDEX pg_dist_authinfo_identification_index;
ALTER TABLE pg_catalog.pg_dist_partition REPLICA IDENTITY USING INDEX pg_dist_partition_logical_relid_index;
ALTER TABLE pg_catalog.pg_dist_placement REPLICA IDENTITY USING INDEX pg_dist_placement_placementid_index;
ALTER TABLE pg_catalog.pg_dist_rebalance_strategy REPLICA IDENTITY USING INDEX pg_dist_rebalance_strategy_name_key;
ALTER TABLE pg_catalog.pg_dist_shard REPLICA IDENTITY USING INDEX pg_dist_shard_shardid_index;
ALTER TABLE pg_catalog.pg_dist_transaction REPLICA IDENTITY USING INDEX pg_dist_transaction_unique_constraint;
 -- During metadata sync, when we send many ddls over single transaction, worker node can error due
-- to reaching at max allocation block size for invalidation messages. To find a workaround for the problem,
-- we added nontransactional metadata sync mode where we create many transaction while dropping shell tables
-- via https:
CREATE OR REPLACE PROCEDURE pg_catalog.worker_drop_all_shell_tables(singleTransaction bool DEFAULT true)
LANGUAGE plpgsql
AS $$
DECLARE
    table_name text;
BEGIN
    -- drop shell tables within single or multiple transactions according to the flag singleTransaction
    FOR table_name IN SELECT logicalrelid::regclass::text FROM pg_dist_partition
    LOOP
        PERFORM pg_catalog.worker_drop_shell_table(table_name);
        IF not singleTransaction THEN
            COMMIT;
        END IF;
    END LOOP;
END;
$$;
COMMENT ON PROCEDURE worker_drop_all_shell_tables(singleTransaction bool)
    IS 'drop all distributed tables only without the metadata within single transaction or '
        'multiple transaction specified by the flag singleTransaction';
CREATE OR REPLACE FUNCTION pg_catalog.citus_internal_mark_node_not_synced(parent_pid int, nodeid int)
    RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$citus_internal_mark_node_not_synced$$;
COMMENT ON FUNCTION citus_internal_mark_node_not_synced(int, int)
    IS 'marks given node not synced by unsetting metadatasynced column at the start of the nontransactional sync.';
CREATE OR REPLACE FUNCTION pg_catalog.citus_stat_tenants_local(
    return_all_tenants BOOLEAN DEFAULT FALSE,
    OUT colocation_id INT,
    OUT tenant_attribute TEXT,
    OUT read_count_in_this_period INT,
    OUT read_count_in_last_period INT,
    OUT query_count_in_this_period INT,
    OUT query_count_in_last_period INT,
    OUT cpu_usage_in_this_period DOUBLE PRECISION,
    OUT cpu_usage_in_last_period DOUBLE PRECISION,
    OUT score BIGINT)
RETURNS SETOF RECORD
LANGUAGE C
AS 'citus', $$citus_stat_tenants_local$$;
CREATE OR REPLACE VIEW citus.citus_stat_tenants_local AS
SELECT
    colocation_id,
    tenant_attribute,
    read_count_in_this_period,
    read_count_in_last_period,
    query_count_in_this_period,
    query_count_in_last_period,
    cpu_usage_in_this_period,
    cpu_usage_in_last_period
FROM pg_catalog.citus_stat_tenants_local()
ORDER BY score DESC;
ALTER VIEW citus.citus_stat_tenants_local SET SCHEMA pg_catalog;
REVOKE ALL ON FUNCTION pg_catalog.citus_stat_tenants_local(BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_catalog.citus_stat_tenants_local(BOOLEAN) TO pg_monitor;
REVOKE ALL ON pg_catalog.citus_stat_tenants_local FROM PUBLIC;
GRANT SELECT ON pg_catalog.citus_stat_tenants_local TO pg_monitor;
-- cts in the query is an abbreviation for citus_stat_tenants
CREATE OR REPLACE FUNCTION pg_catalog.citus_stat_tenants (
    return_all_tenants BOOLEAN DEFAULT FALSE,
    OUT nodeid INT,
    OUT colocation_id INT,
    OUT tenant_attribute TEXT,
    OUT read_count_in_this_period INT,
    OUT read_count_in_last_period INT,
    OUT query_count_in_this_period INT,
    OUT query_count_in_last_period INT,
    OUT cpu_usage_in_this_period DOUBLE PRECISION,
    OUT cpu_usage_in_last_period DOUBLE PRECISION,
    OUT score BIGINT
)
    RETURNS SETOF record
    LANGUAGE plpgsql
    AS $function$
BEGIN
    IF
        array_position(enumvals, 'log') >= array_position(enumvals, setting)
        AND setting != 'off'
        FROM pg_settings
        WHERE name = 'citus.stat_tenants_log_level'
    THEN
        RAISE LOG 'Generating citus_stat_tenants';
    END IF;
    RETURN QUERY
    SELECT *
    FROM jsonb_to_recordset((
        SELECT
            jsonb_agg(all_cst_rows_as_jsonb.cst_row_as_jsonb)::jsonb
        FROM (
            SELECT
                jsonb_array_elements(run_command_on_all_nodes.result::jsonb)::jsonb ||
                    ('{"nodeid":' || run_command_on_all_nodes.nodeid || '}')::jsonb AS cst_row_as_jsonb
            FROM
                run_command_on_all_nodes (
                    $$
                        SELECT
                            coalesce(to_jsonb (array_agg(cstl.*)), '[]'::jsonb)
                        FROM citus_stat_tenants_local($$||return_all_tenants||$$) cstl;
                    $$,
                    parallel:= TRUE,
                    give_warning_for_connection_errors:= TRUE)
            WHERE
                success = 't')
        AS all_cst_rows_as_jsonb))
AS (
    nodeid INT,
    colocation_id INT,
    tenant_attribute TEXT,
    read_count_in_this_period INT,
    read_count_in_last_period INT,
    query_count_in_this_period INT,
    query_count_in_last_period INT,
    cpu_usage_in_this_period DOUBLE PRECISION,
    cpu_usage_in_last_period DOUBLE PRECISION,
    score BIGINT
)
    ORDER BY score DESC
    LIMIT CASE WHEN NOT return_all_tenants THEN current_setting('citus.stat_tenants_limit')::BIGINT END;
END;
$function$;
CREATE OR REPLACE VIEW citus.citus_stat_tenants AS
SELECT
    nodeid,
    colocation_id,
    tenant_attribute,
    read_count_in_this_period,
    read_count_in_last_period,
    query_count_in_this_period,
    query_count_in_last_period,
    cpu_usage_in_this_period,
    cpu_usage_in_last_period
FROM pg_catalog.citus_stat_tenants(FALSE);
ALTER VIEW citus.citus_stat_tenants SET SCHEMA pg_catalog;
REVOKE ALL ON FUNCTION pg_catalog.citus_stat_tenants(BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_catalog.citus_stat_tenants(BOOLEAN) TO pg_monitor;
REVOKE ALL ON pg_catalog.citus_stat_tenants FROM PUBLIC;
GRANT SELECT ON pg_catalog.citus_stat_tenants TO pg_monitor;
CREATE OR REPLACE FUNCTION pg_catalog.citus_stat_tenants_local_reset()
    RETURNS VOID
    LANGUAGE C STRICT
AS 'MODULE_PATHNAME', $$citus_stat_tenants_local_reset$$;
COMMENT ON FUNCTION pg_catalog.citus_stat_tenants_local_reset()
    IS 'resets the local tenant statistics';
CREATE OR REPLACE FUNCTION pg_catalog.citus_stat_tenants_reset()
    RETURNS VOID
    LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM run_command_on_all_nodes($$SELECT citus_stat_tenants_local_reset()$$);
END;
$function$;
-- we introduce nodes_involved, which will be used internally to
-- limit the number of parallel tasks running per node
ALTER TABLE pg_catalog.pg_dist_background_task ADD COLUMN nodes_involved int[] DEFAULT NULL;
