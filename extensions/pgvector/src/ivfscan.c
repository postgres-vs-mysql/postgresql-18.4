#include "debug_trace.h"
#include "postgres.h"

#include <float.h>

#include "access/genam.h"
#include "access/itup.h"
#include "access/relscan.h"
#include "access/tupdesc.h"
#include "catalog/pg_operator_d.h"
#include "catalog/pg_type_d.h"
#include "fmgr.h"
#include "lib/pairingheap.h"
#include "ivfflat.h"
#include "miscadmin.h"
#include "pgstat.h"
#include "storage/bufmgr.h"
#include "utils/memutils.h"
#include "utils/rel.h"
#include "utils/snapmgr.h"
#include "utils/tuplesort.h"

#if PG_VERSION_NUM >= 160000
#include "varatt.h"
#endif

#define GetScanList(ptr) pairingheap_container(IvfflatScanList, ph_node, ptr)
#define GetScanListConst(ptr) pairingheap_const_container(IvfflatScanList, ph_node, ptr)

/*
 * Compare list distances
 */
static int
CompareLists(const pairingheap_node *a, const pairingheap_node *b, void *arg)
{
  DBUG_TRACE;

  if (GetScanListConst(a)->distance > GetScanListConst(b)->distance)
    return 1;

  if (GetScanListConst(a)->distance < GetScanListConst(b)->distance)
    return -1;

  return 0;
}

/*
 * Get lists and sort by distance
 */
static void
GetScanLists(IndexScanDesc scan, Datum value)
{
  DBUG_TRACE;
  IvfflatScanOpaque so = (IvfflatScanOpaque) scan->opaque;
  BlockNumber nextblkno = IVFFLAT_HEAD_BLKNO;
  int     listCount = 0;
  double    maxDistance = DBL_MAX;
  int         total_count = 0;

  DBUG_PRINT("pgvector", "get lists and sort by distance");

  /* Search all list pages */
  while (BlockNumberIsValid(nextblkno)) {
    Buffer    cbuf;
    Page    cpage;
    OffsetNumber maxoffno;

    DBUG_PRINT("pgvector", "search page(blkno:%u)", nextblkno);
    cbuf = ReadBuffer(scan->indexRelation, nextblkno);
    LockBuffer(cbuf, BUFFER_LOCK_SHARE);
    cpage = BufferGetPage(cbuf);

    maxoffno = PageGetMaxOffsetNumber(cpage);

    for (OffsetNumber offno = FirstOffsetNumber; offno <= maxoffno; offno = OffsetNumberNext(offno)) {
      IvfflatList list = (IvfflatList) PageGetItem(cpage, PageGetItemId(cpage, offno));
      double    distance;

      /* Use procinfo from the index instead of scan key for performance */
      distance = DatumGetFloat8(so->distfunc(so->procinfo, so->collation, PointerGetDatum(&list->center), value));

      if (listCount < so->maxProbes) {
        IvfflatScanList *scanlist;

        scanlist = &so->lists[listCount];
        scanlist->startPage = list->startPage;
        scanlist->distance = distance;
        listCount++;

        total_count++;
        /* Add to heap */
        pairingheap_add(so->listQueue, &scanlist->ph_node);

        /* Calculate max distance */
        if (listCount == so->maxProbes) {
          maxDistance = GetScanList(pairingheap_first(so->listQueue))->distance;
          DBUG_PRINT("pgvector", "calculate max distance:%g", maxDistance);
        }
      } else if (distance < maxDistance) {
        IvfflatScanList *scanlist;

        DBUG_PRINT("pgvector", "distance:%g, max distance:%g", distance, maxDistance);
        /* Remove */
        scanlist = GetScanList(pairingheap_remove_first(so->listQueue));

        /* Reuse */
        scanlist->startPage = list->startPage;
        scanlist->distance = distance;
        pairingheap_add(so->listQueue, &scanlist->ph_node);
        total_count++;

        /* Update max distance */
        maxDistance = GetScanList(pairingheap_first(so->listQueue))->distance;
        DBUG_PRINT("pgvector", "update max distance:%g", maxDistance);
      } else {
        DBUG_PRINT("pgvector", "distance:%g, max distance:%g", distance, maxDistance);
      }
    }

    nextblkno = IvfflatPageGetOpaque(cpage)->nextblkno;
    DBUG_PRINT("pgvector", "get next search page(blkno:%u)", nextblkno);

    UnlockReleaseBuffer(cbuf);
  }

  DBUG_PRINT("pgvector", "current list size:%d, total heap insertions:%d", listCount, total_count);

  for (int i = listCount - 1; i >= 0; i--)
    so->listPages[i] = GetScanList(pairingheap_remove_first(so->listQueue))->startPage;

  Assert(pairingheap_is_empty(so->listQueue));
}

/*
 * Get items
 */
static void
GetScanItems(IndexScanDesc scan, Datum value)
{
  DBUG_TRACE;
  IvfflatScanOpaque so = (IvfflatScanOpaque) scan->opaque;
  TupleDesc tupdesc = RelationGetDescr(scan->indexRelation);
  TupleTableSlot *slot = so->vslot;
  int     batchProbes = 0;
  int count = 0;
  int total_count = 0;

  tuplesort_reset(so->sortstate);

  /* Search closest probes lists */
  DBUG_PRINT("pgvector", "search closest probes lists(maxProbes:%d, probes:%d, listIndex:%d)", so->maxProbes, so->probes, so->listIndex);

  while (so->listIndex < so->maxProbes && (++batchProbes) <= so->probes) {
    BlockNumber searchPage = so->listPages[so->listIndex++];

    /* Search all entry pages for list */
    DBUG_PRINT("pgvector", "search page:%u", searchPage);

    while (BlockNumberIsValid(searchPage)) {
      Buffer    buf;
      Page    page;
      OffsetNumber maxoffno;

      buf = ReadBufferExtended(scan->indexRelation, MAIN_FORKNUM, searchPage, RBM_NORMAL, so->bas);
      LockBuffer(buf, BUFFER_LOCK_SHARE);
      page = BufferGetPage(buf);
      maxoffno = PageGetMaxOffsetNumber(page);

      DBUG_PRINT("pgvector", "FirstOffsetNumber:%u, maxoffno:%u", FirstOffsetNumber, maxoffno);
      count = 0;

      for (OffsetNumber offno = FirstOffsetNumber; offno <= maxoffno; offno = OffsetNumberNext(offno)) {
        IndexTuple  itup;
        Datum   datum;
        bool    isnull;
        ItemId    itemid = PageGetItemId(page, offno);

        itup = (IndexTuple) PageGetItem(page, itemid);
        datum = index_getattr(itup, 1, tupdesc, &isnull);

        /*
         * Add virtual tuple
         *
         * Use procinfo from the index instead of scan key for
         * performance
         */
        ExecClearTuple(slot);
        slot->tts_values[0] = so->distfunc(so->procinfo, so->collation, datum, value);
        slot->tts_isnull[0] = false;
        slot->tts_values[1] = PointerGetDatum(&itup->t_tid);
        slot->tts_isnull[1] = false;
        ExecStoreVirtualTuple(slot);

        tuplesort_puttupleslot(so->sortstate, slot);
        count++;
        total_count++;
      }

      searchPage = IvfflatPageGetOpaque(page)->nextblkno;
      DBUG_PRINT("pgvector", "tuples visited:%d and next search page:%u", count, searchPage);

      UnlockReleaseBuffer(buf);
    }
  }

  DBUG_PRINT("pgvector", "total tuples:%d", total_count);
  tuplesort_performsort(so->sortstate);

  DBUG_PRINT("pgvector", "memory: %zu MB", MemoryContextMemAllocated(CurrentMemoryContext, true) / (1024 * 1024));
#if defined(IVFFLAT_MEMORY)
  elog(INFO, "memory: %zu MB", MemoryContextMemAllocated(CurrentMemoryContext, true) / (1024 * 1024));
#endif
}

/*
 * Zero distance
 */
static Datum
ZeroDistance(FmgrInfo *flinfo, Oid collation, Datum arg1, Datum arg2)
{
  DBUG_TRACE;
  return Float8GetDatum(0.0);
}

/*
 * Get scan value
 */
static Datum
GetScanValue(IndexScanDesc scan)
{
  DBUG_TRACE;
  IvfflatScanOpaque so = (IvfflatScanOpaque) scan->opaque;
  Datum   value;

  if (scan->orderByData->sk_flags & SK_ISNULL) {
    value = PointerGetDatum(NULL);
    so->distfunc = ZeroDistance;
  } else {
    value = scan->orderByData->sk_argument;
    so->distfunc = FunctionCall2Coll;

    /* Value should not be compressed or toasted */
    Assert(!VARATT_IS_COMPRESSED(DatumGetPointer(value)));
    Assert(!VARATT_IS_EXTENDED(DatumGetPointer(value)));

    /* Normalize if needed */
    if (so->normprocinfo != NULL) {
      MemoryContext oldCtx = MemoryContextSwitchTo(so->tmpCtx);

      DBUG_PRINT("pgvector", "normalize if needed");
      value = IvfflatNormValue(so->typeInfo, so->collation, value);

      MemoryContextSwitchTo(oldCtx);
    }
  }

  return value;
}

/*
 * Initialize scan sort state
 */
static Tuplesortstate *
InitScanSortState(TupleDesc tupdesc)
{
  DBUG_TRACE;
  AttrNumber  attNums[] = {1};
  Oid     sortOperators[] = {Float8LessOperator};
  Oid     sortCollations[] = {InvalidOid};
  bool    nullsFirstFlags[] = {false};

  DBUG_PRINT("pgvector", "initialize scan sort state");
  return tuplesort_begin_heap(tupdesc, 1, attNums, sortOperators, sortCollations, nullsFirstFlags, work_mem, NULL, false);
}

/*
 * Prepare for an index scan
 */
IndexScanDesc
ivfflatbeginscan(Relation index, int nkeys, int norderbys)
{
  DBUG_TRACE;
  IndexScanDesc scan;
  IvfflatScanOpaque so;
  int     lists;
  int     dimensions;
  int     probes = ivfflat_probes;
  int     maxProbes;
  MemoryContext oldCtx;

  DBUG_PRINT("pgvector", "prepare for an index scan");
  scan = RelationGetIndexScan(index, nkeys, norderbys);

  /* Get lists and dimensions from metapage */
  IvfflatGetMetaPageInfo(index, &lists, &dimensions);

  if (ivfflat_iterative_scan != IVFFLAT_ITERATIVE_SCAN_OFF)
    maxProbes = Max(ivfflat_max_probes, probes);
  else
    maxProbes = probes;

  if (probes > lists)
    probes = lists;

  if (maxProbes > lists)
    maxProbes = lists;

  so = (IvfflatScanOpaque) palloc(sizeof(IvfflatScanOpaqueData));
  so->typeInfo = IvfflatGetTypeInfo(index);
  so->first = true;
  so->probes = probes;
  so->maxProbes = maxProbes;
  so->dimensions = dimensions;

  /* Set support functions */
  so->procinfo = index_getprocinfo(index, 1, IVFFLAT_DISTANCE_PROC);
  so->normprocinfo = IvfflatOptionalProcInfo(index, IVFFLAT_NORM_PROC);
  so->collation = index->rd_indcollation[0];

  so->tmpCtx = AllocSetContextCreate(CurrentMemoryContext,
                                     "Ivfflat scan temporary context",
                                     ALLOCSET_DEFAULT_SIZES);

  oldCtx = MemoryContextSwitchTo(so->tmpCtx);

  /* Create tuple description for sorting */
  so->tupdesc = CreateTemplateTupleDesc(2);
  TupleDescInitEntry(so->tupdesc, (AttrNumber) 1, "distance", FLOAT8OID, -1, 0);
  TupleDescInitEntry(so->tupdesc, (AttrNumber) 2, "heaptid", TIDOID, -1, 0);

  /* Prep sort */
  so->sortstate = InitScanSortState(so->tupdesc);

  /* Need separate slots for puttuple and gettuple */
  so->vslot = MakeSingleTupleTableSlot(so->tupdesc, &TTSOpsVirtual);
  so->mslot = MakeSingleTupleTableSlot(so->tupdesc, &TTSOpsMinimalTuple);

  /*
   * Reuse same set of shared buffers for scan
   *
   * See postgres/src/backend/storage/buffer/README for description
   */
  so->bas = GetAccessStrategy(BAS_BULKREAD);

  so->listQueue = pairingheap_allocate(CompareLists, scan);
  so->listPages = palloc(maxProbes * sizeof(BlockNumber));
  so->listIndex = 0;
  so->lists = palloc(maxProbes * sizeof(IvfflatScanList));

  MemoryContextSwitchTo(oldCtx);

  scan->opaque = so;

  return scan;
}

/*
 * Start or restart an index scan
 */
void
ivfflatrescan(IndexScanDesc scan, ScanKey keys, int nkeys, ScanKey orderbys, int norderbys)
{
  DBUG_TRACE;
  IvfflatScanOpaque so = (IvfflatScanOpaque) scan->opaque;

  DBUG_PRINT("pgvector", "start or restart an index scan");
  so->first = true;
  pairingheap_reset(so->listQueue);
  so->listIndex = 0;

  if (keys && scan->numberOfKeys > 0)
    memmove(scan->keyData, keys, scan->numberOfKeys * sizeof(ScanKeyData));

  if (orderbys && scan->numberOfOrderBys > 0)
    memmove(scan->orderByData, orderbys, scan->numberOfOrderBys * sizeof(ScanKeyData));
}

/*
 * Fetch the next tuple in the given scan
 */
bool
ivfflatgettuple(IndexScanDesc scan, ScanDirection dir)
{
  DBUG_TRACE;
  IvfflatScanOpaque so = (IvfflatScanOpaque) scan->opaque;
  ItemPointer heaptid;
  bool    isnull;

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
    if (scan->orderByData == NULL) {
      DBUG_INSTANT_PRINT("pgvector", "cannot scan ivfflat index without order");
      elog(ERROR, "cannot scan ivfflat index without order");
    }

    /* Requires MVCC-compliant snapshot as not able to pin during sorting */
    /* https://www.postgresql.org/docs/current/index-locking.html */
    if (!IsMVCCSnapshot(scan->xs_snapshot)) {
      DBUG_INSTANT_PRINT("pgvector", "non-MVCC snapshots are not supported with ivfflat");
      elog(ERROR, "non-MVCC snapshots are not supported with ivfflat");
    }

    value = GetScanValue(scan);
    IvfflatBench("GetScanLists", GetScanLists(scan, value));
    IvfflatBench("GetScanItems", GetScanItems(scan, value));
    so->first = false;
    so->value = value;
  }

  while (!tuplesort_gettupleslot(so->sortstate, true, false, so->mslot, NULL)) {
    if (so->listIndex == so->maxProbes)
      return false;

    IvfflatBench("GetScanItems", GetScanItems(scan, so->value));
  }

  heaptid = (ItemPointer) DatumGetPointer(slot_getattr(so->mslot, 2, &isnull));

  scan->xs_heaptid = *heaptid;
  scan->xs_recheck = false;
  scan->xs_recheckorderby = false;
  return true;
}

/*
 * End a scan and release resources
 */
void
ivfflatendscan(IndexScanDesc scan)
{
  DBUG_TRACE;
  IvfflatScanOpaque so = (IvfflatScanOpaque) scan->opaque;

  DBUG_PRINT("pgvector", "end a scan and release resources");
  DBUG_PRINT("pgvector", "free any temporary files");
  /* Free any temporary files */
  tuplesort_end(so->sortstate);

  MemoryContextDelete(so->tmpCtx);

  pfree(so);
  scan->opaque = NULL;
}
