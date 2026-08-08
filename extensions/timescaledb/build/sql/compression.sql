-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_data_to_array(_timescaledb_internal.compressed_data, ANYELEMENT)
   RETURNS ANYARRAY
   AS '$libdir/timescaledb-2.27.0-dev', 'ts_compressed_data_to_array'
   LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.compressed_data_column_size(_timescaledb_internal.compressed_data, ANYELEMENT)
   RETURNS INTEGER
   AS '$libdir/timescaledb-2.27.0-dev', 'ts_compressed_data_column_size'
   LANGUAGE C IMMUTABLE PARALLEL SAFE;

