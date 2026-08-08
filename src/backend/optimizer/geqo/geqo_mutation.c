/*------------------------------------------------------------------------
*
* geqo_mutation.c
*
*  TSP mutation routines
*
* src/backend/optimizer/geqo/geqo_mutation.c
*
*-------------------------------------------------------------------------
*/

/* contributed by:
   =*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=
   *  Martin Utesch        * Institute of Automatic Control    *
   =               = University of Mining and Technology =
   *  utesch@aut.tu-freiberg.de  * Freiberg, Germany           *
   =*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=
 */

/* this is adopted from Genitor : */
/*************************************************************/
/*                               */
/*  Copyright (c) 1990                     */
/*  Darrell L. Whitley                     */
/*  Computer Science Department                */
/*  Colorado State University                */
/*                               */
/*  Permission is hereby granted to copy all or any part of  */
/*  this program for free distribution.   The author's name  */
/*  and this copyright notice must be included in any copy.  */
/*                               */
/*************************************************************/

#include "postgres.h"
#include "debug_trace.h"
#include "optimizer/geqo.h"

#if defined(CX)         /* currently used only in CX mode */

#include "optimizer/geqo_mutation.h"
#include "optimizer/geqo_random.h"

static void
trace_tour(Gene *tour, int num_gene, const char *message)
{
  char output[1024];
  char *p;
  int         i;

  p = output;
  {
    /* write gene sequence */
    for (i = 0; i < (num_gene - 1); i++) {
      p += sprintf(p, "%d-", tour[i]);
    }

    p += sprintf(p, "%d ", tour[i]);

    *p = '\0';
    DBUG_PRINT("info", "%s:%s", message, output);
  }
}

void
geqo_mutation(PlannerInfo *root, Gene *tour, int num_gene)
{
  DBUG_TRACE;
  int     swap1;
  int     swap2;
  int     num_swaps = geqo_randint(root, num_gene / 3, 0);
  Gene    temp;


  while (num_swaps > 0) {
    swap1 = geqo_randint(root, num_gene - 1, 0);
    swap2 = geqo_randint(root, num_gene - 1, 0);

    while (swap1 == swap2)
      swap2 = geqo_randint(root, num_gene - 1, 0);

    temp = tour[swap1];
    tour[swap1] = tour[swap2];
    tour[swap2] = temp;


    num_swaps -= 1;
  }

  trace_tour(tour, num_gene, "mutation");
}

#endif              /* defined(CX) */
