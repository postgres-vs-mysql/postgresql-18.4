-- citus--9.3-2--9.4-1
-- bump version to 9.4-1
CREATE OR REPLACE FUNCTION pg_catalog.worker_last_saved_explain_analyze()
    RETURNS TABLE(explain_analyze_output TEXT, execution_duration DOUBLE PRECISION)
    LANGUAGE C STRICT
    AS 'citus';
COMMENT ON FUNCTION pg_catalog.worker_last_saved_explain_analyze() IS
    'Returns the saved explain analyze output for the last run query';
CREATE OR REPLACE FUNCTION pg_catalog.worker_save_query_explain_analyze(
      query text, options jsonb)
    RETURNS SETOF record
    LANGUAGE C STRICT
    AS 'citus';
COMMENT ON FUNCTION pg_catalog.worker_save_query_explain_analyze(text, jsonb) IS
    'Executes and returns results of query while saving its EXPLAIN ANALYZE to be fetched later';
