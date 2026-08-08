/*-------------------------------------------------------------------------
 *
 * version.c
 *   Returns the PostgreSQL version string
 *
 * Copyright (c) 1998-2025, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *
 * src/backend/utils/adt/version.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "debug_trace.h"

#include "utils/builtins.h"


Datum
pgsql_version(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  PG_RETURN_TEXT_P(cstring_to_text(PG_VERSION_STR));
}
