/**********************************************************************
 *
 * PostGIS - Spatial Types for PostgreSQL
 * http://postgis.net
 *
 * PostGIS is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * PostGIS is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with PostGIS.  If not, see <http://www.gnu.org/licenses/>.
 *
 **********************************************************************
 *
 * Copyright (C) 2009 Paul Ramsey <pramsey@cleverelephant.ca>
 *
 **********************************************************************/


#include "debug_trace.h"
#include "postgres.h"
#include "catalog/pg_type.h" /* for CSTRINGOID */

#include "../postgis_config.h"

#include <math.h>
#include <float.h>
#include <string.h>
#include <stdio.h>

#include "liblwgeom.h"                  /* For standard geometry types. */
#include "liblwgeom_internal.h"         /* For FP comparators. */
#include "lwgeom_pg.h"                  /* For debugging macros. */
#include "geography.h"                  /* For utility functions. */
#include "geography_measurement_trees.h" /* For circ_tree caching */
#include "lwgeom_transform.h"            /* For SRID functions */

#ifdef PROJ_GEODESIC
/* round to 10 nm precision */
#define INVMINDIST 1.0e8
#else
/* round to 100 nm precision */
#define INVMINDIST 1.0e7
#endif

Datum geography_distance(PG_FUNCTION_ARGS);
Datum geography_distance_uncached(PG_FUNCTION_ARGS);
Datum geography_distance_knn(PG_FUNCTION_ARGS);
Datum geography_distance_tree(PG_FUNCTION_ARGS);
Datum geography_dwithin(PG_FUNCTION_ARGS);
Datum geography_dwithin_uncached(PG_FUNCTION_ARGS);
Datum geography_area(PG_FUNCTION_ARGS);
Datum geography_length(PG_FUNCTION_ARGS);
Datum geography_expand(PG_FUNCTION_ARGS);
Datum geography_point_outside(PG_FUNCTION_ARGS);
Datum geography_covers(PG_FUNCTION_ARGS);
Datum geography_coveredby(PG_FUNCTION_ARGS);
Datum geography_bestsrid(PG_FUNCTION_ARGS);
Datum geography_perimeter(PG_FUNCTION_ARGS);
Datum geography_project(PG_FUNCTION_ARGS);
Datum geography_azimuth(PG_FUNCTION_ARGS);
Datum geography_segmentize(PG_FUNCTION_ARGS);

Datum geography_line_locate_point(PG_FUNCTION_ARGS);
Datum geography_line_interpolate_point(PG_FUNCTION_ARGS);
Datum geography_line_substring(PG_FUNCTION_ARGS);
Datum geography_closestpoint(PG_FUNCTION_ARGS);
Datum geography_shortestline(PG_FUNCTION_ARGS);


PG_FUNCTION_INFO_V1(geography_distance_knn);
Datum geography_distance_knn(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom1 = NULL;
  LWGEOM *lwgeom2 = NULL;
  GSERIALIZED *g1 = NULL;
  GSERIALIZED *g2 = NULL;
  double distance;
  double tolerance = FP_TOLERANCE;
  bool use_spheroid = false; /* must use sphere, can't get index to harmonize with spheroid */
  SPHEROID s;

  /* Get our geometry objects loaded into memory. */
  DBUG_PRINT("postgis", "get our geometry objects loaded into memory");
  g1 = PG_GETARG_GSERIALIZED_P(0);
  g2 = PG_GETARG_GSERIALIZED_P(1);

  gserialized_error_if_srid_mismatch(g1, g2, __func__);

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g1), &s);

  /* Set to sphere if requested */
  if ( ! use_spheroid ) {
    DBUG_PRINT("postgis", "set to sphere if requested");
    s.a = s.b = s.radius;
  }

  lwgeom1 = lwgeom_from_gserialized(g1);
  lwgeom2 = lwgeom_from_gserialized(g2);

  /* Return NULL on empty arguments. */
  if ( lwgeom_is_empty(lwgeom1) || lwgeom_is_empty(lwgeom2) ) {
    DBUG_PRINT("postgis", "return NULL on empty arguments");
    PG_FREE_IF_COPY(g1, 0);
    PG_FREE_IF_COPY(g2, 1);
    PG_RETURN_NULL();
  }

  /* Make sure we have boxes attached */
  lwgeom_add_bbox_deep(lwgeom1, NULL);
  lwgeom_add_bbox_deep(lwgeom2, NULL);

  DBUG_PRINT("postgis", "calculate the distance between two LWGEOMs, using the coordinates are longitude and latitude");
  distance = lwgeom_distance_spheroid(lwgeom1, lwgeom2, &s, tolerance);

  POSTGIS_DEBUGF(2, "[GIST] '%s' got distance %g", __func__, distance);
  DBUG_PRINT("postgis", "[GIST] '%s' got distance %g", __func__, distance);

  /* Clean up */
  lwgeom_free(lwgeom1);
  lwgeom_free(lwgeom2);
  PG_FREE_IF_COPY(g1, 0);
  PG_FREE_IF_COPY(g2, 1);

  /* Something went wrong, negative return... should already be eloged, return NULL */
  if ( distance < 0.0 ) {
    PG_RETURN_NULL();
  }

  PG_RETURN_FLOAT8(distance);
}

/*
** geography_distance_uncached(GSERIALIZED *g1, GSERIALIZED *g2, double tolerance, boolean use_spheroid)
** returns double distance in meters
*/
PG_FUNCTION_INFO_V1(geography_distance_uncached);
Datum geography_distance_uncached(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom1 = NULL;
  LWGEOM *lwgeom2 = NULL;
  GSERIALIZED *g1 = PG_GETARG_GSERIALIZED_P(0);
  GSERIALIZED *g2 = PG_GETARG_GSERIALIZED_P(1);
  double distance;
  double tolerance = FP_TOLERANCE;
  bool use_spheroid = true;
  SPHEROID s;

  /* Read our tolerance value. */
  if ( PG_NARGS() > 2 && ! PG_ARGISNULL(2) ) {
    tolerance = PG_GETARG_FLOAT8(2);
    DBUG_PRINT("postgis", "read our tolerance value:%g", tolerance);
  }

  /* Read our calculation type. */
  if ( PG_NARGS() > 3 && ! PG_ARGISNULL(3) ) {
    use_spheroid = PG_GETARG_BOOL(3);

    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }
  }

  gserialized_error_if_srid_mismatch(g1, g2, __func__);

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g1), &s);

  /* Set to sphere if requested */
  if ( ! use_spheroid ) {
    DBUG_PRINT("postgis", "set to sphere if requested");
    s.a = s.b = s.radius;
  }

  lwgeom1 = lwgeom_from_gserialized(g1);
  lwgeom2 = lwgeom_from_gserialized(g2);

  /* Return NULL on empty arguments. */
  if ( !lwgeom1 || !lwgeom2 || lwgeom_is_empty(lwgeom1) || lwgeom_is_empty(lwgeom2) ) {
    DBUG_PRINT("postgis", "return NULL on empty arguments");
    PG_FREE_IF_COPY(g1, 0);
    PG_FREE_IF_COPY(g2, 1);
    PG_RETURN_NULL();
  }

  /* Make sure we have boxes attached */
  lwgeom_add_bbox_deep(lwgeom1, NULL);
  lwgeom_add_bbox_deep(lwgeom2, NULL);

  DBUG_PRINT("postgis", "calculate the distance between two LWGEOMs, using the coordinates are longitude and latitude");
  distance = lwgeom_distance_spheroid(lwgeom1, lwgeom2, &s, tolerance);
  DBUG_PRINT("postgis", "distance:%g", distance);

  /* Clean up */
  lwgeom_free(lwgeom1);
  lwgeom_free(lwgeom2);
  PG_FREE_IF_COPY(g1, 0);
  PG_FREE_IF_COPY(g2, 1);

  /* Something went wrong, negative return... should already be eloged, return NULL */
  if ( distance < 0.0 ) {
    PG_RETURN_NULL();
  }

  PG_RETURN_FLOAT8(distance);
}


/*
** geography_distance(GSERIALIZED *g1, GSERIALIZED *g2, double tolerance, boolean use_spheroid)
** returns double distance in meters
*/
PG_FUNCTION_INFO_V1(geography_distance);
Datum geography_distance(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  SHARED_GSERIALIZED *shared_geom1 = ToastCacheGetGeometry(fcinfo, 0);
  SHARED_GSERIALIZED *shared_geom2 = ToastCacheGetGeometry(fcinfo, 1);
  const GSERIALIZED *g1 = shared_gserialized_get(shared_geom1);
  const GSERIALIZED *g2 = shared_gserialized_get(shared_geom2);
  double distance;
  bool use_spheroid = true;
  SPHEROID s;

  if (PG_NARGS() > 2) {
    use_spheroid = PG_GETARG_BOOL(2);

    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }
  }

  gserialized_error_if_srid_mismatch(g1, g2, __func__);

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g1), &s);

  /* Set to sphere if requested */
  if ( ! use_spheroid ) {
    DBUG_PRINT("postgis", "set to sphere if requested");
    s.a = s.b = s.radius;
  }

  /* Return NULL on empty arguments. */
  if ( gserialized_is_empty(g1) || gserialized_is_empty(g2) ) {
    DBUG_PRINT("postgis", "return NULL on empty arguments");
    PG_RETURN_NULL();
  }

  /* Do the brute force calculation if the cached calculation doesn't tick over */
  if (LW_FAILURE == geography_distance_cache(fcinfo, shared_geom1, shared_geom2, &s, &distance)) {
    DBUG_PRINT("postgis", "do the brute force calculation if the cached calculation doesn't tick over");
    /* default to using tree-based distance calculation at all times */
    /* in standard distance call. */
    geography_tree_distance(g1, g2, &s, FP_TOLERANCE, &distance);
    /*
    LWGEOM* lwgeom1 = lwgeom_from_gserialized(g1);
    LWGEOM* lwgeom2 = lwgeom_from_gserialized(g2);
    distance = lwgeom_distance_spheroid(lwgeom1, lwgeom2, &s, tolerance);
    lwgeom_free(lwgeom1);
    lwgeom_free(lwgeom2);
    */
  }

  /* Knock off any funny business at the nanometer level, ticket #2168 */
  distance = round(distance * INVMINDIST) / INVMINDIST;
  DBUG_PRINT("postgis", "knock off any funny business at the nanometer level and distance:%g", distance);

  /* Something went wrong, negative return... should already be eloged, return NULL */
  if ( distance < 0.0 ) {
    DBUG_INSTANT_PRINT("postgis", "distance returned negative!");
    elog(ERROR, "distance returned negative!");
    PG_RETURN_NULL();
  }

  PG_RETURN_FLOAT8(distance);
}

/*
** geography_dwithin(GSERIALIZED *g1, GSERIALIZED *g2, double tolerance, boolean use_spheroid)
** returns double distance in meters
*/
PG_FUNCTION_INFO_V1(geography_dwithin);
Datum geography_dwithin(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  SHARED_GSERIALIZED *shared_geom1 = ToastCacheGetGeometry(fcinfo, 0);
  SHARED_GSERIALIZED *shared_geom2 = ToastCacheGetGeometry(fcinfo, 1);
  const GSERIALIZED *g1 = shared_gserialized_get(shared_geom1);
  const GSERIALIZED *g2 = shared_gserialized_get(shared_geom2);
  SPHEROID s;
  double tolerance = FP_TOLERANCE;
  bool use_spheroid = true;
  double distance;
  int dwithin = LW_FALSE;

  gserialized_error_if_srid_mismatch(g1, g2, __func__);

  /* Read our tolerance value. */
  if ( PG_NARGS() > 2 && ! PG_ARGISNULL(2) ) {
    tolerance = PG_GETARG_FLOAT8(2);
    DBUG_PRINT("postgis", "read our tolerance value:%g", tolerance);
  }

  /* Read our calculation type. */
  if ( PG_NARGS() > 3 && ! PG_ARGISNULL(3) ) {
    use_spheroid = PG_GETARG_BOOL(3);

    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }

  }

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g1), &s);

  /* Set to sphere if requested */
  if ( ! use_spheroid ) {
    DBUG_PRINT("postgis", "set to sphere if requested");
    s.a = s.b = s.radius;
  }

  /* Return FALSE on empty arguments. */
  if ( gserialized_is_empty(g1) || gserialized_is_empty(g2) ) {
    DBUG_PRINT("postgis", "return FALSE on empty arguments");
    PG_RETURN_BOOL(false);
  }

  /* Do the brute force calculation if the cached calculation doesn't tick over */
  if (LW_FAILURE == geography_dwithin_cache(fcinfo, shared_geom1, shared_geom2, &s, tolerance, &dwithin)) {
    LWGEOM* lwgeom1 = lwgeom_from_gserialized(g1);
    LWGEOM* lwgeom2 = lwgeom_from_gserialized(g2);
    DBUG_PRINT("postgis", "calculate the distance between two LWGEOMs, using the coordinates are longitude and latitude");
    distance = lwgeom_distance_spheroid(lwgeom1, lwgeom2, &s, tolerance);
    DBUG_PRINT("postgis", "distance:%g, tolerance:%g", distance, tolerance);

    /* Something went wrong... */
    if ( distance < 0.0 )
      elog(ERROR, "lwgeom_distance_spheroid returned negative!");

    dwithin = (distance <= tolerance);
    lwgeom_free(lwgeom1);
    lwgeom_free(lwgeom2);
  }

  if (dwithin) {
    DBUG_PRINT("postgis", "return true");
  } else {
    DBUG_PRINT("postgis", "return false");
  }

  PG_RETURN_BOOL(dwithin);
}

PG_FUNCTION_INFO_V1(geography_intersects);
Datum geography_intersects(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  bool result = CallerFInfoFunctionCall2(geography_dwithin, fcinfo->flinfo, InvalidOid, PG_GETARG_DATUM(0), PG_GETARG_DATUM(1));

  if (result) {
    DBUG_PRINT("postgis", "return true");
  } else {
    DBUG_PRINT("postgis", "return false");
  }

  PG_RETURN_BOOL(result);
}

/*
** geography_distance_tree(GSERIALIZED *g1, GSERIALIZED *g2, double tolerance, boolean use_spheroid)
** returns double distance in meters
*/
PG_FUNCTION_INFO_V1(geography_distance_tree);
Datum geography_distance_tree(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  GSERIALIZED *g1 = NULL;
  GSERIALIZED *g2 = NULL;
  double tolerance = 0.0;
  double distance;
  bool use_spheroid = true;
  SPHEROID s;

  /* Get our geometry objects loaded into memory. */
  g1 = PG_GETARG_GSERIALIZED_P(0);
  g2 = PG_GETARG_GSERIALIZED_P(1);

  DBUG_PRINT("postgis", "get our geometry objects loaded into memory");
  gserialized_error_if_srid_mismatch(g1, g2, __func__);

  /* Return zero on empty arguments. */
  if ( gserialized_is_empty(g1) || gserialized_is_empty(g2) ) {
    DBUG_PRINT("postgis", "return zero on empty arguments");
    PG_FREE_IF_COPY(g1, 0);
    PG_FREE_IF_COPY(g2, 1);
    PG_RETURN_FLOAT8(0.0);
  }

  /* Read our tolerance value. */
  if ( PG_NARGS() > 2 && ! PG_ARGISNULL(2) ) {
    tolerance = PG_GETARG_FLOAT8(2);
    DBUG_PRINT("postgis", "read our tolerance value:%g", tolerance);
  }

  /* Read our calculation type. */
  if ( PG_NARGS() > 3 && ! PG_ARGISNULL(3) ) {
    use_spheroid = PG_GETARG_BOOL(3);

    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }
  }

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g1), &s);

  /* Set to sphere if requested */
  if ( ! use_spheroid )
    DBUG_PRINT("postgis", "set to sphere if requested");

  s.a = s.b = s.radius;

  if  ( geography_tree_distance(g1, g2, &s, tolerance, &distance) == LW_FAILURE ) {
    elog(ERROR, "geography_distance_tree failed!");
    PG_RETURN_NULL();
  }

  /* Knock off any funny business at the nanometer level, ticket #2168 */
  distance = round(distance * INVMINDIST) / INVMINDIST;

  DBUG_PRINT("postgis", "return distance:%g", distance);
  PG_RETURN_FLOAT8(distance);
}



/*
** geography_dwithin_uncached(GSERIALIZED *g1, GSERIALIZED *g2, double tolerance, boolean use_spheroid)
** returns double distance in meters
*/
PG_FUNCTION_INFO_V1(geography_dwithin_uncached);
Datum geography_dwithin_uncached(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom1 = NULL;
  LWGEOM *lwgeom2 = NULL;
  GSERIALIZED *g1 = NULL;
  GSERIALIZED *g2 = NULL;
  double tolerance = 0.0;
  double distance;
  bool use_spheroid = true;
  SPHEROID s;

  DBUG_PRINT("postgis", "return double distance in meters");

  /* Get our geometry objects loaded into memory. */
  DBUG_PRINT("postgis", "get our geometry objects loaded into memory");
  g1 = PG_GETARG_GSERIALIZED_P(0);
  g2 = PG_GETARG_GSERIALIZED_P(1);
  gserialized_error_if_srid_mismatch(g1, g2, __func__);

  /* Read our tolerance value. */
  if ( PG_NARGS() > 2 && ! PG_ARGISNULL(2) ) {
    tolerance = PG_GETARG_FLOAT8(2);
    DBUG_PRINT("postgis", "read our tolerance value:%g", tolerance);
  }

  /* Read our calculation type. */
  if ( PG_NARGS() > 3 && ! PG_ARGISNULL(3) ) {
    use_spheroid = PG_GETARG_BOOL(3);

    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }

  }

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g1), &s);

  /* Set to sphere if requested */
  if ( ! use_spheroid ) {
    DBUG_PRINT("postgis", "set to sphere if requested");
    s.a = s.b = s.radius;
  }

  lwgeom1 = lwgeom_from_gserialized(g1);
  lwgeom2 = lwgeom_from_gserialized(g2);

  /* Return FALSE on empty arguments. */
  if ( lwgeom_is_empty(lwgeom1) || lwgeom_is_empty(lwgeom2) ) {
    DBUG_PRINT("postgis", "return FALSE on empty arguments");
    PG_RETURN_BOOL(false);
  }

  DBUG_PRINT("postgis", "calculate the distance between two LWGEOMs, using the coordinates are longitude and latitude");
  distance = lwgeom_distance_spheroid(lwgeom1, lwgeom2, &s, tolerance);
  DBUG_PRINT("postgis", "distance:%g, tolerance:%g", distance, tolerance);

  /* Clean up */
  lwgeom_free(lwgeom1);
  lwgeom_free(lwgeom2);
  PG_FREE_IF_COPY(g1, 0);
  PG_FREE_IF_COPY(g2, 1);

  /* Something went wrong... should already be eloged, return FALSE */
  if ( distance < 0.0 ) {
    elog(ERROR, "lwgeom_distance_spheroid returned negative!");
    DBUG_PRINT("postgis", "lwgeom_distance_spheroid returned negative!");
    DBUG_PRINT("postgis", "return false");
    PG_RETURN_BOOL(false);
  }

  if (distance <= tolerance) {
    DBUG_PRINT("postgis", "return true");
  } else {
    DBUG_PRINT("postgis", "return false");
  }

  PG_RETURN_BOOL(distance <= tolerance);
}


/*
** geography_expand(GSERIALIZED *g) returns *GSERIALIZED
**
** warning, this tricky little function does not expand the
** geometry at all, just re-writes bounding box value to be
** a bit bigger. only useful when passing the result along to
** an index operator (&&)
*/
PG_FUNCTION_INFO_V1(geography_expand);
Datum geography_expand(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  GSERIALIZED *g = NULL;
  GSERIALIZED *g_out = NULL;
  double unit_distance, distance;

  /* Get a wholly-owned pointer to the geography */
  DBUG_PRINT("postgis", "get a wholly-owned pointer to the geography");
  g = PG_GETARG_GSERIALIZED_P_COPY(0);

  /* Read our distance value and normalize to unit-sphere. */
  distance = PG_GETARG_FLOAT8(1);
  DBUG_PRINT("postgis", "read our distance value and normalize to unit-sphere:%g", distance);
  /* Magic 1% expansion is to bridge difference between potential */
  /* spheroidal input distance and fact that expanded box filter is */
  /* calculated on sphere */
  unit_distance = 1.01 * distance / WGS84_RADIUS;
  DBUG_PRINT("postgis", "unit distance:%g", unit_distance);

  /* Try the expansion */
  DBUG_PRINT("postgis", "try to expansion");
  g_out = gserialized_expand(g, unit_distance);

  /* If the expansion fails, the return our input */
  if ( g_out == NULL ) {
    DBUG_PRINT("postgis", "if the expansion fails, the return our input");
    PG_RETURN_POINTER(g);
  }

  if ( g_out != g ) {
    pfree(g);
  }

  PG_RETURN_POINTER(g_out);
}

/*
** geography_area(GSERIALIZED *g)
** returns double area in meters square
*/
PG_FUNCTION_INFO_V1(geography_area);
Datum geography_area(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom = NULL;
  GSERIALIZED *g = NULL;
  GBOX gbox;
  double area;
  bool use_spheroid = LW_TRUE;
  SPHEROID s;

  DBUG_PRINT("postgis", "return double area in meters square");
  /* Get our geometry object loaded into memory. */
  g = PG_GETARG_GSERIALIZED_P(0);

  /* Read our calculation type */
  use_spheroid = PG_GETARG_BOOL(1);
  {
    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }
  }


  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g), &s);

  lwgeom = lwgeom_from_gserialized(g);

  /* EMPTY things have no area */
  if ( lwgeom_is_empty(lwgeom) ) {
    DBUG_PRINT("postgis", "EMPTY things have no area");
    lwgeom_free(lwgeom);
    PG_RETURN_FLOAT8(0.0);
  }

  if ( lwgeom->bbox )
    gbox = *(lwgeom->bbox);
  else
    lwgeom_calculate_gbox_geodetic(lwgeom, &gbox);

#ifndef PROJ_GEODESIC

  /* Test for cases that are currently not handled by spheroid code */
  if ( use_spheroid ) {
    /* We can't circle the poles right now */
    if ( FP_GTEQ(gbox.zmax, 1.0) || FP_LTEQ(gbox.zmin, -1.0) )
      use_spheroid = LW_FALSE;

    /* We can't cross the equator right now */
    if ( gbox.zmax > 0.0 && gbox.zmin < 0.0 )
      use_spheroid = LW_FALSE;
  }

#endif /* ifndef PROJ_GEODESIC */

  /* User requests spherical calculation, turn our spheroid into a sphere */
  if ( ! use_spheroid ) {
    DBUG_PRINT("postgis", "use requests spherical calculation, turn our spheroid into a sphere");
    s.a = s.b = s.radius;
  }

  /* Calculate the area */
  DBUG_PRINT("postgis", "calculate the area");
  area = lwgeom_area_spheroid(lwgeom, &s);

  /* Clean up */
  lwgeom_free(lwgeom);
  PG_FREE_IF_COPY(g, 0);

  /* Something went wrong... */
  if ( area < 0.0 ) {
    elog(ERROR, "lwgeom_area_spher(oid) returned area < 0.0");
    PG_RETURN_NULL();
  }

  DBUG_PRINT("postgis", "return area:%g", area);
  PG_RETURN_FLOAT8(area);
}

/*
** geography_perimeter(GSERIALIZED *g)
** returns double perimeter in meters for area features
*/
PG_FUNCTION_INFO_V1(geography_perimeter);
Datum geography_perimeter(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom = NULL;
  GSERIALIZED *g = NULL;
  double length;
  bool use_spheroid = LW_TRUE;
  SPHEROID s;
  int type;

  DBUG_PRINT("postgis", "return double perimeter in meters for area features");
  /* Get our geometry object loaded into memory. */
  g = PG_GETARG_GSERIALIZED_P(0);

  /* Only return for area features. */
  type = gserialized_get_type(g);

  if ( ! (type == POLYGONTYPE || type == MULTIPOLYGONTYPE || type == COLLECTIONTYPE) ) {
    DBUG_PRINT("postgis", "return 0.0");
    PG_RETURN_FLOAT8(0.0);
  }

  lwgeom = lwgeom_from_gserialized(g);

  /* EMPTY things have no perimeter */
  if ( lwgeom_is_empty(lwgeom) ) {
    lwgeom_free(lwgeom);
    DBUG_PRINT("postgis", "return 0.0");
    PG_RETURN_FLOAT8(0.0);
  }

  /* Read our calculation type */
  use_spheroid = PG_GETARG_BOOL(1);
  {
    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }
  }

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g), &s);

  /* User requests spherical calculation, turn our spheroid into a sphere */
  if ( ! use_spheroid ) {
    s.a = s.b = s.radius;
    DBUG_PRINT("postgis", "user requests spherical calculation, turn our spheroid into a sphere");
  }

  /* Calculate the length */
  DBUG_PRINT("postgis", "calculate the length");
  length = lwgeom_length_spheroid(lwgeom, &s);

  /* Something went wrong... */
  if ( length < 0.0 ) {
    elog(ERROR, "lwgeom_length_spheroid returned length < 0.0");
    PG_RETURN_NULL();
  }

  /* Clean up, but not all the way to the point arrays */
  lwgeom_free(lwgeom);

  PG_FREE_IF_COPY(g, 0);
  DBUG_PRINT("postgis", "return length:%g", length);
  PG_RETURN_FLOAT8(length);
}

/*
** geography_length(GSERIALIZED *g)
** returns double length in meters
*/
PG_FUNCTION_INFO_V1(geography_length);
Datum geography_length(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom = NULL;
  GSERIALIZED *g = NULL;
  double length;
  bool use_spheroid = LW_TRUE;
  SPHEROID s;

  DBUG_PRINT("postgis", "return double length in meters");
  /* Get our geometry object loaded into memory. */
  g = PG_GETARG_GSERIALIZED_P(0);
  lwgeom = lwgeom_from_gserialized(g);

  /* EMPTY things have no length */
  if ( lwgeom_is_empty(lwgeom) || lwgeom->type == POLYGONTYPE || lwgeom->type == MULTIPOLYGONTYPE ) {
    DBUG_PRINT("postgis", "EMPTY things have no length");
    lwgeom_free(lwgeom);
    PG_RETURN_FLOAT8(0.0);
  }

  /* Read our calculation type */
  use_spheroid = PG_GETARG_BOOL(1);
  {
    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }
  }

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g), &s);

  /* User requests spherical calculation, turn our spheroid into a sphere */
  if ( ! use_spheroid ) {
    s.a = s.b = s.radius;
    DBUG_PRINT("postgis", "use requests spherical calculation, turn our spheroid into a sphere");
  }

  /* Calculate the length */
  length = lwgeom_length_spheroid(lwgeom, &s);
  DBUG_PRINT("postgis", "calculate the length:%g", length);

  /* Something went wrong... */
  if ( length < 0.0 ) {
    elog(ERROR, "lwgeom_length_spheroid returned length < 0.0");
    PG_RETURN_NULL();
  }

  /* Clean up */
  lwgeom_free(lwgeom);

  PG_FREE_IF_COPY(g, 0);
  DBUG_PRINT("postgis", "return length:%g", length);
  PG_RETURN_FLOAT8(length);
}

/*
** geography_point_outside(GSERIALIZED *g)
** returns point outside the object
*/
PG_FUNCTION_INFO_V1(geography_point_outside);
Datum geography_point_outside(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  GBOX gbox;
  LWGEOM *lwpoint = NULL;
  POINT2D pt;

  DBUG_PRINT("postgis", "return point outside the object");

  /* We need the bounding box to get an outside point for area algorithm */
  if (gserialized_datum_get_gbox_p(PG_GETARG_DATUM(0), &gbox) == LW_FAILURE) {
    POSTGIS_DEBUG(4, "gserialized_datum_get_gbox_p returned LW_FAILURE");
    elog(ERROR, "Error in gserialized_datum_get_gbox_p calculation.");
    PG_RETURN_NULL();
  }

  POSTGIS_DEBUGF(4, "got gbox %s", gbox_to_string(&gbox));
  DBUG_PRINT("postgis", "got gbox %s", gbox_to_string(&gbox));

  /* Get an exterior point, based on this gbox */
  gbox_pt_outside(&gbox, &pt);

  lwpoint = (LWGEOM*) lwpoint_make2d(4326, pt.x, pt.y);

  PG_RETURN_POINTER(geography_serialize(lwpoint));
}

/*
** geography_covers(GSERIALIZED *g, GSERIALIZED *g) returns boolean
** Only works for (multi)points and (multi)polygons currently.
** Attempts a simple point-in-polygon test on the polygon and point.
** Current algorithm does not distinguish between points on edge
** and points within.
*/
PG_FUNCTION_INFO_V1(geography_covers);
Datum geography_covers(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom1 = NULL;
  LWGEOM *lwgeom2 = NULL;
  GSERIALIZED *g1 = NULL;
  GSERIALIZED *g2 = NULL;
  int result = LW_FALSE;

  /* Get our geometry objects loaded into memory. */
  DBUG_PRINT("postgis", "get our geometry objects loaded into memory");
  g1 = PG_GETARG_GSERIALIZED_P(0);
  g2 = PG_GETARG_GSERIALIZED_P(1);
  gserialized_error_if_srid_mismatch(g1, g2, __func__);

  /* Construct our working geometries */
  DBUG_PRINT("postgis", "construct our working geometries");
  lwgeom1 = lwgeom_from_gserialized(g1);
  lwgeom2 = lwgeom_from_gserialized(g2);

  /* EMPTY never intersects with another geometry */
  if ( lwgeom_is_empty(lwgeom1) || lwgeom_is_empty(lwgeom2) ) {
    DBUG_PRINT("postgis", "EMPTY never intersects with another geometry");
    lwgeom_free(lwgeom1);
    lwgeom_free(lwgeom2);
    PG_FREE_IF_COPY(g1, 0);
    PG_FREE_IF_COPY(g2, 1);
    PG_RETURN_BOOL(false);
  }

  /* Calculate answer */
  result = lwgeom_covers_lwgeom_sphere(lwgeom1, lwgeom2);
  DBUG_PRINT("postgis", "calculate answer:%d", result);

  /* Clean up */
  lwgeom_free(lwgeom1);
  lwgeom_free(lwgeom2);
  PG_FREE_IF_COPY(g1, 0);
  PG_FREE_IF_COPY(g2, 1);

  PG_RETURN_BOOL(result);
}

PG_FUNCTION_INFO_V1(geography_coveredby);
Datum geography_coveredby(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom1 = NULL;
  LWGEOM *lwgeom2 = NULL;
  GSERIALIZED *g1 = NULL;
  GSERIALIZED *g2 = NULL;
  int result = LW_FALSE;

  /* Get our geometry objects loaded into memory. */
  /* Pick them up in reverse order to covers */
  DBUG_PRINT("postgis", "get our geometry objects loaded into memory");
  g1 = PG_GETARG_GSERIALIZED_P(1);
  g2 = PG_GETARG_GSERIALIZED_P(0);
  gserialized_error_if_srid_mismatch(g1, g2, __func__);

  /* Construct our working geometries */
  DBUG_PRINT("postgis", "construct our working geometries");
  lwgeom1 = lwgeom_from_gserialized(g1);
  lwgeom2 = lwgeom_from_gserialized(g2);

  /* EMPTY never intersects with another geometry */
  if ( lwgeom_is_empty(lwgeom1) || lwgeom_is_empty(lwgeom2) ) {
    DBUG_PRINT("postgis", "EMPTY never intersects with another geometry");
    lwgeom_free(lwgeom1);
    lwgeom_free(lwgeom2);
    PG_FREE_IF_COPY(g1, 1);
    PG_FREE_IF_COPY(g2, 0);
    DBUG_PRINT("postgis", "return false");
    PG_RETURN_BOOL(false);
  }

  /* Calculate answer */
  result = lwgeom_covers_lwgeom_sphere(lwgeom1, lwgeom2);
  DBUG_PRINT("postgis", "calculate answer:%d", result);

  /* Clean up */
  lwgeom_free(lwgeom1);
  lwgeom_free(lwgeom2);
  PG_FREE_IF_COPY(g1, 1);
  PG_FREE_IF_COPY(g2, 0);

  if (result) {
    DBUG_PRINT("postgis", "return true");
  } else {
    DBUG_PRINT("postgis", "return false");
  }

  PG_RETURN_BOOL(result);
}

/*
** geography_bestsrid(GSERIALIZED *g, GSERIALIZED *g) returns int
** Utility function. Returns negative SRID numbers that match to the
** numbers handled in code by the transform(lwgeom, srid) function.
** UTM, polar stereographic and mercator as fallback. To be used
** in wrapping existing geometry functions in SQL to provide access
** to them in the geography module.
*/
PG_FUNCTION_INFO_V1(geography_bestsrid);
Datum geography_bestsrid(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  GBOX gbox, gbox1, gbox2;
  GSERIALIZED *g1 = NULL;
  GSERIALIZED *g2 = NULL;
  int empty1 = LW_FALSE;
  int empty2 = LW_FALSE;
  double xwidth, ywidth;
  POINT2D center;
  LWGEOM *lwgeom;

  /* Get our geometry objects loaded into memory. */
  DBUG_PRINT("postgis", "get our geometry objects loaded into memory");
  g1 = PG_GETARG_GSERIALIZED_P(0);
  /* Synchronize our box types */
  gbox1.flags = gserialized_get_lwflags(g1);
  /* Calculate if the geometry is empty. */
  empty1 = gserialized_is_empty(g1);

  /* Convert g1 to LWGEOM type */
  DBUG_PRINT("postgis", "convert g1 to LWGEOM type");
  lwgeom = lwgeom_from_gserialized(g1);

  /* Calculate a geocentric bounds for the objects */
  if ( ! empty1 && gserialized_get_gbox_p(g1, &gbox1) == LW_FAILURE )
    elog(ERROR, "Error in geography_bestsrid calling gserialized_get_gbox_p(g1, &gbox1)");

  POSTGIS_DEBUGF(4, "calculated gbox = %s", gbox_to_string(&gbox1));
  DBUG_PRINT("postgis", "calculated gbox = %s", gbox_to_string(&gbox1));

  if ( !lwgeom_isfinite(lwgeom) ) {
    elog(ERROR, "Error in geography_bestsrid calling with infinite coordinate geographies");
  }

  lwgeom_free(lwgeom);

  /* If we have a unique second argument, fill in all the necessary variables. */
  if (PG_NARGS() > 1) {
    DBUG_PRINT("postgis", "if we have a unique second argument, fill in all the necessary variables");
    g2 = PG_GETARG_GSERIALIZED_P(1);
    gbox2.flags = gserialized_get_lwflags(g2);
    empty2 = gserialized_is_empty(g2);

    if ( ! empty2 && gserialized_get_gbox_p(g2, &gbox2) == LW_FAILURE )
      elog(ERROR, "Error in geography_bestsrid calling gserialized_get_gbox_p(g2, &gbox2)");

    /* Convert g2 to LWGEOM type */
    DBUG_PRINT("postgis", "convert g2 to LWGEOM type");
    lwgeom = lwgeom_from_gserialized(g2);

    if ( !lwgeom_isfinite(lwgeom) ) {
      elog(ERROR, "Error in geography_bestsrid calling with second arg infinite coordinate geographies");
    }

    lwgeom_free(lwgeom);
  }
  /*
  ** If no unique second argument, copying the box for the first
  ** argument will give us the right answer for all subsequent tests.
  */
  else {
    gbox = gbox2 = gbox1;
  }

  /* Both empty? We don't have an answer. */
  if ( empty1 && empty2 )
    PG_RETURN_NULL();

  /* One empty? We can use the other argument values as infill. Otherwise merge the boxen */
  if ( empty1 )
    gbox = gbox2;
  else if ( empty2 )
    gbox = gbox1;
  else
    gbox_union(&gbox1, &gbox2, &gbox);

  gbox_centroid(&gbox, &center);

  /* Width and height in degrees */
  xwidth = 180.0 * gbox_angular_width(&gbox)  / M_PI;
  ywidth = 180.0 * gbox_angular_height(&gbox) / M_PI;

  DBUG_PRINT("postgis", "xwidth %g, ywidth %g and center POINT(%g %g)", xwidth, ywidth, center.x, center.y);
  POSTGIS_DEBUGF(2, "xwidth %g", xwidth);
  DBUG_PRINT("postgis", "xwidth %g", xwidth);
  POSTGIS_DEBUGF(2, "ywidth %g", ywidth);
  DBUG_PRINT("postgis", "ywidth %g", ywidth);
  POSTGIS_DEBUGF(2, "center POINT(%g %g)", center.x, center.y);
  DBUG_PRINT("postgis", "center POINT(%g %g)", center.x, center.y);

  /* Are these data arctic? Lambert Azimuthal Equal Area North. */
  if ( center.y > 70.0 && ywidth < 45.0 ) {
    DBUG_PRINT("postgis", "return result:%d", SRID_NORTH_LAMBERT);
    PG_RETURN_INT32(SRID_NORTH_LAMBERT);
  }

  /* Are these data antarctic? Lambert Azimuthal Equal Area South. */
  if ( center.y < -70.0 && ywidth < 45.0 ) {
    DBUG_PRINT("postgis", "return result:%d", SRID_SOUTH_LAMBERT);
    PG_RETURN_INT32(SRID_SOUTH_LAMBERT);
  }

  /*
  ** Can we fit these data into one UTM zone?
  ** We will assume we can push things as
  ** far as a half zone past a zone boundary.
  ** Note we have no handling for the date line in here.
  */
  if ( xwidth < 6.0 ) {
    int zone = floor((center.x + 180.0) / 6.0);

    if ( zone > 59 ) zone = 59;

    /* Are these data below the equator? UTM South. */
    if ( center.y < 0.0 ) {
      DBUG_PRINT("postgis", "return result:%d", SRID_SOUTH_UTM_START + zone);
      PG_RETURN_INT32( SRID_SOUTH_UTM_START + zone );
    }
    /* Are these data above the equator? UTM North. */
    else {
      DBUG_PRINT("postgis", "return result:%d", SRID_NORTH_UTM_START + zone);
      PG_RETURN_INT32( SRID_NORTH_UTM_START + zone );
    }
  }

  /*
  ** Can we fit into a custom LAEA area? (30 degrees high, variable width)
  ** We will allow overlap into adjoining areas, but use a slightly narrower test (25) to try
  ** and minimize the worst case.
  ** Again, we are hoping the dateline doesn't trip us up much
  */
  if ( ywidth < 25.0 ) {
    int xzone = -1;
    int yzone = 3 + floor(center.y / 30.0); /* (range of 0-5) */

    /* Equatorial band, 12 zones, 30 degrees wide */
    if ( (yzone == 2 || yzone == 3) && xwidth < 30.0 ) {
      xzone = 6 + floor(center.x / 30.0);
    }
    /* Temperate band, 8 zones, 45 degrees wide */
    else if ( (yzone == 1 || yzone == 4) && xwidth < 45.0 ) {
      xzone = 4 + floor(center.x / 45.0);
    }
    /* Arctic band, 4 zones, 90 degrees wide */
    else if ( (yzone == 0 || yzone == 5) && xwidth < 90.0 ) {
      xzone = 2 + floor(center.x / 90.0);
    }

    /* Did we fit into an appropriate xzone? */
    if ( xzone != -1 ) {
      DBUG_PRINT("postgis", "return result:%d", SRID_LAEA_START + 20 * yzone + xzone);
      PG_RETURN_INT32(SRID_LAEA_START + 20 * yzone + xzone);
    }
  }

  /*
  ** Running out of options... fall-back to Mercator
  ** and hope for the best.
  */
  DBUG_PRINT("postgis", "return result:%d", SRID_WORLD_MERCATOR);
  PG_RETURN_INT32(SRID_WORLD_MERCATOR);

}

/*
** geography_project(GSERIALIZED *g, distance, azimuth)
** returns point of projection given start point,
** azimuth in radians (bearing) and distance in meters
*/
PG_FUNCTION_INFO_V1(geography_project);
Datum geography_project(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom = NULL;
  LWPOINT *lwp_projected;
  GSERIALIZED *g = NULL;
  GSERIALIZED *g_out = NULL;
  double azimuth = 0.0;
  double distance;
  SPHEROID s;
  uint32_t type;

  DBUG_PRINT("postgis", "return point of projection given start point, azimuth in radians (bearing) and distance in meters");

  /* Return NULL on NULL distance or geography */
  if ( PG_NARGS() < 2 || PG_ARGISNULL(0) || PG_ARGISNULL(1) ) {
    DBUG_PRINT("postgis", "return NULL on NULL distance or geography");
    PG_RETURN_NULL();
  }

  /* Get our geometry object loaded into memory. */
  g = PG_GETARG_GSERIALIZED_P(0);

  /* Only return for points. */
  type = gserialized_get_type(g);

  if ( type != POINTTYPE ) {
    elog(ERROR, "ST_Project(geography) is only valid for point inputs");
    PG_RETURN_NULL();
  }

  distance = PG_GETARG_FLOAT8(1); /* Distance in Meters */
  lwgeom = lwgeom_from_gserialized(g);

  /* EMPTY things cannot be projected from */
  if ( lwgeom_is_empty(lwgeom) ) {
    lwgeom_free(lwgeom);
    elog(ERROR, "ST_Project(geography) cannot project from an empty start point");
    PG_RETURN_NULL();
  }

  if ( PG_NARGS() > 2 && ! PG_ARGISNULL(2) )
    azimuth = PG_GETARG_FLOAT8(2); /* Azimuth in Radians */

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g), &s);

  /* Handle the zero distance case */
  if( FP_EQUALS(distance, 0.0) ) {
    DBUG_PRINT("postgis", "handle the zero distance case");
    PG_RETURN_POINTER(g);
  }

  /* Calculate the length */
  DBUG_PRINT("postgis", "calculate the length");
  lwp_projected = lwgeom_project_spheroid(lwgeom_as_lwpoint(lwgeom), &s, distance, azimuth);

  /* Something went wrong... */
  if ( lwp_projected == NULL ) {
    elog(ERROR, "lwgeom_project_spheroid returned null");
    PG_RETURN_NULL();
  }

  /* Clean up, but not all the way to the point arrays */
  lwgeom_free(lwgeom);
  g_out = geography_serialize(lwpoint_as_lwgeom(lwp_projected));
  lwpoint_free(lwp_projected);

  PG_FREE_IF_COPY(g, 0);
  PG_RETURN_POINTER(g_out);
}

/*
** geography_project_geography(geog1, geog2, distance, azimuth)
** returns point of projection given from/pt points,
** azimuth in radians (bearing) and distance in meters
*/
PG_FUNCTION_INFO_V1(geography_project_geography);
Datum geography_project_geography(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom1, *lwgeom2;
  LWPOINT *lwp1, *lwp2, *lwp3;
  GSERIALIZED *g1, *g2, *g3;
  double distance;
  SPHEROID s;

  DBUG_PRINT("postgis", "return point of projection given from/pt points, azimuth in radians (bearing) and distance in meters");
  /* Get our geometry object loaded into memory. */
  g1 = PG_GETARG_GSERIALIZED_P(0);
  g2 = PG_GETARG_GSERIALIZED_P(1);

  if ( gserialized_get_type(g1) != POINTTYPE ||
       gserialized_get_type(g2) != POINTTYPE ) {
    elog(ERROR, "ST_Project(geography) is only valid for point inputs");
    PG_RETURN_NULL();
  }

  distance = PG_GETARG_FLOAT8(2); /* Distance in meters */

  /* Handle the zero distance case */
  if ( FP_EQUALS(distance, 0.0) ) {
    PG_RETURN_POINTER(g2);
  }

  lwgeom1 = lwgeom_from_gserialized(g1);
  lwgeom2 = lwgeom_from_gserialized(g2);

  /* EMPTY things cannot be projected from */
  if ( lwgeom_is_empty(lwgeom1) || lwgeom_is_empty(lwgeom2) ) {
    lwgeom_free(lwgeom1);
    lwgeom_free(lwgeom2);
    elog(ERROR, "ST_Project(geography) cannot project from an empty point");
    PG_RETURN_NULL();
  }

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(lwgeom_get_srid(lwgeom1), &s);

  /* Calculate the length */
  lwp1 = lwgeom_as_lwpoint(lwgeom1);
  lwp2 = lwgeom_as_lwpoint(lwgeom2);
  DBUG_PRINT("postgis", "calculate the length");
  lwp3 = lwgeom_project_spheroid_lwpoint(lwp1, lwp2, &s, distance);

  /* Something went wrong... */
  if ( lwp3 == NULL ) {
    elog(ERROR, "lwgeom_project_spheroid_lwpoint returned null");
    PG_RETURN_NULL();
  }

  /* Clean up, but not all the way to the point arrays */
  lwgeom_free(lwgeom1);
  lwgeom_free(lwgeom2);
  g3 = geography_serialize(lwpoint_as_lwgeom(lwp3));
  lwpoint_free(lwp3);

  PG_FREE_IF_COPY(g1, 0);
  PG_FREE_IF_COPY(g2, 1);
  PG_RETURN_POINTER(g3);
}


/*
** geography_azimuth(GSERIALIZED *g1, GSERIALIZED *g2)
** returns direction between points (north = 0)
** azimuth (bearing) and distance
*/
PG_FUNCTION_INFO_V1(geography_azimuth);
Datum geography_azimuth(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  GSERIALIZED *g1 = PG_GETARG_GSERIALIZED_P(0);
  GSERIALIZED *g2 = PG_GETARG_GSERIALIZED_P(1);
  LWGEOM *lwgeom1 = NULL;
  LWGEOM *lwgeom2 = NULL;
  double azimuth;
  SPHEROID s;
  uint32_t type1, type2;

  DBUG_PRINT("postgis", "return direction between points (north = 0) azimuth (bearing) and distance");
  /* Only return for points. */
  type1 = gserialized_get_type(g1);
  type2 = gserialized_get_type(g2);

  if ( type1 != POINTTYPE || type2 != POINTTYPE ) {
    elog(ERROR, "ST_Azimuth(geography, geography) is only valid for point inputs");
    PG_RETURN_NULL();
  }

  lwgeom1 = lwgeom_from_gserialized(g1);
  lwgeom2 = lwgeom_from_gserialized(g2);

  /* EMPTY things cannot be used */
  if ( lwgeom_is_empty(lwgeom1) || lwgeom_is_empty(lwgeom2) ) {
    lwgeom_free(lwgeom1);
    lwgeom_free(lwgeom2);
    elog(ERROR, "ST_Azimuth(geography, geography) cannot work with empty points");
    PG_RETURN_NULL();
  }

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g1), &s);

  /* Calculate the direction */
  DBUG_PRINT("postgis", "calculate the direction");
  azimuth = lwgeom_azumith_spheroid(lwgeom_as_lwpoint(lwgeom1), lwgeom_as_lwpoint(lwgeom2), &s);

  /* Clean up */
  lwgeom_free(lwgeom1);
  lwgeom_free(lwgeom2);

  PG_FREE_IF_COPY(g1, 0);
  PG_FREE_IF_COPY(g2, 1);

  /* Return NULL for unknown (same point) azimuth */
  if( !isfinite(azimuth) ) {
    PG_RETURN_NULL();
  }

  DBUG_PRINT("postgis", "return distance:%g", azimuth);
  PG_RETURN_FLOAT8(azimuth);
}



/**
 * ST_Segmentize(geography, double max_seg_length)
 * Returns densified geometry with no segment longer than maximum.
 */
PG_FUNCTION_INFO_V1(geography_segmentize);
Datum geography_segmentize(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  LWGEOM *lwgeom1 = NULL;
  LWGEOM *lwgeom2 = NULL;
  GSERIALIZED *g1 = PG_GETARG_GSERIALIZED_P(0);
  GSERIALIZED *g2 = NULL;
  double max_seg_length = PG_GETARG_FLOAT8(1) / WGS84_RADIUS;
  uint32_t type1 = gserialized_get_type(g1);

  DBUG_PRINT("postgis", "return densified geometry with no segment longer than maximum");

  /* We can't densify points or points, reflect them back */
  if ( type1 == POINTTYPE || type1 == MULTIPOINTTYPE || gserialized_is_empty(g1) ) {
    DBUG_PRINT("postgis", "we can't densify points or points, reflect them back");
    PG_RETURN_POINTER(g1);
  }

  /* Deserialize */
  DBUG_PRINT("postgis", "deserialize");
  lwgeom1 = lwgeom_from_gserialized(g1);

  /* Calculate the densified geometry */
  DBUG_PRINT("postgis", "calculate the densified geometry");
  lwgeom2 = lwgeom_segmentize_sphere(lwgeom1, max_seg_length);

  /*
  ** Set the geodetic flag so subsequent
  ** functions do the right thing.
  */
  lwgeom_set_geodetic(lwgeom2, true);

  /* Recalculate the boxes after re-setting the geodetic bit */
  DBUG_PRINT("postgis", "recalculate the boxes after re-setting the geodetic bit");
  lwgeom_drop_bbox(lwgeom2);

  /* We are trusting geography_serialize will add a box if needed */
  DBUG_PRINT("postgis", "we are trusting geography_serialize will add a box if needed");
  g2 = geography_serialize(lwgeom2);

  /* Clean up */
  lwgeom_free(lwgeom1);
  lwgeom_free(lwgeom2);
  PG_FREE_IF_COPY(g1, 0);

  PG_RETURN_POINTER(g2);
}


/********************************************************************************/

/**
 * ST_LineSubstring(geography line, float start_fraction, float end_fraction)
 * Return the part of a line between two fractional locations.
 */
PG_FUNCTION_INFO_V1(geography_line_substring);
Datum geography_line_substring(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  GSERIALIZED *gs = PG_GETARG_GSERIALIZED_P(0);
  double from_fraction = PG_GETARG_FLOAT8(1);
  double to_fraction = PG_GETARG_FLOAT8(2);
  LWLINE *lwline;
  LWGEOM *lwresult;
  SPHEROID s;
  GSERIALIZED *result;
  bool use_spheroid = true;

  DBUG_PRINT("postgis", "return the part of a line between two fractional locations");

  if ( PG_NARGS() > 3 && ! PG_ARGISNULL(3) ) {
    use_spheroid = PG_GETARG_BOOL(3);

    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }

  }

  /* Return NULL on empty argument. */
  if ( gserialized_is_empty(gs) ) {
    PG_FREE_IF_COPY(gs, 0);
    PG_RETURN_NULL();
  }

  if ( from_fraction < 0 || from_fraction > 1 ) {
    elog(ERROR, "%s: second argument is not within [0,1]", __func__);
    PG_FREE_IF_COPY(gs, 0);
    PG_RETURN_NULL();
  }

  if ( to_fraction < 0 || to_fraction > 1 ) {
    elog(ERROR, "%s: argument arg is not within [0,1]", __func__);
    PG_FREE_IF_COPY(gs, 0);
    PG_RETURN_NULL();
  }

  if ( from_fraction > to_fraction ) {
    elog(ERROR, "%s: second argument must be smaller than third argument", __func__);
    PG_RETURN_NULL();
  }

  lwline = lwgeom_as_lwline(lwgeom_from_gserialized(gs));

  if ( !lwline ) {
    elog(ERROR, "%s: first argument is not a line", __func__);
    PG_FREE_IF_COPY(gs, 0);
    PG_RETURN_NULL();
  }

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(gs), &s);

  /* Set to sphere if requested */
  if ( ! use_spheroid ) {
    DBUG_PRINT("postgis", "set to sphere if requested");
    s.a = s.b = s.radius;
  }

  DBUG_PRINT("postgis", "return the part of a line between two fractional locations");
  lwresult = geography_substring(lwline, &s,
                                 from_fraction, to_fraction, FP_TOLERANCE);

  lwline_free(lwline);
  PG_FREE_IF_COPY(gs, 0);
  lwgeom_set_geodetic(lwresult, true);
  result = geography_serialize(lwresult);
  lwgeom_free(lwresult);

  PG_RETURN_POINTER(result);
}


/**
 * ST_LineInterpolatePoint(geography line, float fraction, boolean use_spheroid)
 * Interpolate a point along a geographic line.
 *
 * ST_LineInterpolatePoints(geography line, float fraction, boolean use_spheroid)
 * In-fill geographic line with multiple points using the fraction as the interval
 * between each point.
 */
PG_FUNCTION_INFO_V1(geography_line_interpolate_point);
Datum geography_line_interpolate_point(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  GSERIALIZED *gs = PG_GETARG_GSERIALIZED_P(0);
  double distance_fraction = PG_GETARG_FLOAT8(1);
  /* Read calculation type */
  bool use_spheroid = PG_GETARG_BOOL(2);
  /* Read repeat mode */
  bool repeat = (PG_NARGS() > 3) && PG_GETARG_BOOL(3);
  LWLINE* lwline;
  LWGEOM* lwresult;
  SPHEROID s;
  GSERIALIZED *result;
  DBUG_PRINT("postgis", "interpolate a point along a geographic line");
  {
    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }
  }

  /* Return NULL on empty argument. */
  if ( gserialized_is_empty(gs) ) {
    PG_FREE_IF_COPY(gs, 0);
    PG_RETURN_NULL();
  }

  if ( distance_fraction < 0 || distance_fraction > 1 ) {
    elog(ERROR, "%s: second arg is not within [0,1]", __func__);
    PG_FREE_IF_COPY(gs, 0);
    PG_RETURN_NULL();
  }

  lwline = lwgeom_as_lwline(lwgeom_from_gserialized(gs));

  if ( !lwline ) {
    elog(ERROR, "%s: first arg is not a line", __func__);
    PG_FREE_IF_COPY(gs, 0);
    PG_RETURN_NULL();
  }

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(gs), &s);

  /* Set to sphere if requested */
  if ( ! use_spheroid ) {
    DBUG_PRINT("postgis", "set to sphere if requested");
    s.a = s.b = s.radius;
  }

  DBUG_PRINT("postgis", "interpolate a point along a geographic line");
  lwresult = geography_interpolate_points(lwline, distance_fraction, &s, repeat);

  lwgeom_free(lwline_as_lwgeom(lwline));
  PG_FREE_IF_COPY(gs, 0);

  lwgeom_set_geodetic(lwresult, true);
  result = geography_serialize(lwresult);
  lwgeom_free(lwresult);

  PG_RETURN_POINTER(result);
}


/**
 * ST_LineLocatePoint(geography line, geography point, bool use_spheroid)
 * Locate a point along a geographic line.
 */
PG_FUNCTION_INFO_V1(geography_line_locate_point);
Datum geography_line_locate_point(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  GSERIALIZED *gs1 = PG_GETARG_GSERIALIZED_P(0);
  GSERIALIZED *gs2 = PG_GETARG_GSERIALIZED_P(1);
  bool use_spheroid = PG_GETARG_BOOL(2);
  double tolerance = FP_TOLERANCE;
  SPHEROID s;
  LWLINE *lwline;
  LWPOINT *lwpoint;
  POINTARRAY *pa;
  POINT4D p, p_proj;
  double ret;

  DBUG_PRINT("postgis", "locate a point along a geographic line");
  {
    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }
  }

  gserialized_error_if_srid_mismatch(gs1, gs2, __func__);

  /* Return NULL on empty argument. */
  if ( gserialized_is_empty(gs1) || gserialized_is_empty(gs2)) {
    PG_FREE_IF_COPY(gs1, 0);
    PG_FREE_IF_COPY(gs2, 1);
    PG_RETURN_NULL();
  }

  if ( gserialized_get_type(gs1) != LINETYPE ) {
    elog(ERROR, "%s: 1st arg is not a line", __func__);
    PG_RETURN_NULL();
  }

  if ( gserialized_get_type(gs2) != POINTTYPE ) {
    elog(ERROR, "%s: 2nd arg is not a point", __func__);
    PG_RETURN_NULL();
  }

  /* Set to sphere if requested */
  if ( ! use_spheroid ) {
    DBUG_PRINT("postgis", "set to sphere if requested");
    s.a = s.b = s.radius;
  } else {
    /* Initialize spheroid */
    DBUG_PRINT("postgis", "initialize spheroid");
    spheroid_init_from_srid(gserialized_get_srid(gs1), &s);
  }

  lwline = lwgeom_as_lwline(lwgeom_from_gserialized(gs1));
  lwpoint = lwgeom_as_lwpoint(lwgeom_from_gserialized(gs2));

  pa = lwline->points;
  lwpoint_getPoint4d_p(lwpoint, &p);

  DBUG_PRINT("postgis", "locate a point along the point array defining a geographic line");
  ret = ptarray_locate_point_spheroid(pa, &p, &s, tolerance, NULL, &p_proj);

  DBUG_PRINT("postgis", "return %g", ret);
  PG_RETURN_FLOAT8(ret);
}


/**
 * ST_ClosestPoint(geography line, geography point)
 * Return the point in first input geography that is closest to the
 * second input geography in 2d
 */
PG_FUNCTION_INFO_V1(geography_closestpoint);
Datum geography_closestpoint(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  GSERIALIZED *g1 = PG_GETARG_GSERIALIZED_P(0);
  GSERIALIZED *g2 = PG_GETARG_GSERIALIZED_P(1);
  LWGEOM *point, *lwg1, *lwg2;
  GSERIALIZED *result;

  DBUG_PRINT("postgis", "return the point in first input geography that is closest to the second input geography in 2d");
  gserialized_error_if_srid_mismatch(g1, g2, __func__);

  lwg1 = lwgeom_from_gserialized(g1);
  lwg2 = lwgeom_from_gserialized(g2);

  /* Return NULL on empty/bad arguments. */
  if ( !lwg1 || !lwg2 || lwgeom_is_empty(lwg1) || lwgeom_is_empty(lwg2) ) {
    DBUG_PRINT("postgis", "return NULL on empty/bad arguments");
    PG_FREE_IF_COPY(g1, 0);
    PG_FREE_IF_COPY(g2, 1);
    PG_RETURN_NULL();
  }

  DBUG_PRINT("postgis", "closest point and closest line functions for geographies");
  point = geography_tree_closestpoint(lwg1, lwg2, FP_TOLERANCE);
  result = geography_serialize(point);
  lwgeom_free(point);
  lwgeom_free(lwg1);
  lwgeom_free(lwg2);

  PG_FREE_IF_COPY(g1, 0);
  PG_FREE_IF_COPY(g2, 1);
  PG_RETURN_POINTER(result);
}

/**
 * ST_ShortestLine(geography, geography)
 * Return the shortest line between the first and second arguments.
 */
PG_FUNCTION_INFO_V1(geography_shortestline);
Datum geography_shortestline(PG_FUNCTION_ARGS)
{
  DBUG_TRACE;
  GSERIALIZED* g1 = PG_GETARG_GSERIALIZED_P(0);
  GSERIALIZED* g2 = PG_GETARG_GSERIALIZED_P(1);
  bool use_spheroid = PG_GETARG_BOOL(2);
  LWGEOM *line, *lwgeom1, *lwgeom2;
  GSERIALIZED* result;
  SPHEROID s;
  {
    if (use_spheroid) {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is true");
    } else {
      DBUG_PRINT("postgis", "read our calculation type and use_spheroid is false");
    }
  }

  gserialized_error_if_srid_mismatch(g1, g2, __func__);

  lwgeom1 = lwgeom_from_gserialized(g1);
  lwgeom2 = lwgeom_from_gserialized(g2);

  /* Return NULL on empty/bad arguments. */
  if ( !lwgeom1 || !lwgeom2 || lwgeom_is_empty(lwgeom1) || lwgeom_is_empty(lwgeom2) ) {
    PG_FREE_IF_COPY(g1, 0);
    PG_FREE_IF_COPY(g2, 1);
    PG_RETURN_NULL();
  }

  /* Initialize spheroid */
  DBUG_PRINT("postgis", "initialize spheroid");
  spheroid_init_from_srid(gserialized_get_srid(g1), &s);

  /* Set to sphere if requested */
  if ( ! use_spheroid ) {
    DBUG_PRINT("postgis", "set to sphere if requested");
    s.a = s.b = s.radius;
  }

  DBUG_PRINT("postgis", "call geography_tree_shortestline");
  line = geography_tree_shortestline(lwgeom1, lwgeom2, FP_TOLERANCE, &s);

  if (lwgeom_is_empty(line))
    PG_RETURN_NULL();

  result = geography_serialize(line);
  lwgeom_free(line);

  PG_FREE_IF_COPY(g1, 0);
  PG_FREE_IF_COPY(g2, 1);
  PG_RETURN_POINTER(result);
}
