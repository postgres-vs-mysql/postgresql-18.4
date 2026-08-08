#include "debug_trace.h"
#include "postgres.h"

#include "access/genam.h"
#include "access/generic_xlog.h"
#include "access/itup.h"
#include "commands/vacuum.h"
#include "ivfflat.h"
#include "storage/bufmgr.h"
#include "utils/relcache.h"
#include "miscadmin.h"

#if PG_VERSION_NUM >= 180000
#define vacuum_delay_point() vacuum_delay_point(false)
#endif

/*
 * Bulk delete tuples from the index
 */
IndexBulkDeleteResult *
ivfflatbulkdelete(IndexVacuumInfo *info, IndexBulkDeleteResult *stats,
                  IndexBulkDeleteCallback callback, void *callback_state)
{
  DBUG_TRACE;
  Relation  index = info->index;
  BlockNumber blkno = IVFFLAT_HEAD_BLKNO;
  BufferAccessStrategy bas = GetAccessStrategy(BAS_BULKREAD);
  size_t count = 0;
  bool tmp_trace_disabled = false;

  if (stats == NULL)
    stats = (IndexBulkDeleteResult *) palloc0(sizeof(IndexBulkDeleteResult));

  /* Iterate over list pages */
  DBUG_PRINT("pgvector", "iterate over list pages");
  while (BlockNumberIsValid(blkno)) {
    Buffer    cbuf;
    Page    cpage;
    OffsetNumber coffno;
    OffsetNumber cmaxoffno;
    BlockNumber listPages[MaxOffsetNumber];
    ListInfo  listInfo;
    int tmp_count = 0;


    DBUG_PRINT("pgvector", "read buffer(blkno:%u)", blkno);
    cbuf = ReadBuffer(index, blkno);
    LockBuffer(cbuf, BUFFER_LOCK_SHARE);
    cpage = BufferGetPage(cbuf);

    cmaxoffno = PageGetMaxOffsetNumber(cpage);

    /* Iterate over lists */

    for (coffno = FirstOffsetNumber; coffno <= cmaxoffno; coffno = OffsetNumberNext(coffno)) {
      IvfflatList list = (IvfflatList) PageGetItem(cpage, PageGetItemId(cpage, coffno));

      listPages[coffno - FirstOffsetNumber] = list->startPage;
      tmp_count++;
    }
    DBUG_PRINT("pgvector", "iterate over lists(size:%d and cmaxoffno:%u)", tmp_count, cmaxoffno);

    listInfo.blkno = blkno;
    blkno = IvfflatPageGetOpaque(cpage)->nextblkno;

    UnlockReleaseBuffer(cbuf);

    for (coffno = FirstOffsetNumber; coffno <= cmaxoffno; coffno = OffsetNumberNext(coffno)) {
      BlockNumber searchPage = listPages[coffno - FirstOffsetNumber];
      BlockNumber insertPage = InvalidBlockNumber;

      /* Iterate over entry pages */
      DBUG_PRINT("pgvector", "iterate over entry pages (searchPage:%u)", searchPage);
      while (BlockNumberIsValid(searchPage)) {
        Buffer    buf;
        Page    page;
        GenericXLogState *state;
        OffsetNumber offno;
        OffsetNumber maxoffno;
        OffsetNumber deletable[MaxOffsetNumber];
        int     ndeletable;

        if (count > max_trace_iterations) {
          if (!trace_disabled) {
            if (!tmp_trace_disabled) {
              tmp_trace_disabled = true;
              set_trace_disabled();
            }
          }
        }
        count++;
        vacuum_delay_point();

        DBUG_PRINT("pgvector", "return a buffer containing the requested block of the requested relation");
        buf = ReadBufferExtended(index, MAIN_FORKNUM, searchPage, RBM_NORMAL, bas);

        /*
         * ambulkdelete cannot delete entries from pages that are
         * pinned by other backends
         *
         * https://www.postgresql.org/docs/current/index-locking.html
         */
        LockBufferForCleanup(buf);

        state = GenericXLogStart(index);
        page = GenericXLogRegisterBuffer(state, buf, 0);

        maxoffno = PageGetMaxOffsetNumber(page);
        ndeletable = 0;

        /* Find deleted tuples */
        for (offno = FirstOffsetNumber; offno <= maxoffno; offno = OffsetNumberNext(offno)) {
          IndexTuple  itup = (IndexTuple) PageGetItem(page, PageGetItemId(page, offno));
          ItemPointer htup = &(itup->t_tid);

          if (callback(htup, callback_state)) {
            deletable[ndeletable++] = offno;
            stats->tuples_removed++;
          } else
            stats->num_index_tuples++;
        }

        /* Set to first free page */
        /* Must be set before searchPage is updated */
        if (!BlockNumberIsValid(insertPage) && ndeletable > 0)
          insertPage = searchPage;

        searchPage = IvfflatPageGetOpaque(page)->nextblkno;

        if (ndeletable > 0) {
          /* Delete tuples */
          DBUG_PRINT("pgvector", "delete tuples(%d)", ndeletable);
          PageIndexMultiDelete(page, deletable, ndeletable);
          GenericXLogFinish(state);
        } else
          GenericXLogAbort(state);

        UnlockReleaseBuffer(buf);
      }

      /*
       * Update after all tuples deleted.
       *
       * We don't add or delete items from lists pages, so offset won't
       * change.
       */
      if (BlockNumberIsValid(insertPage)) {
        DBUG_PRINT("pgvector", "update after all tuples deleted (insertPage:%u)", insertPage);
        listInfo.offno = coffno;
        IvfflatUpdateList(index, listInfo, insertPage, InvalidBlockNumber, InvalidBlockNumber, MAIN_FORKNUM);
      }
    }
  }

  if (tmp_trace_disabled) {
    set_trace_enabled();
    tmp_trace_disabled = false;
    DBUG_PRINT("pgvector", "...");
    DBUG_PRINT("pgvector", "similar things have been processed %lu times", count - max_trace_iterations);
    DBUG_PRINT("pgvector", "total processed:%lu", count);
  }
  FreeAccessStrategy(bas);

  return stats;
}

/*
 * Clean up after a VACUUM operation
 */
IndexBulkDeleteResult *
ivfflatvacuumcleanup(IndexVacuumInfo *info, IndexBulkDeleteResult *stats)
{
  DBUG_TRACE;
  Relation  rel = info->index;

  if (info->analyze_only) {
    DBUG_PRINT("pgvector", "analyze_only: true");
    return stats;
  }

  /* stats is NULL if ambulkdelete not called */
  /* OK to return NULL if index not changed */
  if (stats == NULL) {
    DBUG_PRINT("pgvector", "stats is NULL if ambulkdelete not called");
    DBUG_PRINT("pgvector", "OK to return NULL if index not changed");
    return NULL;
  }

  stats->num_pages = RelationGetNumberOfBlocks(rel);
    
  DBUG_PRINT("pgvector", "pages remaining in index:%u", stats->num_pages);

  return stats;
}
