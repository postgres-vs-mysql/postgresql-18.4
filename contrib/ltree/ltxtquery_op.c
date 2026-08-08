/*
 * txtquery operations with ltree
 * Teodor Sigaev <teodor@stack.net>
 * contrib/ltree/ltxtquery_op.c
 */
#include "postgres.h"
#include "debug_trace.h"

#include <ctype.h>

#include "ltree.h"
#include "miscadmin.h"

PG_FUNCTION_INFO_V1(ltxtq_exec);
PG_FUNCTION_INFO_V1(ltxtq_rexec);

/*
 * check for boolean condition
 */
bool
ltree_execute(ITEM *curitem, void *checkval, bool calcnot, bool (*chkcond) (void *checkval, ITEM *val))
{
  DBUG_TRACE;
  bool result;
  /* since this function recurses, it could be driven to stack overflow */
  check_stack_depth();

  DBUG_PRINT("ltree", "check for boolean condition");

  if (curitem->type == VAL) {
    result = (*chkcond) (checkval, curitem);

    if (result) {
      DBUG_PRINT("ltree", "return true");
    } else {
      DBUG_PRINT("ltree", "return false");
    }

    return result;
  } else if (curitem->val == (int32) '!') {
    result = calcnot ?
             ((ltree_execute(curitem + 1, checkval, calcnot, chkcond)) ? false : true)
             : true;

    if (result) {
      DBUG_PRINT("ltree", "return true");
    } else {
      DBUG_PRINT("ltree", "return false");
    }

    return result;
  } else if (curitem->val == (int32) '&') {
    if (ltree_execute(curitem + curitem->left, checkval, calcnot, chkcond)) {
      result = ltree_execute(curitem + 1, checkval, calcnot, chkcond);

      if (result) {
        DBUG_PRINT("ltree", "return true");
      } else {
        DBUG_PRINT("ltree", "return false");
      }

      return result;
    } else {
      DBUG_PRINT("ltree", "return false");
      return false;
    }
  } else {
    /* |-operator */
    DBUG_PRINT("ltree", "|-operator");

    if (ltree_execute(curitem + curitem->left, checkval, calcnot, chkcond)) {
      DBUG_PRINT("ltree", "return true");
      return true;
    } else {
      result = ltree_execute(curitem + 1, checkval, calcnot, chkcond);

      if (result) {
        DBUG_PRINT("ltree", "return true");
      } else {
        DBUG_PRINT("ltree", "return false");
      }

      return result;
    }
  }
}

typedef struct {
  ltree    *node;
  char     *operand;
} CHKVAL;

static bool
checkcondition_str(void *checkval, ITEM *val)
{
  DBUG_TRACE;
  ltree_level *level = LTREE_FIRST(((CHKVAL *) checkval)->node);
  int     tlen = ((CHKVAL *) checkval)->node->numlevel;
  char     *op = ((CHKVAL *) checkval)->operand + val->distance;
  bool    prefix = (val->flag & LVAR_ANYEND);
  bool    ci = (val->flag & LVAR_INCASE);

  while (tlen > 0) {
    if (val->flag & LVAR_SUBLEXEME) {
      if (compare_subnode(level, op, val->length, prefix, ci)) {
        DBUG_PRINT("ltree", "return true");
        return true;
      }
    } else if (ltree_label_match(op, val->length, level->name, level->len,
                                 prefix, ci)) {
      DBUG_PRINT("ltree", "return true");
      return true;
    }

    tlen--;
    level = LEVEL_NEXT(level);
  }

  DBUG_PRINT("ltree", "return false");
  return false;
}

Datum
ltxtq_exec(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  ltree    *val = PG_GETARG_LTREE_P(0);
  ltxtquery  *query = PG_GETARG_LTXTQUERY_P(1);
  CHKVAL    chkval;
  bool    result;

  chkval.node = val;
  chkval.operand = GETOPERAND(query);

  result = ltree_execute(GETQUERY(query),
                         &chkval,
                         true,
                         checkcondition_str);

  PG_FREE_IF_COPY(val, 0);
  PG_FREE_IF_COPY(query, 1);

  if (result) {
    DBUG_PRINT("ltree", "return true");
  } else {
    DBUG_PRINT("ltree", "return false");
  }

  PG_RETURN_BOOL(result);
}

Datum
ltxtq_rexec(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  PG_RETURN_DATUM(DirectFunctionCall2(ltxtq_exec,
                                      PG_GETARG_DATUM(1),
                                      PG_GETARG_DATUM(0)
                                     ));
}
