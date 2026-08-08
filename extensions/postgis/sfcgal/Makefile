# **********************************************************************
# *
# * PostGIS - Spatial Types for PostgreSQL
# * http://postgis.net
# *
# * PostGIS is free software: you can redistribute it and/or modify
# * it under the terms of the GNU General Public License as published by
# * the Free Software Foundation, either version 2 of the License, or
# * (at your option) any later version.
# *
# * PostGIS is distributed in the hope that it will be useful,
# * but WITHOUT ANY WARRANTY; without even the implied warranty of
# * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# * GNU General Public License for more details.
# *
# * You should have received a copy of the GNU General Public License
# * along with PostGIS.  If not, see <http://www.gnu.org/licenses/>.
# *
# **********************************************************************
# *
# * Copyright 2020 Regina Obe
# * Copyright 2008 Mark Cave-Ayland
# *
# **********************************************************************
MODULE_NAME=postgis_sfcgal
MODULE_big=$(MODULE_NAME)-3
MODULEDIR=contrib/postgis-3.7
MODULEPATH=$$libdir/$(MODULE_NAME)-3
POSTGIS_PGSQL_VERSION=180

ifeq (no,yes)
MODULEPATH=$$libdir/$(MODULE_NAME)-3.7
MODULE_big=$(MODULE_NAME)-3.7
endif

# Files to be copied to the contrib/ directory
DATA_built=sfcgal.sql uninstall_sfcgal.sql sfcgal_upgrade.sql
DATA=

# SQL preprocessor
SQLPP = /opt/rh/devtoolset-11/root/usr/bin/cpp -traditional-cpp -w -P -Upixel -Ubool

# SQL objects (files requiring pre-processing)
SQL_OBJS = \
  sfcgal.sql

# Objects to build using PGXS

OBJS = lwgeom_sfcgal.o postgis_sfcgal_legacy.o

# Libraries to link into the module (proj, geos)
#
# Note: we specify liblwgeom.a directly in SHLIB_LINK rather than using
# -L... -l options to prevent issues with some platforms trying to link
# to an existing liblwgeom.so in the PostgreSQL $libdir supplied by an
# older version of PostGIS, rather than with the static liblwgeom.a
# supplied with newer versions of PostGIS
PG_CPPFLAGS += -I../liblwgeom -I../liblwgeom -I../libpgcommon -std=gnu11 -g -O2 -fno-math-errno -fno-signed-zeros -Wall -O2  -fno-semantic-interposition  -I/usr/local/geos/include -I/usr/local/proj/include  -I/usr/include/libxml2 -I/usr/local/gmp/include    -I/usr/include/json-c   -DNDEBUG -I/usr/local/gmp/include -I/usr/local/proj/includ  -fPIC -DPIC
SHLIB_LINK_F = ../libpgcommon/libpgcommon.a ../liblwgeom/.libs/liblwgeom.a  -L/usr/local/geos/lib64 -lgeos_c -L/usr/local/proj/lib -lproj -ljson-c    -lxml2 -lz -lm -ldl -L/usr/local/gmp/lib -lgmp    -Wl,--exclude-libs,ALL -L/usr/local/gmp/lib  -L/usr/local/proj/lib64 -lm

# Add SFCGAL Flags if defined
ifeq (,sfcgal)
PG_CPPFLAGS += 
SHLIB_LINK_F += 
endif

# Extra files to remove during 'make clean'
EXTRA_CLEAN=$(SQL_OBJS) \
	uninstall_sfcgal.sql \
	sfcgal_upgrade.sql.in \
	sfcgal_upgrade.sql \
	sfcgal_after_upgrade.sql \
	sfcgal_before_upgrade.sql

# PGXS information
PG_CONFIG := /home/wangbin/pgsql_trace/bin/pg_config
PGXS := /home/wangbin/pgsql_trace/lib/pgxs/src/makefiles/pgxs.mk
# NO_TEMP_INSTALL is a workaround for a 9.5dev bug. See:
# http://www.postgresql.org/message-id/CAB7nPqTsR5o3g-fBi6jbsVdhfPiLFWQ_0cGU5=94Rv_8W3qvFA@mail.gmail.com
NO_TEMP_INSTALL=yes
include $(PGXS)

VPATH := .

# Set PERL _after_ the include of PGXS
PERL=/usr/bin/perl

# This is to workaround a bug in PGXS 8.4 win32 link line,
# see http://trac.osgeo.org/postgis/ticket/1158#comment:57
SHLIB_LINK := $(SHLIB_LINK_F) $(SHLIB_LINK)

# NOTE: setting LDFLAGS explicitly here avoids getting the
# link line polluted by unrelated PostgreSQL switches that
# may be confusing and out-of-control for the builder of
# PostGIS
LDFLAGS = -L/usr/local/gmp/lib  -L/usr/local/proj/lib64 -lm

# If REGRESS=1 passed as a parameter, change the default install paths
# so that no prefix is included. This allows us to relocate to a temporary
# directory for regression testing.
ifeq ($(REGRESS),1)
	bindir=/bin
	pkglibdir=/lib
	datadir=/share
	datamoduledir=contrib/postgis
endif

# Make all PostGIS objects depend upon liblwgeom, so that if an underlying
# change is made, a PostGIS rebuild is triggered.
#
# Also they are all dependent on postgis_config.h
# and thus postgis_revision.h
#
$(OBJS): ../liblwgeom/.libs/liblwgeom.a ../libpgcommon/libpgcommon.a ../postgis_config.h ../postgis_revision.h

# SQL objects are also dependent on postgis_config.h for PostgreSQL
# version
$(SQL_OBJS): ../postgis_config.h ../postgis_revision.h


# Borrow the $libdir substitution from PGXS but customise by running the preprocessor
# and adding the version number
# replace @extschema@. with nothing, this is only used as placeholder for extension install
%.sql: %.sql.in
	$(SQLPP) -I../postgis $< > $@.tmp
	grep -v '^#' $@.tmp | \
	$(PERL) -lpe "s'MODULE_PATHNAME'\$(MODULEPATH)'g;s'@extschema@\.''g" > $@
	rm -f $@.tmp

sfcgal_upgrade.sql.in: sfcgal.sql ../utils/create_upgrade.pl
	$(PERL) ../utils/create_upgrade.pl $< > $@

sfcgal_upgrade.sql: sfcgal_before_upgrade.sql sfcgal_upgrade.sql.in sfcgal_after_upgrade.sql
	echo "BEGIN;" > $@
	cat $^ >> $@
	echo "COMMIT;" >> $@

uninstall_sfcgal_legacy.sql: sfcgal_legacy.sql ../utils/create_uninstall.pl
	$(PERL) ../utils/create_uninstall.pl $< $(POSTGIS_PGSQL_VERSION) > $@

uninstall_sfcgal.sql: sfcgal.sql ../utils/create_uninstall.pl
	$(PERL) ../utils/create_uninstall.pl $< $(POSTGIS_PGSQL_VERSION) > $@

distclean: clean
	rm -f Makefile
	rm -f regress/Makefile
	rm -f regress/tests.mk

check-unit:

check-regress:

maintainer-clean: distclean

check: check-regress

check-regress:
	$(MAKE) -C regress check
