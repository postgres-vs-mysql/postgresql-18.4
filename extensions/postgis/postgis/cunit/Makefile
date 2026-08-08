# **********************************************************************
# *
# * PostGIS - Spatial Types for PostgreSQL
# * http://postgis.net
# *
# * Copyright 2025 Darafei Praliaskouski <me@komzpa.net>
# *
# * This is free software; you can redistribute and/or modify it under
# * the terms of the GNU General Public Licence. See the COPYING file.
# *
# **********************************************************************

srcdir = .
top_builddir = ../..

CC=gcc
LIBTOOL=$(SHELL) $(top_builddir)/libtool
CFLAGS = -std=gnu11 -g -O2 -fno-math-errno -fno-signed-zeros -Wall -O2  -I/usr/local/geos/include -I/usr/local/proj/include  -I/usr/include/libxml2 -I/usr/local/gmp/include    -I/usr/include/json-c   -DNDEBUG -I/usr/local/gmp/include -I/usr/local/proj/includ -I/home/wangbin/pgsql_trace/include/server  -I.. -I$(top_builddir) -I../../liblwgeom -I../../liblwgeom -I../../libpgcommon -I../../libpgcommon
LDFLAGS =  -lm



OBJS = cu_tester.o

# Build the standalone histogram helper tester.
all: cu_tester

# Execute the suite directly; no installation step is required.
check: all
	$(LIBTOOL) --mode=execute ./cu_tester

# Link the tester with libtool; all helper code is header-only.
cu_tester: $(OBJS)
	$(LIBTOOL) --mode=link $(CC) $(CFLAGS) -o $@ $(OBJS) $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) cu_tester

clobber distclean: clean
	rm -f Makefile
