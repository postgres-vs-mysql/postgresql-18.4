/*-------------------------------------------------------------------------
 *
 * table.c
 *    Generic routines for table related code.
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *    src/backend/access/table/table.c
 *
 *
 * NOTES
 *    This file contains table_ routines that implement access to tables (in
 *    contrast to other relation types like indexes) that are independent of
 *    individual table access methods.
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "debug_trace.h"

#include "access/relation.h"
#include "access/table.h"
#include "utils/rel.h"

static inline void validate_relation_kind(Relation r);

/* Names of lock modes, for debug printouts */
static const char *const lock_mode_names[] = {
  "INVALID",
  "AccessShareLock",
  "RowShareLock",
  "RowExclusiveLock",
  "ShareUpdateExclusiveLock",
  "ShareLock",
  "ShareRowExclusiveLock",
  "ExclusiveLock",
  "AccessExclusiveLock"
};
/* ----------------
 *    table_open - open a table relation by relation OID
 *
 *    This is essentially relation_open plus check that the relation
 *    is not an index nor a composite type.  (The caller should also
 *    check that it's not a view or foreign table before assuming it has
 *    storage.)
 * ----------------
 */
Relation
table_open(Oid relationId, LOCKMODE lockmode)
{
  DBUG_TRACE;
  Relation  r;

  r = relation_open(relationId, lockmode);

  validate_relation_kind(r);

  {
    const char *table_name = RelationGetRelationName(r);

    if (lockmode > 0) {
      DBUG_PRINT("info", "table open:%s, lockmode:%s",
                 table_name, lock_mode_names[lockmode]);
    } else {
      DBUG_PRINT("info", "table open:%s", table_name);
    }
  }
  return r;
}


/* ----------------
 *    try_table_open - open a table relation by relation OID
 *
 *    Same as table_open, except return NULL instead of failing
 *    if the relation does not exist.
 * ----------------
 */
Relation
try_table_open(Oid relationId, LOCKMODE lockmode)
{
  DBUG_TRACE;
  Relation  r;

  r = try_relation_open(relationId, lockmode);

  /* leave if table does not exist */
  if (!r)
    return NULL;

  validate_relation_kind(r);

  return r;
}

/* ----------------
 *    table_openrv - open a table relation specified
 *    by a RangeVar node
 *
 *    As above, but relation is specified by a RangeVar.
 * ----------------
 */
Relation
table_openrv(const RangeVar *relation, LOCKMODE lockmode)
{
  DBUG_TRACE;
  Relation  r;

  r = relation_openrv(relation, lockmode);

  validate_relation_kind(r);

  return r;
}

/* ----------------
 *    table_openrv_extended - open a table relation specified
 *    by a RangeVar node
 *
 *    As above, but optionally return NULL instead of failing for
 *    relation-not-found.
 * ----------------
 */
Relation
table_openrv_extended(const RangeVar *relation, LOCKMODE lockmode,
                      bool missing_ok)
{
  DBUG_TRACE;
  Relation  r;

  r = relation_openrv_extended(relation, lockmode, missing_ok);

  if (r)
    validate_relation_kind(r);

  return r;
}

/* ----------------
 *    table_close - close a table
 *
 *    If lockmode is not "NoLock", we then release the specified lock.
 *
 *    Note that it is often sensible to hold a lock beyond relation_close;
 *    in that case, the lock is released automatically at xact end.
 *    ----------------
 */
void
table_close(Relation relation, LOCKMODE lockmode)
{
  DBUG_TRACE;

  {
    const char *index_name = RelationGetRelationName(relation);

    if (index_name) {
      if (lockmode > 0) {
        DBUG_PRINT("info", "table close:%s, lockmode:%s",
                   index_name, lock_mode_names[lockmode]);
      } else {
        DBUG_PRINT("info", "table close:%s", index_name);
      }
    }
  }
  relation_close(relation, lockmode);
}

/* ----------------
 *    validate_relation_kind - check the relation's kind
 *
 *    Make sure relkind is not index or composite type
 * ----------------
 */
static inline void
validate_relation_kind(Relation r)
{
  if (r->rd_rel->relkind == RELKIND_INDEX ||
      r->rd_rel->relkind == RELKIND_PARTITIONED_INDEX ||
      r->rd_rel->relkind == RELKIND_COMPOSITE_TYPE)
    ereport(ERROR,
            (errcode(ERRCODE_WRONG_OBJECT_TYPE),
             errmsg("cannot open relation \"%s\"",
                    RelationGetRelationName(r)),
             errdetail_relkind_not_supported(r->rd_rel->relkind)));
}
