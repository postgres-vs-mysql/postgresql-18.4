-- List of functions

CREATE FUNCTION vchordrq_sampled_values(regclass) RETURNS SETOF TEXT
STRICT LANGUAGE c AS 'MODULE_PATHNAME', '_vchordrq_sampled_values_wrapper';

CREATE FUNCTION vchordrq_sampled_queries(regclass)
RETURNS TABLE(
    schema_name NAME,
    index_name NAME,
    table_name NAME,
    column_name NAME,
    operator NAME,
    value TEXT
)
STRICT LANGUAGE plpgsql AS $$
DECLARE
    ext_schema TEXT;
    query_text TEXT;
BEGIN
    SELECT n.nspname
    INTO ext_schema
    FROM pg_catalog.pg_extension e
    JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'vchord';

    IF ext_schema IS NULL THEN
        RAISE EXCEPTION 'vchord is not installed';
    END IF;

    query_text := format(
        $q$
        WITH index_metadata AS (
            SELECT
                NS.nspname AS schema_name,
                I.relname AS index_name,
                C.relname AS table_name,
                PA.attname AS column_name,
                OP.oprname AS operator
            FROM
                pg_catalog.pg_index X
            JOIN
                pg_catalog.pg_class C ON C.oid = X.indrelid
            JOIN
                pg_catalog.pg_namespace NS ON C.relnamespace = NS.oid
            JOIN
                pg_catalog.pg_class I ON I.oid = X.indexrelid
            JOIN
                pg_catalog.pg_am A ON A.oid = I.relam
            LEFT JOIN
                pg_catalog.pg_opclass AS OPC ON OPC.oid = X.indclass[0]
            LEFT JOIN
                pg_catalog.pg_amop AO ON OPC.opcfamily = AO.amopfamily
            LEFT JOIN
                pg_catalog.pg_operator OP ON OP.oid = AO.amopopr
            LEFT JOIN
                pg_catalog.pg_attribute PA ON PA.attrelid = X.indrelid AND PA.attnum = X.indkey[0]
            WHERE
                A.amname = 'vchordrq'
                AND AO.amopstrategy = 1
                AND C.relkind = 'r'
                AND X.indnatts = 1
                AND X.indexrelid = %1$s
        )
        SELECT
            im.schema_name,
            im.index_name,
            im.table_name,
            im.column_name,
            im.operator,
            s.value
        FROM
            index_metadata im,
            LATERAL %2$I.vchordrq_sampled_values(%1$s) AS s(value);
        $q$,
        $1::oid,
        ext_schema
    );
    RETURN QUERY EXECUTE query_text;
END;
$$;

-- List of views

CREATE VIEW vchordrq_sampled_queries AS
SELECT
    record.schema_name,
    record.index_name,
    record.table_name,
    record.column_name,
    record.operator,
    record.value
FROM
    (
        SELECT i.oid
        FROM pg_catalog.pg_class AS i
        JOIN pg_catalog.pg_index AS ix ON i.oid = ix.indexrelid
        JOIN pg_catalog.pg_opclass AS opc ON ix.indclass[0] = opc.oid
        JOIN pg_catalog.pg_am AS am ON opc.opcmethod = am.oid
        WHERE am.amname = 'vchordrq'
    ) AS index_oids
CROSS JOIN LATERAL vchordrq_sampled_queries(index_oids.oid::regclass) AS record;
