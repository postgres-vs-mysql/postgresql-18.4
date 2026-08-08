-- citus--11.2-1--11.2-2
-- Since we backported the UDF below from version 11.3, the definition is the same
CREATE OR REPLACE FUNCTION pg_catalog.worker_adjust_identity_column_seq_ranges(regclass)
    RETURNS VOID
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_adjust_identity_column_seq_ranges$$;
COMMENT ON FUNCTION pg_catalog.worker_adjust_identity_column_seq_ranges(regclass)
    IS 'modify identity column seq ranges to produce globally unique values';
