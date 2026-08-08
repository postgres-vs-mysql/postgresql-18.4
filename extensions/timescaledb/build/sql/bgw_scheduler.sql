-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE OR REPLACE FUNCTION _timescaledb_functions.restart_background_workers()
RETURNS BOOL
AS '$libdir/timescaledb', 'ts_bgw_db_workers_restart'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.stop_background_workers()
RETURNS BOOL
AS '$libdir/timescaledb', 'ts_bgw_db_workers_stop'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION _timescaledb_functions.start_background_workers()
RETURNS BOOL
AS '$libdir/timescaledb', 'ts_bgw_db_workers_start'
LANGUAGE C VOLATILE;
