-- columnar--9.5-1--10.0-1.sql
CREATE SCHEMA columnar;
SET search_path TO columnar;
CREATE SEQUENCE storageid_seq MINVALUE 10000000000 NO CYCLE;
CREATE TABLE options (
    regclass regclass NOT NULL PRIMARY KEY,
    chunk_group_row_limit int NOT NULL,
    stripe_row_limit int NOT NULL,
    compression_level int NOT NULL,
    compression name NOT NULL
) WITH (user_catalog_table = true);
COMMENT ON TABLE options IS 'columnar table specific options, maintained by alter_columnar_table_set';
CREATE TABLE stripe (
    storage_id bigint NOT NULL,
    stripe_num bigint NOT NULL,
    file_offset bigint NOT NULL,
    data_length bigint NOT NULL,
    column_count int NOT NULL,
    chunk_row_count int NOT NULL,
    row_count bigint NOT NULL,
    chunk_group_count int NOT NULL,
    PRIMARY KEY (storage_id, stripe_num)
) WITH (user_catalog_table = true);
COMMENT ON TABLE stripe IS 'Columnar per stripe metadata';
CREATE TABLE chunk_group (
    storage_id bigint NOT NULL,
    stripe_num bigint NOT NULL,
    chunk_group_num int NOT NULL,
    row_count bigint NOT NULL,
    PRIMARY KEY (storage_id, stripe_num, chunk_group_num),
    FOREIGN KEY (storage_id, stripe_num) REFERENCES stripe(storage_id, stripe_num) ON DELETE CASCADE
);
COMMENT ON TABLE chunk_group IS 'Columnar chunk group metadata';
CREATE TABLE chunk (
    storage_id bigint NOT NULL,
    stripe_num bigint NOT NULL,
    attr_num int NOT NULL,
    chunk_group_num int NOT NULL,
    minimum_value bytea,
    maximum_value bytea,
    value_stream_offset bigint NOT NULL,
    value_stream_length bigint NOT NULL,
    exists_stream_offset bigint NOT NULL,
    exists_stream_length bigint NOT NULL,
    value_compression_type int NOT NULL,
    value_compression_level int NOT NULL,
    value_decompressed_length bigint NOT NULL,
    value_count bigint NOT NULL,
    PRIMARY KEY (storage_id, stripe_num, attr_num, chunk_group_num),
    FOREIGN KEY (storage_id, stripe_num, chunk_group_num) REFERENCES chunk_group(storage_id, stripe_num, chunk_group_num) ON DELETE CASCADE
) WITH (user_catalog_table = true);
COMMENT ON TABLE chunk IS 'Columnar per chunk metadata';
DO $proc$
BEGIN
-- from version 12 and up we have support for tableam's if installed on pg11 we can't
-- create the objects here. Instead we rely on citus_finish_pg_upgrade to be called by the
-- user instead to add the missing objects
IF substring(current_Setting('server_version'), '\d+')::int >= 12 THEN
  EXECUTE $$
CREATE OR REPLACE FUNCTION columnar.columnar_handler(internal)
    RETURNS table_am_handler
    LANGUAGE C
AS 'MODULE_PATHNAME', 'columnar_handler';
COMMENT ON FUNCTION columnar.columnar_handler(internal)
    IS 'internal function returning the handler for columnar tables';
-- postgres 11.8 does not support the syntax for table am, also it is seemingly trying
-- to parse the upgrade file and erroring on unknown syntax.
-- normally this section would not execute on postgres 11 anyway. To trick it to pass on
-- 11.8 we wrap the statement in a plpgsql block together with an EXECUTE. This is valid
-- syntax on 11.8 and will execute correctly in 12
DO $create_table_am$
BEGIN
EXECUTE 'CREATE ACCESS METHOD columnar TYPE TABLE HANDLER columnar.columnar_handler';
END $create_table_am$;
CREATE OR REPLACE FUNCTION pg_catalog.alter_columnar_table_set(
    table_name regclass,
    chunk_group_row_limit int DEFAULT NULL,
    stripe_row_limit int DEFAULT NULL,
    compression name DEFAULT null,
    compression_level int DEFAULT NULL)
    RETURNS void
    LANGUAGE C
AS 'MODULE_PATHNAME', 'alter_columnar_table_set';
COMMENT ON FUNCTION pg_catalog.alter_columnar_table_set(
    table_name regclass,
    chunk_group_row_limit int,
    stripe_row_limit int,
    compression name,
    compression_level int)
IS 'set one or more options on a columnar table, when set to NULL no change is made';
CREATE OR REPLACE FUNCTION pg_catalog.alter_columnar_table_reset(
    table_name regclass,
    chunk_group_row_limit bool DEFAULT false,
    stripe_row_limit bool DEFAULT false,
    compression bool DEFAULT false,
    compression_level bool DEFAULT false)
    RETURNS void
    LANGUAGE C
AS 'MODULE_PATHNAME', 'alter_columnar_table_reset';
COMMENT ON FUNCTION pg_catalog.alter_columnar_table_reset(
    table_name regclass,
    chunk_group_row_limit bool,
    stripe_row_limit bool,
    compression bool,
    compression_level bool)
IS 'reset on or more options on a columnar table to the system defaults';
  $$;
END IF;
END$proc$;
-- citus_internal.columnar_ensure_objects_exist is an internal helper function to create
-- missing objects, anything related to the table access methods.
-- Since the API for table access methods is only available in PG12 we can't create these
-- objects when Citus is installed in PG11. Once citus is installed on PG11 the user can
-- upgrade their database to PG12. Now they require the table access method objects that
-- we couldn't create before.
-- This internal function is called from `citus_finish_pg_upgrade` which the user is
-- required to call after a PG major upgrade.
CREATE OR REPLACE FUNCTION citus_internal.columnar_ensure_objects_exist()
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = pg_catalog
AS $ceoe$
BEGIN
-- when postgres is version 12 or above we need to create the tableam. If the tableam
-- exist we assume all objects have been created.
IF substring(current_Setting('server_version'), '\d+')::int >= 12 THEN
IF NOT EXISTS (SELECT 1 FROM pg_am WHERE amname = 'columnar') THEN
CREATE OR REPLACE FUNCTION columnar.columnar_handler(internal)
    RETURNS table_am_handler
    LANGUAGE C
AS 'MODULE_PATHNAME', 'columnar_handler';
COMMENT ON FUNCTION columnar.columnar_handler(internal)
    IS 'internal function returning the handler for columnar tables';
-- postgres 11.8 does not support the syntax for table am, also it is seemingly trying
-- to parse the upgrade file and erroring on unknown syntax.
-- normally this section would not execute on postgres 11 anyway. To trick it to pass on
-- 11.8 we wrap the statement in a plpgsql block together with an EXECUTE. This is valid
-- syntax on 11.8 and will execute correctly in 12
DO $create_table_am$
BEGIN
EXECUTE 'CREATE ACCESS METHOD columnar TYPE TABLE HANDLER columnar.columnar_handler';
END $create_table_am$;
CREATE OR REPLACE FUNCTION pg_catalog.alter_columnar_table_set(
    table_name regclass,
    chunk_group_row_limit int DEFAULT NULL,
    stripe_row_limit int DEFAULT NULL,
    compression name DEFAULT null,
    compression_level int DEFAULT NULL)
    RETURNS void
    LANGUAGE C
AS 'MODULE_PATHNAME', 'alter_columnar_table_set';
COMMENT ON FUNCTION pg_catalog.alter_columnar_table_set(
    table_name regclass,
    chunk_group_row_limit int,
    stripe_row_limit int,
    compression name,
    compression_level int)
IS 'set one or more options on a columnar table, when set to NULL no change is made';
CREATE OR REPLACE FUNCTION pg_catalog.alter_columnar_table_reset(
    table_name regclass,
    chunk_group_row_limit bool DEFAULT false,
    stripe_row_limit bool DEFAULT false,
    compression bool DEFAULT false,
    compression_level bool DEFAULT false)
    RETURNS void
    LANGUAGE C
AS 'MODULE_PATHNAME', 'alter_columnar_table_reset';
COMMENT ON FUNCTION pg_catalog.alter_columnar_table_reset(
    table_name regclass,
    chunk_group_row_limit bool,
    stripe_row_limit bool,
    compression bool,
    compression_level bool)
IS 'reset on or more options on a columnar table to the system defaults';
    -- add the missing objects to the extension
    ALTER EXTENSION citus ADD FUNCTION columnar.columnar_handler(internal);
    ALTER EXTENSION citus ADD ACCESS METHOD columnar;
    ALTER EXTENSION citus ADD FUNCTION pg_catalog.alter_columnar_table_set(
        table_name regclass,
        chunk_group_row_limit int,
        stripe_row_limit int,
        compression name,
        compression_level int);
    ALTER EXTENSION citus ADD FUNCTION pg_catalog.alter_columnar_table_reset(
        table_name regclass,
        chunk_group_row_limit bool,
        stripe_row_limit bool,
        compression bool,
        compression_level bool);
END IF;
END IF;
END;
$ceoe$;
COMMENT ON FUNCTION citus_internal.columnar_ensure_objects_exist()
    IS 'internal function to be called by pg_catalog.citus_finish_pg_upgrade responsible for creating the columnar objects';
RESET search_path;
