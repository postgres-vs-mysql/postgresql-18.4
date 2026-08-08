DROP VIEW citus_shards;
DROP VIEW IF EXISTS pg_catalog.citus_tables;
DROP VIEW IF EXISTS public.citus_tables;
DROP FUNCTION citus_shard_sizes;
CREATE OR REPLACE FUNCTION pg_catalog.citus_shard_sizes(OUT shard_id int, OUT size bigint)
  RETURNS SETOF RECORD
  LANGUAGE C STRICT
  AS 'MODULE_PATHNAME', $$citus_shard_sizes$$;
 COMMENT ON FUNCTION pg_catalog.citus_shard_sizes(OUT shard_id int, OUT size bigint)
     IS 'returns shards sizes across citus cluster';
CREATE OR REPLACE VIEW citus.citus_shards AS
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
        pg_size_pretty(table_sizes.table_size) AS table_size,
        (select count(*) from pg_dist_shard where logicalrelid = p.logicalrelid) AS shard_count,
        pg_get_userbyid(relowner) AS table_owner,
        amname AS access_method
    FROM
        pg_dist_partition p
    JOIN
        pg_class c ON (p.logicalrelid = c.oid)
    LEFT JOIN
        pg_am a ON (a.oid = c.relam)
    JOIN
        (
            SELECT ds.logicalrelid AS table_id, SUM(css.size) AS table_size
            FROM citus_shard_sizes() css, pg_dist_shard ds
            WHERE css.shard_id = ds.shardid
            GROUP BY ds.logicalrelid
        ) table_sizes ON (table_sizes.table_id = p.logicalrelid)
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
