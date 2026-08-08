# **********************************************************************
# *
# * PostGIS - Spatial Types for PostgreSQL
# * http://postgis.net
# * Copyright 2008 Mark Cave-Ayland
# *
# * This is free software; you can redistribute and/or modify it under
# * the terms of the GNU General Public Licence. See the COPYING file.
# *
# **********************************************************************

srcdir = .
top_builddir = ..

CC=gcc
CFLAGS= -I$(srcdir)/../liblwgeom -I$(top_builddir)/liblwgeom  -I/usr/local/geos/include -I/usr/local/proj/include  -I/usr/include/libxml2 -I/usr/local/gmp/include    -I/usr/include/json-c   -DNDEBUG -I/usr/local/gmp/include -I/usr/local/proj/includ -std=gnu11 -g -O2 -fno-math-errno -fno-signed-zeros -Wall -O2 -I/home/wangbin/pgsql_trace/include/server -I/usr/local/proj/include  -fPIC -DPIC 
LDFLAGS= 

YACC=/usr/bin/bison
LEX=flex



# Standalone COMMON objects
SA_OBJS = \
	gserialized_gist.o \
	lwgeom_transform.o \
	lwgeom_cache.o \
	lwgeom_pg.o \
	shared_gserialized.o


SA_HEADERS = \
	lwgeom_pg.h \
	lwgeom_transform.h \
	lwgeom_cache.h \
	gserialized_gist.h

all: libpgcommon.a

# nothing to install or uninstall
install uninstall:

libpgcommon.a: $(SA_OBJS) $(SA_HEADERS)
	gcc-ar rs libpgcommon.a $(SA_OBJS)

maintainer-clean: clean

clean:
	$(MAKE) -C cunit clean
	rm -f $(SA_OBJS)
	rm -f $(NM_OBJS)
	rm -f libpgcommon.a

distclean: clean
	$(MAKE) -C cunit distclean
	rm -f Makefile

check: check-unit

check-regress:

check-unit: libpgcommon.a
	$(MAKE) -C cunit check

# Command to build each of the .o files
$(SA_OBJS): %.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(SA_OBJS): ../postgis_config.h

