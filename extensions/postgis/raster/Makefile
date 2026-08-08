#############################################################################
#
# Master Makefile used to build WKT Raster
#
# Copyright (c) 2009 Sandro Santilli <strk@kbt.io>
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
#############################################################################

CC=gcc
CFLAGS=-I../liblwgeom -std=gnu11 -g -O2 -fno-math-errno -fno-signed-zeros -Wall -O2
LDFLAGS = -L/usr/local/gmp/lib  -L/usr/local/proj/lib64 -lm

with_pg = 
all:
	$(MAKE) 
ifdef with_pg
	$(MAKE) 
endif
	$(MAKE) 
ifdef with_pg
	$(MAKE) 
endif

corelib:
	$(MAKE) -C rt_core

pglib: corelib
	$(MAKE) -C rt_pg

rtloader: corelib
	$(MAKE) -C loader

rtpostgis.sql:
	$(MAKE) -C rt_pg rtpostgis.sql

install: all
	$(MAKE) -C loader install
ifdef with_pg
	$(MAKE) -C rt_pg install
	$(MAKE) -C scripts install
endif

uninstall:
	$(MAKE) -C loader uninstall
ifdef with_pg
	$(MAKE) -C rt_pg uninstall
	$(MAKE) -C scripts uninstall
endif

clean:
	$(MAKE) -C rt_core $@
	$(MAKE) -C loader $@
	$(MAKE) -C test $@
ifdef with_pg
	$(MAKE) -C rt_pg $@
	$(MAKE) -C scripts $@
endif

distclean: clean
	$(MAKE) -C rt_core $@
	$(MAKE) -C loader $@
	$(MAKE) -C test $@
ifdef with_pg
	$(MAKE) -C rt_pg $@
	$(MAKE) -C scripts $@
endif
	rm -f raster_config.h Makefile

check check-unit check-regress core-check:
	$(MAKE) -C test $@
