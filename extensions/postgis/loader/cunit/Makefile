# **********************************************************************
# *
# * PostGIS - Spatial Types for PostgreSQL
# * http://postgis.net
# *
# * Copyright 2022 Sandro Santilli <strk@kbt.io>
# * Copyright 2008 Paul Ramsey, Mark Cave-Ayland
# *
# * This is free software; you can redistribute and/or modify it under
# * the terms of the GNU General Public Licence. See the COPYING file.
# *
# **********************************************************************

top_builddir = ../..
srcdir = .
top_srcdir = ../..

CC=gcc
CFLAGS=-std=gnu11 -g -O2 -fno-math-errno -fno-signed-zeros -Wall -O2
SHELL = /bin/sh
LIBTOOL = $(SHELL) $(top_builddir)/libtool

CUNIT_LDFLAGS=
GEOS_LDFLAGS=-L/usr/local/geos/lib64 -lgeos_c
CUNIT_CPPFLAGS = \
	-I$(srcdir)/.. \
	-I$(top_builddir)/liblwgeom \
	-I$(top_srcdir)/liblwgeom \
	-I.. \
	 \
	 -I/usr/local/geos/include -I/usr/local/proj/include  -I/usr/include/libxml2 -I/usr/local/gmp/include    -I/usr/include/json-c   -DNDEBUG -I/usr/local/gmp/include -I/usr/local/proj/includ

# GTK includes and libraries
GTK_CFLAGS =  
GTK_LIBS =  
GTK_WIN32_FLAGS = 

# PostgreSQL frontend CPPFLAGS and LDFLAGS (for compiling and linking with libpq)
PGSQL_FE_CPPFLAGS=-I/home/wangbin/pgsql_trace/include
PGSQL_FE_LDFLAGS=-L/home/wangbin/pgsql_trace/lib -lpq

# liblwgeom
LIBLWGEOM = $(top_builddir)/liblwgeom/.libs/liblwgeom.la

# iconv flags
ICONV_LDFLAGS= -lc
ICONV_CFLAGS=

# GetText includes and libraries
GETTEXT_CFLAGS = 
GETTEXT_LDFLAGS =  

# Proj flags
PROJ_CFLAGS=-I/usr/local/proj/include
PROJ_LDFLAGS=-L/usr/local/proj/lib -lproj

# Built out CFLAGS with ICONV and GETTEXT
CFLAGS += $(GETTEXT_CFLAGS) $(ICONV_CFLAGS) $(PROJ_CFLAGS)

# Build full linking line
LDFLAGS = $(GEOS_LDFLAGS) $(GETTEXT_LDFLAGS) $(PGSQL_FE_LDFLAGS) $(ICONV_LDFLAGS) $(CUNIT_LDFLAGS) $(PROJ_LDFLAGS)



# Object files
OBJS=	\
	cu_shp2pgsql.o \
	cu_tester.o

ifneq (/home/wangbin/pgsql_trace/bin/pg_config,no)
OBJS +=	\
	cu_pgsql2shp.o
endif

LOADER_OBJS= \
	../dbfopen.o \
	../shpopen.o \
	../getopt.o \
	../shpcommon.o \
	../safileio.o \
	../shp2pgsql-core.o

ifneq (/home/wangbin/pgsql_trace/bin/pg_config,no)
LOADER_OBJS +=	\
	../pgsql2shp-core.o
endif

# If we couldn't find the cunit library then display a helpful message
ifeq ($(CUNIT_LDFLAGS),)
all: requirements_not_met_cunit
check: requirements_not_met_cunit
else

$(LOADER_OBJS):
	$(MAKE) -C ..

# Build the unit tester
all: cu_tester

# Build and run the unit tester
check: cu_tester
	@./cu_tester

endif

# Build the main unit test executable
cu_tester: $(LOADER_OBJS) $(OBJS)
	$(LIBTOOL) --mode=link \
	$(CC) $(CFLAGS) $^ -o $@ $(LIBLWGEOM) $(LDFLAGS)

# Command to build each of the .o files
$(OBJS): %.o: %.c
	$(CC) $(CFLAGS) $(CUNIT_CPPFLAGS) $(GTK_CFLAGS) $(PGSQL_FE_CPPFLAGS) -c -o $@ $<

# Clean target
clean:
	rm -f $(OBJS)
	rm -f cu_tester

distclean: clean
	rm -f Makefile

# Requirements message
requirements_not_met_cunit:
	@echo
	@echo "WARNING:"
	@echo
	@echo "configure was unable to find CUnit which is required for unit testing."
	@echo "In order to enable unit testing, you must install CUnit and then re-run configure."
	@echo
