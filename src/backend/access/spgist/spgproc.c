/*-------------------------------------------------------------------------
 *
 * spgproc.c
 *    Common supporting procedures for SP-GiST opclasses.
 *
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *      src/backend/access/spgist/spgproc.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "debug_trace.h"

#include <math.h>

#include "access/spgist_private.h"
#include "utils/float.h"
#include "utils/fmgrprotos.h"
#include "utils/geo_decls.h"

#define point_point_distance(p1,p2) \
  DatumGetFloat8(DirectFunctionCall2(point_distance, \
                     PointPGetDatum(p1), PointPGetDatum(p2)))

/* Point-box distance in the assumption that box is aligned by axis */
static double
point_box_distance(Point *point, BOX *box)
{
  DBUG_TRACE;
  double result;
  double    dx,
            dy;

  if (isnan(point->x) || isnan(box->low.x) ||
      isnan(point->y) || isnan(box->low.y))
    return get_float8_nan();

  if (point->x < box->low.x)
    dx = box->low.x - point->x;
  else if (point->x > box->high.x)
    dx = point->x - box->high.x;
  else
    dx = 0.0;

  if (point->y < box->low.y)
    dy = box->low.y - point->y;
  else if (point->y > box->high.y)
    dy = point->y - box->high.y;
  else
    dy = 0.0;

  result = HYPOT(dx, dy);

  DBUG_PRINT("info", "point-box distance in the assumption that box is aligned by axis:%g", result);
  return result;
}

/*
 * Returns distances from given key to array of ordering scan keys.  Leaf key
 * is expected to be point, non-leaf key is expected to be box.  Scan key
 * arguments are expected to be points.
 */
double *
spg_key_orderbys_distances(Datum key, bool isLeaf,
                           ScanKey orderbys, int norderbys)
{
  DBUG_TRACE;
  int     sk_num;
  double result;
  double     *distances = (double *) palloc(norderbys * sizeof(double)),
              *distance = distances;

  if (isLeaf) {
    DBUG_PRINT("info", "return distances from given key to array of ordering scan keys(norderbys:%d, isLeaf:true)", norderbys);
  } else {
    DBUG_PRINT("info", "return distances from given key to array of ordering scan keys(norderbys:%d, isLeaf:false)", norderbys);
  }

  for (sk_num = 0; sk_num < norderbys; ++sk_num, ++orderbys, ++distance) {
    Point    *point = DatumGetPointP(orderbys->sk_argument);

    result = isLeaf ? point_point_distance(point, DatumGetPointP(key))
             : point_box_distance(point, DatumGetBoxP(key));
    DBUG_PRINT("info", "distance:%g for sk_num:%d", result, sk_num);
    *distance = result;
  }

  return distances;
}

BOX *
box_copy(BOX *orig)
{
  BOX      *result = palloc(sizeof(BOX));

  *result = *orig;
  return result;
}
