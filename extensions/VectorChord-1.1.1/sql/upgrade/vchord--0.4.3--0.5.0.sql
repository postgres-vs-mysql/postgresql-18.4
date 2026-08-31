-- internal changes

CREATE FUNCTION _vchordg_support_halfvec_cosine_ops() RETURNS TEXT
IMMUTABLE STRICT PARALLEL SAFE LANGUAGE c AS 'MODULE_PATHNAME', '_vchordg_support_halfvec_cosine_ops_wrapper';

CREATE FUNCTION _vchordg_support_halfvec_ip_ops() RETURNS TEXT
IMMUTABLE STRICT PARALLEL SAFE LANGUAGE c AS 'MODULE_PATHNAME', '_vchordg_support_halfvec_ip_ops_wrapper';

CREATE FUNCTION _vchordg_support_halfvec_l2_ops() RETURNS TEXT
IMMUTABLE STRICT PARALLEL SAFE LANGUAGE c AS 'MODULE_PATHNAME', '_vchordg_support_halfvec_l2_ops_wrapper';

CREATE FUNCTION _vchordg_support_vector_cosine_ops() RETURNS TEXT
IMMUTABLE STRICT PARALLEL SAFE LANGUAGE c AS 'MODULE_PATHNAME', '_vchordg_support_vector_cosine_ops_wrapper';

CREATE FUNCTION _vchordg_support_vector_ip_ops() RETURNS TEXT
IMMUTABLE STRICT PARALLEL SAFE LANGUAGE c AS 'MODULE_PATHNAME', '_vchordg_support_vector_ip_ops_wrapper';

CREATE FUNCTION _vchordg_support_vector_l2_ops() RETURNS TEXT
IMMUTABLE STRICT PARALLEL SAFE LANGUAGE c AS 'MODULE_PATHNAME', '_vchordg_support_vector_l2_ops_wrapper';

-- List of functions

CREATE FUNCTION vchordrq_evaluate_query_recall(
    query text,
    exact_search boolean default false,
    accu_probes TEXT default NULL,
    accu_epsilon real default 1.9
)
RETURNS real
LANGUAGE plpgsql
AS $$
DECLARE
    rough tid[];
    accu tid[];
    match_count integer := 0;
    accu_k integer;
    recall real;
    rough_probes text;
BEGIN
    IF query IS NULL OR exact_search IS NULL OR accu_epsilon IS NULL THEN
        RETURN NULL;
    END IF;
    IF query LIKE '%@#%' AND NOT exact_search THEN
        RAISE EXCEPTION 'MaxSim operator cannot be used for estimated recall evaluation. Please use exact_search => true.';
    END IF;
    IF NOT exact_search THEN
        BEGIN
            rough_probes := current_setting('vchordrq.probes');
        END;
    END IF;

    BEGIN
        EXECUTE
            format('SELECT coalesce(array_agg(id), array[]::tid[]) FROM (%s) AS result(id)', query)
        INTO
            rough;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Error executing ANN query "%": %', query, SQLERRM;
    END;

    BEGIN
        IF exact_search THEN
            SET LOCAL vchordrq.enable_scan = off;
        ELSE
            IF accu_probes IS NULL THEN
                IF rough_probes = '' THEN
                    accu_probes := '';
                ELSIF position(',' in rough_probes) > 0 THEN
                    accu_probes := '65535,65535';
                ELSE
                    accu_probes := '65535';
                END IF;
            END IF;
            EXECUTE format('SET LOCAL "vchordrq.probes" = %L', accu_probes);
            EXECUTE format('SET LOCAL "vchordrq.epsilon" = %L', accu_epsilon);
            SET LOCAL vchordrq.max_scan_tuples = -1;
        END IF;
        EXECUTE
            format('SELECT coalesce(array_agg(id), array[]::tid[]) FROM (%s) AS result(id)', query)
        INTO
            accu;
    EXCEPTION WHEN OTHERS THEN
         RAISE EXCEPTION 'Error executing Ground Truth query "%": %', query, SQLERRM;
    END;
    accu_k := cardinality(accu);
    IF accu_k = 0 THEN
        RAISE WARNING  'Query "%": No results found, returning NaN for recall.', query;
        RETURN 'NaN';
    END IF;
    SELECT COUNT(*) INTO match_count FROM (SELECT unnest(rough) INTERSECT SELECT unnest(accu)) AS tids;
    recall := match_count::real / accu_k::real;
    RETURN recall;
END;
$$;

CREATE FUNCTION vchordg_amhandler(internal) RETURNS index_am_handler
IMMUTABLE STRICT PARALLEL SAFE LANGUAGE c AS 'MODULE_PATHNAME', '_vchordg_amhandler_wrapper';

CREATE FUNCTION vchordg_prewarm(regclass) RETURNS TEXT
STRICT LANGUAGE c AS 'MODULE_PATHNAME', '_vchordg_prewarm_wrapper';

-- List of access methods

CREATE ACCESS METHOD vchordg TYPE INDEX HANDLER vchordg_amhandler;

-- List of operator families

CREATE OPERATOR FAMILY vector_l2_ops USING vchordg;
CREATE OPERATOR FAMILY vector_ip_ops USING vchordg;
CREATE OPERATOR FAMILY vector_cosine_ops USING vchordg;
CREATE OPERATOR FAMILY halfvec_l2_ops USING vchordg;
CREATE OPERATOR FAMILY halfvec_ip_ops USING vchordg;
CREATE OPERATOR FAMILY halfvec_cosine_ops USING vchordg;

-- List of operator classes

CREATE OPERATOR CLASS vector_l2_ops
    FOR TYPE vector USING vchordg FAMILY vector_l2_ops AS
    OPERATOR 1 <-> (vector, vector) FOR ORDER BY float_ops,
    OPERATOR 2 <<->> (vector, sphere_vector) FOR SEARCH,
    FUNCTION 1 _vchordg_support_vector_l2_ops();

CREATE OPERATOR CLASS vector_ip_ops
    FOR TYPE vector USING vchordg FAMILY vector_ip_ops AS
    OPERATOR 1 <#> (vector, vector) FOR ORDER BY float_ops,
    OPERATOR 2 <<#>> (vector, sphere_vector) FOR SEARCH,
    FUNCTION 1 _vchordg_support_vector_ip_ops();

CREATE OPERATOR CLASS vector_cosine_ops
    FOR TYPE vector USING vchordg FAMILY vector_cosine_ops AS
    OPERATOR 1 <=> (vector, vector) FOR ORDER BY float_ops,
    OPERATOR 2 <<=>> (vector, sphere_vector) FOR SEARCH,
    FUNCTION 1 _vchordg_support_vector_cosine_ops();

CREATE OPERATOR CLASS halfvec_l2_ops
    FOR TYPE halfvec USING vchordg FAMILY halfvec_l2_ops AS
    OPERATOR 1 <-> (halfvec, halfvec) FOR ORDER BY float_ops,
    OPERATOR 2 <<->> (halfvec, sphere_halfvec) FOR SEARCH,
    FUNCTION 1 _vchordg_support_halfvec_l2_ops();

CREATE OPERATOR CLASS halfvec_ip_ops
    FOR TYPE halfvec USING vchordg FAMILY halfvec_ip_ops AS
    OPERATOR 1 <#> (halfvec, halfvec) FOR ORDER BY float_ops,
    OPERATOR 2 <<#>> (halfvec, sphere_halfvec) FOR SEARCH,
    FUNCTION 1 _vchordg_support_halfvec_ip_ops();

CREATE OPERATOR CLASS halfvec_cosine_ops
    FOR TYPE halfvec USING vchordg FAMILY halfvec_cosine_ops AS
    OPERATOR 1 <=> (halfvec, halfvec) FOR ORDER BY float_ops,
    OPERATOR 2 <<=>> (halfvec, sphere_halfvec) FOR SEARCH,
    FUNCTION 1 _vchordg_support_halfvec_cosine_ops();
