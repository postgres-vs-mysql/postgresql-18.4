/*
 * This file and its contents are licensed under the Apache License 2.0.
 * Please see the included NOTICE for copyright information and
 * LICENSE-APACHE for a copy of the license.
 */
#include "debug_trace.h"
#include "dimension_vector.h"

static int
cmp_slices(const void *left, const void *right)
{
  DBUG_TRACE;
  int result;
  const DimensionSlice *left_slice = *((DimensionSlice **) left);
  const DimensionSlice *right_slice = *((DimensionSlice **) right);

  result = ts_dimension_slice_cmp(left_slice, right_slice);

  DBUG_PRINT("timescaledb", "return result:%d", result);
  return result;
}

static int
cmp_coordinate_and_slice(const void *left, const void *right)
{
  DBUG_TRACE;
  int64 coord = *((int64 *) left);
  const DimensionSlice *slice = *((DimensionSlice **) right);
  int result;

  result = ts_dimension_slice_cmp_coordinate(slice, coord);

  DBUG_PRINT("timescaledb", "return result:%d", result);
  return result;
}

static DimensionVec *
dimension_vec_expand(DimensionVec *vec, int32 new_capacity)
{
  DBUG_TRACE;
  if (vec != NULL && vec->capacity >= new_capacity)
    return vec;

  if (NULL == vec)
    vec = palloc(DIMENSION_VEC_SIZE(new_capacity));
  else
    vec = repalloc(vec, DIMENSION_VEC_SIZE(new_capacity));

  vec->capacity = new_capacity;

  return vec;
}

DimensionVec *
ts_dimension_vec_create(int32 initial_num_slices)
{
  DBUG_TRACE;
  DimensionVec *vec = dimension_vec_expand(NULL, initial_num_slices);

  vec->capacity = initial_num_slices;
  vec->num_slices = 0;

  return vec;
}

DimensionVec *
ts_dimension_vec_sort(DimensionVec **vecptr)
{
  DBUG_TRACE;
  DimensionVec *vec = *vecptr;

  if (vec->num_slices > 1) {
    DBUG_PRINT("timescaledb", "qsort vector's slices(num_slices:%d)", vec->num_slices);
    qsort((void *) vec->slices, vec->num_slices, sizeof(DimensionSlice *), cmp_slices);
  }

  return vec;
}

DimensionVec *
ts_dimension_vec_add_slice(DimensionVec **vecptr, DimensionSlice *slice)
{
  DBUG_TRACE;
  DimensionVec *vec = *vecptr;

  /* Ensure consistent dimension */
  Assert(vec->num_slices == 0 || vec->slices[0]->fd.dimension_id == slice->fd.dimension_id);

  if (vec->num_slices + 1 > vec->capacity)
    *vecptr = vec = dimension_vec_expand(vec, vec->capacity + 10);

  vec->slices[vec->num_slices++] = slice;

  return vec;
}

DimensionVec *
ts_dimension_vec_add_unique_slice(DimensionVec **vecptr, DimensionSlice *slice)
{
  DBUG_TRACE;
  DimensionVec *vec = *vecptr;
  int32 existing_slice_index = ts_dimension_vec_find_slice_index(vec, slice->fd.id);

  if (existing_slice_index == -1)
    return ts_dimension_vec_add_slice(vecptr, slice);

  return vec;
}

DimensionVec *
ts_dimension_vec_add_slice_sort(DimensionVec **vecptr, DimensionSlice *slice)
{
  DBUG_TRACE;
  *vecptr = ts_dimension_vec_add_slice(vecptr, slice);
  return ts_dimension_vec_sort(vecptr);
}

void
ts_dimension_vec_remove_slice(DimensionVec **vecptr, int32 index)
{
  DBUG_TRACE;
  DimensionVec *vec = *vecptr;

  ts_dimension_slice_free(vec->slices[index]);
  memmove((void *) &vec->slices[index],
          (void *) &vec->slices[index + 1],
          sizeof(DimensionSlice *) * (vec->num_slices - index - 1));
  vec->num_slices--;
}

#if defined(USE_ASSERT_CHECKING)
static inline bool
dimension_vec_is_sorted(const DimensionVec *vec)
{
  DBUG_TRACE;
  int i;

  if (vec->num_slices < 2)
    return true;

  for (i = 1; i < vec->num_slices; i++)
    if (cmp_slices((void *) &vec->slices[i - 1], (void *) &vec->slices[i]) > 0)
      return false;

  return true;
}
#endif

DimensionSlice *
ts_dimension_vec_find_slice(const DimensionVec *vec, int64 coordinate)
{
  DBUG_TRACE;
  DimensionSlice **res;

  if (vec->num_slices == 0)
    return NULL;

  Assert(dimension_vec_is_sorted(vec));

  res = (DimensionSlice **) bsearch(&coordinate,
                                    (void *) vec->slices,
                                    vec->num_slices,
                                    sizeof(DimensionSlice *),
                                    cmp_coordinate_and_slice);

  if (res == NULL)
    return NULL;

  return *res;
}

int
ts_dimension_vec_find_slice_index(const DimensionVec *vec, int32 dimension_slice_id)
{
  DBUG_TRACE;
  int i;

  for (i = 0; i < vec->num_slices; i++)
    if (dimension_slice_id == vec->slices[i]->fd.id) {
      DBUG_PRINT("timescaledb", "return slice index:%d", i);
      return i;
    }

      
  DBUG_PRINT("timescaledb", "return slice index:-1");
  return -1;
}

const DimensionSlice *
ts_dimension_vec_get(const DimensionVec *vec, int32 index)
{
  DBUG_TRACE;
  if (index >= vec->num_slices)
    return NULL;

  return vec->slices[index];
}

void
ts_dimension_vec_free(DimensionVec *vec)
{
  DBUG_TRACE;
  int i;

  for (i = 0; i < vec->num_slices; i++)
    ts_dimension_slice_free(vec->slices[i]);

  pfree(vec);
}
