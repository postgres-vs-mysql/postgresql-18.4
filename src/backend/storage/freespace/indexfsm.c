/*-------------------------------------------------------------------------
 *
 * indexfsm.c
 *    POSTGRES free space map for quickly finding free pages in relations
 *
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *    src/backend/storage/freespace/indexfsm.c
 *
 *
 * NOTES:
 *
 *  This is similar to the FSM used for heap, in freespace.c, but instead
 *  of tracking the amount of free space on pages, we only track whether
 *  pages are completely free or in-use. We use the same FSM implementation
 *  as for heaps, using 0 to denote used pages, and (BLCKSZ - 1) for unused.
 *
 *-------------------------------------------------------------------------
 */
#include "debug_trace.h"
#include "postgres.h"

#include "storage/freespace.h"
#include "storage/indexfsm.h"

/*
 * Exported routines
 */

/*
 * GetFreeIndexPage - return a free page from the FSM
 *
 * As a side effect, the page is marked as used in the FSM.
 */
BlockNumber
GetFreeIndexPage(Relation rel)
{
  DBUG_TRACE;
  BlockNumber blkno = GetPageWithFreeSpace(rel, BLCKSZ / 2);

  if (blkno != InvalidBlockNumber)
    RecordUsedIndexPage(rel, blkno);

  DBUG_PRINT("info", "return a free page from the FSM:%u", blkno);
  return blkno;
}

/*
 * RecordFreeIndexPage - mark a page as free in the FSM
 */
void
RecordFreeIndexPage(Relation rel, BlockNumber freeBlock)
{
  DBUG_TRACE;
  RecordPageWithFreeSpace(rel, freeBlock, BLCKSZ - 1);
  DBUG_PRINT("info", "mark a page as free in the FSM:%u", freeBlock);
}


/*
 * RecordUsedIndexPage - mark a page as used in the FSM
 */
void
RecordUsedIndexPage(Relation rel, BlockNumber usedBlock)
{
  DBUG_TRACE;
  RecordPageWithFreeSpace(rel, usedBlock, 0);
  DBUG_PRINT("info", "mark a page as used in the FSM:%u", usedBlock);
}

/*
 * IndexFreeSpaceMapVacuum - scan and fix any inconsistencies in the FSM
 */
void
IndexFreeSpaceMapVacuum(Relation rel)
{
  DBUG_TRACE;
  FreeSpaceMapVacuum(rel);
}
