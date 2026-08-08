############################################################################
#
# Copyright (c) 2009-2011 Sandro Santilli <strk@kbt.io>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#############################################################################

MODULE_NAME=postgis_raster

POSTGIS_PGSQL_VERSION=180
MODULE_big=$(MODULE_NAME)-3
MODULEDIR=contrib/postgis-3.7
MODULEPATH    = $$libdir/$(MODULE_NAME)-3

ifeq (no,yes)
MODULEPATH=$$libdir/$(MODULE_NAME)-3.7
MODULE_big=$(MODULE_NAME)-3.7
endif

# Files to be copied to the contrib/ directory
DATA_built=rtpostgis.sql rtpostgis_upgrade.sql uninstall_rtpostgis.sql rtpostgis_legacy.sql
DATA=

# SQL preprocessor
SQLPP = /opt/rh/devtoolset-11/root/usr/bin/cpp -traditional-cpp -w -P -Upixel -Ubool

# SQL objects (files requiring pre-processing)
SQL_OBJS=rtpostgis.sql rtpostgis_drop.sql rtpostgis_upgrade_cleanup.sql rtpostgis_legacy.sql

# Objects to build using PGXS
OBJS = \
	rtpostgis.o \
	rtpg_internal.o \
	rtpg_legacy.o \
	rtpg_spatial_relationship.o \
	rtpg_mapalgebra.o \
	rtpg_utility.o \
	rtpg_inout.o \
	rtpg_wkb.o \
	rtpg_geometry.o \
	rtpg_raster_properties.o \
	rtpg_band_properties.o \
	rtpg_pixel.o \
	rtpg_create.o \
	rtpg_gdal.o \
	rtpg_statistics.o

# Libraries to link into the module (proj, geos)
#
# Note: we specify liblwgeom.a directly in SHLIB_LINK rather than using
# -L... -l options to prevent issues with some platforms trying to link
# to an existing liblwgeom.so in the PostgreSQL $libdir supplied by an
# older version of PostGIS, rather than with the static liblwgeom.a
# supplied with newer versions of PostGIS
#
LIBLWGEOM_LDFLAGS = ../../liblwgeom/.libs/liblwgeom.a
LIBLWGEOM_CFLAGS = -I../../liblwgeom -I../../liblwgeom
LIBPGCOMMON_CFLAGS = -I../../libpgcommon
LIBPGCOMMON_LDFLAGS = ../../libpgcommon/libpgcommon.a
LIBGDAL_CFLAGS=
LIBGDAL_LDFLAGS=
LIBPROJ_CFLAGS=-I/usr/local/proj/include

CC = gcc
PG_CPPFLAGS += \
	$(LIBLWGEOM_CFLAGS) \
	 -I/usr/local/geos/include -I/usr/local/proj/include  -I/usr/include/libxml2 -I/usr/local/gmp/include    -I/usr/include/json-c   -DNDEBUG -I/usr/local/gmp/include -I/usr/local/proj/includ \
	-std=gnu11 -g -O2 -fno-math-errno -fno-signed-zeros -Wall -O2 \
	 -fno-semantic-interposition \
	$(LIBGDAL_CFLAGS) \
	$(LIBPGCOMMON_CFLAGS) \
	$(LIBPROJ_CFLAGS) \
	-I./../rt_core \
	-I. \
	-I./.. \
	-I../..
SHLIB_LINK_F = ./../rt_core/librtcore.a $(LIBLWGEOM_LDFLAGS) $(LIBPGCOMMON_LDFLAGS) $(LIBGDAL_LDFLAGS)  -L/usr/local/geos/lib64 -lgeos_c -L/usr/local/proj/lib -lproj -ljson-c    -lxml2 -lz -lm -ldl -L/usr/local/gmp/lib -lgmp    -Wl,--exclude-libs,ALL -L/usr/local/gmp/lib  -L/usr/local/proj/lib64 -lm

# Extra files to remove during 'make clean'
EXTRA_CLEAN=$(SQL_OBJS) $(DATA_built) rtpostgis_upgrade.sql.in

# PGXS information
PG_CONFIG := /home/wangbin/pgsql_trace/bin/pg_config
PGXS := /home/wangbin/pgsql_trace/lib/pgxs/src/makefiles/pgxs.mk
# NO_TEMP_INSTALL is a workaround for a 9.5dev bug. See:
# http://www.postgresql.org/message-id/CAB7nPqTsR5o3g-fBi6jbsVdhfPiLFWQ_0cGU5=94Rv_8W3qvFA@mail.gmail.com
NO_TEMP_INSTALL=yes
include $(PGXS)



# Utility rule for use from outside
sql_objs: $(DATA_built)

# Set PERL _after_ the include of PGXS
PERL=/usr/bin/perl

# This is to workaround a bug in PGXS 8.4 win32 link line,
# see http://trac.osgeo.org/postgis/ticket/1158#comment:57
SHLIB_LINK := $(SHLIB_LINK_F) $(SHLIB_LINK)

# If REGRESS=1 passed as a parameter, change the default install paths
# so that no prefix is included. This allows us to relocate to a temporary
# directory for regression testing.
ifeq ($(REGRESS),1)
        bindir=/bin
        pkglibdir=/lib
        datadir=/share
        datamoduledir=contrib/postgis
endif

# Borrow the $libdir substitution from PGXS but customise by running the preprocessor
# and adding the version number
# replace @extschema@. with nothing, this is only used as placeholder for extension install
#
# TODO: create an intermediate product with @extschema@ in place, to reduce rules duplications
#       in the extension/ folder
#
%.sql: %.sql.in
	$(SQLPP) -I../../postgis/ $< > $@.tmp
	grep -v '^#' $@.tmp | \
	$(PERL) -lpe "s'MODULE_PATHNAME'\$(MODULEPATH)'g;s'@extschema@\.''g" > $@
	rm -f $@.tmp

../../liblwgeom/.libs/liblwgeom.a:
	$(MAKE) -C ../../liblwgeom

../rt_core/librtcore.a:
	$(MAKE) -C ../rt_core

../../libpgcommon/libpgcommon.a:
	$(MAKE) -C ../../libpgcommon

# Objects dependencies
# NOTE: the .a deps are really only link-time dependencies, but at this
#       time I dunno how to wncode those
$(OBJS): ../../liblwgeom/.libs/liblwgeom.a ../rt_core/librtcore.a ../../libpgcommon/libpgcommon.a ../../postgis_config.h ../../postgis_revision.h

# SQL objects deps here
$(SQL_OBJS): ../../postgis/sqldefines.h ../../postgis_revision.h

#this is redundant but trying to fold in with the  other just hangs
rtpostgis_upgrade.sql.in: rtpostgis.sql ../../utils/create_upgrade.pl
	$(PERL) ../../utils/create_upgrade.pl $< > $@

rtpostgis_upgrade.sql: ../../postgis/common_before_upgrade.sql rtpostgis_upgrade_cleanup.sql rtpostgis_upgrade.sql.in rtpostgis_drop.sql ../../postgis/common_after_upgrade.sql
	echo 'BEGIN;' > $@
	cat $^ | sed -e 's/^BEGIN;$$//' -e 's/^COMMIT;$$//' >> $@
	echo 'COMMIT;' >> $@

uninstall_rtpostgis.sql: rtpostgis.sql ../../utils/create_uninstall.pl
	$(PERL) ../../utils/create_uninstall.pl $< $(POSTGIS_PGSQL_VERSION) > $@

distclean: clean
	rm -f Makefile
