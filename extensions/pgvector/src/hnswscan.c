#include "debug_trace.h"
#include "postgres.h"

#include "access/genam.h"
#include "access/relscan.h"
#include "hnsw.h"
#include "lib/pairingheap.h"
#include "miscadmin.h"
#include "nodes/pg_list.h"
#include "pgstat.h"
#include "storage/lmgr.h"
#include "utils/float.h"
#include "utils/memutils.h"
#include "utils/relcache.h"
#include "utils/snapmgr.h"

#if PG_VERSION_NUM >= 160000
#include "varatt.h"
#endif

/*
 * Algorithm 5 from paper
 */
static List *
GetScanItems(IndexScanDesc scan, Datum value)
{
  DBUG_TRACE;
  HnswScanOpaque so = (HnswScanOpaque) scan->opaque;
  Relation  index = scan->indexRelation;
  HnswSupport *support = &so->support;
  List     *ep;
  List     *w;
  int     m;
  HnswElement entryPoint;
  char     *base = NULL;
  HnswQuery  *q = &so->q;

  DBUG_PRINT("pgvector", "algorithm 5 from paper");
  /* Get m and entry point */
  HnswGetMetaPageInfo(index, &m, &entryPoint);

  q->value = value;
  so->m = m;

  DBUG_PRINT("pgvector", "get m:%d and entry point:%d", m, entryPoint->level);

  if (entryPoint == NULL)
    return NIL;

  ep = list_make1(HnswEntryCandidate(base, entryPoint, q, index, support, false));

  for (int lc = entryPoint->level; lc >= 1; lc--) {
    w = HnswSearchLayer(base, q, ep, 1, lc, index, support, m, false, NULL, NULL, NULL, true, NULL);
    ep = w;
  }

  DBUG_PRINT("pgvector", "hnsw_ef_search:%d", hnsw_ef_search);
  return HnswSearchLayer(base, q, ep, hnsw_ef_search, 0, index, support, m, false, NULL,
                         &so->v, hnsw_iterative_scan != HNSW_ITERATIVE_SCAN_OFF ? &so->discarded : NULL, true, &so->tuples);
}

/*
 * Resume scan at ground level with discarded candidates
 */
static List *
ResumeScanItems(IndexScanDesc scan)
{
  DBUG_TRACE;
  HnswScanOpaque so = (HnswScanOpaque) scan->opaque;
  Relation  index = scan->indexRelation;
  List     *ep = NIL;
  char     *base = NULL;
  int     batch_size = hnsw_ef_search;

  if (pairingheap_is_empty(so->discarded))
    return NIL;

  DBUG_PRINT("pgvector", "resume scan at ground level with discarded candidates");
  DBUG_PRINT("pgvector", "get next batch(%d) of candidates", batch_size);

  /* Get next batch of candidates */
  for (int i = 0; i < batch_size; i++) {
    HnswSearchCandidate *sc;

    if (pairingheap_is_empty(so->discarded))
      break;

    sc = HnswGetSearchCandidate(w_node, pairingheap_remove_first(so->discarded));

    ep = lappend(ep, sc);
  }

  return HnswSearchLayer(base, &so->q, ep, batch_size, 0, index, &so->support, so->m, false, NULL, &so->v, &so->discarded, false, &so->tuples);
}

/*
 * Get scan value
 */
static Datum
GetScanValue(IndexScanDesc scan)
{
  DBUG_TRACE;
  HnswScanOpaque so = (HnswScanOpaque) scan->opaque;
  Datum   value;

  if (scan->orderByData->sk_flags & SK_ISNULL)
    value = PointerGetDatum(NULL);
  else {
    value = scan->orderByData->sk_argument;

    /* Value should not be compressed or toasted */
    Assert(!VARATT_IS_COMPRESSED(DatumGetPointer(value)));
    Assert(!VARATT_IS_EXTENDED(DatumGetPointer(value)));

    /* Normalize if needed */
    if (so->support.normprocinfo != NULL)
      value = HnswNormValue(so->typeInfo, so->support.collation, value);
  }

  return value;
}

#if defined(HNSW_MEMORY)
/*
 * Show memory usage
 */
static void
ShowMemoryUsage(HnswScanOpaque so)
{
  elog(INFO, "memory: %zu KB, tuples: " INT64_FORMAT, MemoryContextMemAllocated(so->tmpCtx, false) / 1024, so->tuples);
}
#endif

/*
 * Prepare for an index scan
 */
IndexScanDesc
hnswbeginscan(Relation index, int nkeys, int norderbys)
{
  DBUG_TRACE;
  IndexScanDesc scan;
  HnswScanOpaque so;
  double    maxMemory;

  DBUG_PRINT("pgvector", "prepare for an index scan");
  scan = RelationGetIndexScan(index, nkeys, norderbys);

  so = (HnswScanOpaque) palloc(sizeof(HnswScanOpaqueData));
  so->typeInfo = HnswGetTypeInfo(index);

  /* Set support functions */
  HnswInitSupport(&so->support, index);

  /*
   * Use a lower max allocation size than default to allow scanning more
   * tuples for iterative search before exceeding work_mem
   */
  so->tmpCtx = AllocSetContextCreate(CurrentMemoryContext,
                                     "Hnsw scan temporary context",
                                     0, 8 * 1024, 256 * 1024);

  /* Calculate max memory */
  /* Add 256 extra bytes to fill last block when close */
  maxMemory = (double) work_mem * hnsw_scan_mem_multiplier * 1024.0 + 256;
  DBUG_PRINT("pgvector", "calculate max memory:%g", maxMemory);
  so->maxMemory = Min(maxMemory, (double) SIZE_MAX);

  scan->opaque = so;

  return scan;
}

/*
 * Start or restart an index scan
 */
void
hnswrescan(IndexScanDesc scan, ScanKey keys, int nkeys, ScanKey orderbys, int norderbys)
{
  DBUG_TRACE;
  HnswScanOpaque so = (HnswScanOpaque) scan->opaque;

  so->first = true;
  /* v and discarded are allocated in tmpCtx */
  so->v.tids = NULL;
  so->discarded = NULL;
  so->tuples = 0;
  so->previousDistance = -get_float8_infinity();
  MemoryContextReset(so->tmpCtx);

  if (keys) {
    if (norderbys) {
      DBUG_PRINT("pgvector", "start or restart an index scan(numberOfKeys:%d, numberOfOrderBys:%d)",
                 scan->numberOfKeys, scan->numberOfOrderBys);
    } else {
      DBUG_PRINT("pgvector", "start or restart an index scan(numberOfKeys:%d)", scan->numberOfKeys);
    }
  } else {
    if (norderbys) {
      DBUG_PRINT("pgvector", "start or restart an index scan(numberOfOrderBys:%d)", scan->numberOfOrderBys);
    } else {
      DBUG_PRINT("pgvector", "start or restart an index scan");
    }
  }

  if (keys && scan->numberOfKeys > 0) {
    memmove(scan->keyData, keys, scan->numberOfKeys * sizeof(ScanKeyData));
  }

  if (orderbys && scan->numberOfOrderBys > 0) {
    memmove(scan->orderByData, orderbys, scan->numberOfOrderBys * sizeof(ScanKeyData));
  }
}

/*
 * Fetch the next tuple in the given scan
 */
bool
hnswgettuple(IndexScanDesc scan, ScanDirection dir)
{
  DBUG_TRACE;
  HnswScanOpaque so = (HnswScanOpaque) scan->opaque;
  MemoryContext oldCtx = MemoryContextSwitchTo(so->tmpCtx);

  DBUG_PRINT("pgvector", "fetch the next tuple in the given scan");
  /*
   * Index can be used to scan backward, but Postgres doesn't support
   * backward scan on operators
   */
  Assert(ScanDirectionIsForward(dir));

  if (so->first) {
    Datum   value;

    /* Count index scan for stats */
    pgstat_count_index_scan(scan->indexRelation);
#if PG_VERSION_NUM >= 180000

    if (scan->instrument)
      scan->instrument->nsearches++;

#endif

    /* Safety check */
    if (scan->orderByData == NULL)
      elog(ERROR, "cannot scan hnsw index without order");

    /* Requires MVCC-compliant snapshot as not able to maintain a pin */
    /* https://www.postgresql.org/docs/current/index-locking.html */
    if (!IsMVCCSnapshot(scan->xs_snapshot)) {
      DBUG_INSTANT_PRINT("pgvector", "non-MVCC snapshots are not supported with hnsw");
      elog(ERROR, "non-MVCC snapshots are not supported with hnsw");
    }

    /* Get scan value */
    value = GetScanValue(scan);

    /*
     * Get a shared lock. This allows vacuum to ensure no in-flight scans
     * before marking tuples as deleted.
     */
    LockPage(scan->indexRelation, HNSW_SCAN_LOCK, ShareLock);

    so->w = GetScanItems(scan, value);

    /* Release shared lock */
    UnlockPage(scan->indexRelation, HNSW_SCAN_LOCK, ShareLock);

    so->first = false;

    DBUG_PRINT("pgvector", "memory: %zu KB, tuples: " INT64_FORMAT, MemoryContextMemAllocated(so->tmpCtx, false) / 1024, so->tuples);
#if defined(HNSW_MEMORY)
    ShowMemoryUsage(so);
#endif
  }

  for (;;) {
    char     *base = NULL;
    HnswSearchCandidate *sc;
    HnswElement element;
    ItemPointer heaptid;

    DBUG_PRINT("pgvector", "list_length(so->w):%u", list_length(so->w));

    if (list_length(so->w) == 0) {
      if (hnsw_iterative_scan == HNSW_ITERATIVE_SCAN_OFF)
        break;

      /* Empty index */
      if (so->discarded == NULL) {
        DBUG_PRINT("pgvector", "empty index");
        break;
      }

      /* Reached max number of tuples or memory limit */
      if (so->tuples >= hnsw_max_scan_tuples || MemoryContextMemAllocated(so->tmpCtx, false) > so->maxMemory) {
        if (so->tuples >= hnsw_max_scan_tuples) {
          DBUG_PRINT("pgvector", "reached max number of tuple");
        } else {
          DBUG_PRINT("pgvector", "reached memory limit");
        }

        if (pairingheap_is_empty(so->discarded))
          break;

        /* Return remaining tuples */
        DBUG_PRINT("pgvector", "return remaining tuples");
        so->w = lappend(so->w, HnswGetSearchCandidate(w_node, pairingheap_remove_first(so->discarded)));
      } else {
        /*
         * Locking ensures when neighbors are read, the elements they
         * reference will not be deleted (and replaced) during the
         * iteration.
         *
         * Elements loaded into memory on previous iterations may have
         * been deleted (and replaced), so when reading neighbors, the
         * element version must be checked.
         */
        LockPage(scan->indexRelation, HNSW_SCAN_LOCK, ShareLock);

        so->w = ResumeScanItems(scan);

        UnlockPage(scan->indexRelation, HNSW_SCAN_LOCK, ShareLock);

        DBUG_PRINT("pgvector", "memory: %zu KB, tuples: " INT64_FORMAT, MemoryContextMemAllocated(so->tmpCtx, false) / 1024, so->tuples);
#if defined(HNSW_MEMORY)
        ShowMemoryUsage(so);
#endif
      }

      if (list_length(so->w) == 0)
        break;
    }

    sc = llast(so->w);
    element = HnswPtrAccess(base, sc->element);

    /* Move to next element if no valid heap TIDs */
    if (element->heaptidsLength == 0) {
      DBUG_PRINT("pgvector", "move to next element if no valid heap TIDs");
      so->w = list_delete_last(so->w);

      /* Mark memory as free for next iteration */
      if (hnsw_iterative_scan != HNSW_ITERATIVE_SCAN_OFF) {
        pfree(element);
        pfree(sc);
      }

      continue;
    } else {
      DBUG_PRINT("pgvector", "element->heaptidsLength:%d, level:%d", element->heaptidsLength, element->level);
    }

    heaptid = &element->heaptids[--element->heaptidsLength];

    if (hnsw_iterative_scan == HNSW_ITERATIVE_SCAN_STRICT) {
      DBUG_PRINT("pgvector", "iterative scan strict and distance:%g, previousDistance:%g", sc->distance, so->previousDistance);

      if (sc->distance < so->previousDistance) {
        continue;
      }

      so->previousDistance = sc->distance;
    }

    MemoryContextSwitchTo(oldCtx);

    scan->xs_heaptid = *heaptid;
    scan->xs_recheck = false;
    scan->xs_recheckorderby = false;
    return true;
  }

  MemoryContextSwitchTo(oldCtx);
  return false;
}

/*
 * End a scan and release resources
 */
void
hnswendscan(IndexScanDesc scan)
{
  DBUG_TRACE;
  HnswScanOpaque so = (HnswScanOpaque) scan->opaque;

  MemoryContextDelete(so->tmpCtx);

  pfree(so);
  scan->opaque = NULL;
}
