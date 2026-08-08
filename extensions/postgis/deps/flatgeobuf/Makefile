#/**********************************************************************
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
# * Copyright 2021 Björn Harrtell
# * Copyright 2022 Sandro Santilli <strk@kbt.io>
# *
# **********************************************************************/

top_builddir = ../..
top_srcdir = ../..
srcdir = .
libdir = ${exec_prefix}/lib

CXX = gcc -std=c++11 -x c++
# This ugly -Dflatbuffers=postgis_flatbuffers is to prevent potential subtle
# clash with other flatbuffers copies that could come from GDAL or its
# dependencies.
CXXFLAGS =-I$(top_srcdir)/liblwgeom -I$(top_builddir)/liblwgeom -I$(srcdir)/include  -I/usr/local/geos/include -I/usr/local/proj/include  -I/usr/include/libxml2 -I/usr/local/gmp/include    -I/usr/include/json-c   -DNDEBUG -I/usr/local/gmp/include -I/usr/local/proj/includ   -fPIC -DPIC -Dflatbuffers=postgis_flatbuffers
LDFLAGS = -L/usr/local/gmp/lib  -L/usr/local/proj/lib64 -lm
LIBTOOL = $(SHELL) $(top_builddir)/libtool



FLATGEOBUF_OBJS = \
	flatgeobuf_c.o geometrywriter.o geometryreader.o packedrtree.o

FLATGEOBUF_HEADERS = \
	flatgeobuf_c.h \
	geometrywriter.h \
	geometryreader.h \
	packedrtree.h \
	include/flatbuffers/flatbuffers.h \
	include/flatbuffers/base.h \
	include/flatbuffers/stl_emulation.h

all: libflatgeobuf.la

libflatgeobuf.la: $(FLATGEOBUF_OBJS)
	gcc-ar rs libflatgeobuf.la $(FLATGEOBUF_OBJS)

$(FLATGEOBUF_OBJS): %.o: %.cpp ../../liblwgeom/liblwgeom.h $(FLATGEOBUF_HEADERS)
	$(CXX) $(CXXFLAGS) -c -o $@ $<

../../liblwgeom/liblwgeom.h:
	$(MAKE) -C ../../liblwgeom liblwgeom.h

clean:
	rm -f libflatgeobuf.la $(FLATGEOBUF_OBJS)

distclean: clean
	rm -f Makefile


install:

uninstall:

check:

.PHONY: clean distclean install uninstall check
