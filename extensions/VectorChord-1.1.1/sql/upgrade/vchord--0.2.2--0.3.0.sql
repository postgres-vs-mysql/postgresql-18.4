CREATE FUNCTION "_vchord_halfvec_operator_maxsim"(
    "lhs" halfvec[],
    "rhs" halfvec[]
) RETURNS real
IMMUTABLE STRICT PARALLEL SAFE
LANGUAGE c
AS 'MODULE_PATHNAME', '_vchord_halfvec_operator_maxsim_wrapper';

CREATE FUNCTION "_vchord_vector_operator_maxsim"(
    "lhs" vector[],
    "rhs" vector[]
) RETURNS real
IMMUTABLE STRICT PARALLEL SAFE
LANGUAGE c
AS 'MODULE_PATHNAME', '_vchord_vector_operator_maxsim_wrapper';

CREATE FUNCTION "_vchordrq_support_halfvec_maxsim_ops"() RETURNS TEXT
IMMUTABLE STRICT PARALLEL SAFE
LANGUAGE c
AS 'MODULE_PATHNAME', '_vchordrq_support_halfvec_maxsim_ops_wrapper';

CREATE FUNCTION "_vchordrq_support_vector_maxsim_ops"() RETURNS TEXT
IMMUTABLE STRICT PARALLEL SAFE
LANGUAGE c
AS 'MODULE_PATHNAME', '_vchordrq_support_vector_maxsim_ops_wrapper';

CREATE OPERATOR @# (
    PROCEDURE = _vchord_vector_operator_maxsim,
    LEFTARG = vector[],
    RIGHTARG = vector[]
);

CREATE OPERATOR @# (
    PROCEDURE = _vchord_halfvec_operator_maxsim,
    LEFTARG = halfvec[],
    RIGHTARG = halfvec[]
);

CREATE OPERATOR FAMILY vector_maxsim_ops USING vchordrq;

CREATE OPERATOR FAMILY halfvec_maxsim_ops USING vchordrq;

CREATE OPERATOR CLASS vector_maxsim_ops
    FOR TYPE vector[] USING vchordrq FAMILY vector_maxsim_ops AS
    OPERATOR 3 @# (vector[], vector[]) FOR ORDER BY float_ops,
    FUNCTION 1 _vchordrq_support_vector_maxsim_ops();

CREATE OPERATOR CLASS halfvec_maxsim_ops
    FOR TYPE halfvec[] USING vchordrq FAMILY halfvec_maxsim_ops AS
    OPERATOR 3 @# (halfvec[], halfvec[]) FOR ORDER BY float_ops,
    FUNCTION 1 _vchordrq_support_halfvec_maxsim_ops();
