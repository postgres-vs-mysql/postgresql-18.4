-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- DROP some chunks to test metadata cleanup
\if :WITH_CHUNK
DROP TABLE _timescaledb_internal._hyper_1_2_chunk;
DROP TABLE _timescaledb_internal._hyper_1_3_chunk;
\endif
