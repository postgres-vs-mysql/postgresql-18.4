#############################################################################
#
# Master Makefile used to build extensions
# Copyright (C) 2012 Regina Obe and Leo Hsu <lr@pcorp.us>
# Copyright (C) 2012 Sandro Santilli <strk@kbt.io>
#
# This is free software; you can redistribute and/or modify it under
# the terms of the GNU General Public Licence. See the COPYING file.
#
#############################################################################

srcdir = .
SQLPP = /opt/rh/devtoolset-11/root/usr/bin/cpp -traditional-cpp -w -P -Upixel -Ubool
PERL=/usr/bin/perl
VPATH := $(srcdir)

SCRIPTS_BUILT = postgis_extension_helper.sql

SUBDIRS = postgis

ifeq (,raster)
	SUBDIRS += postgis_raster
endif
ifeq (topology,topology)
	SUBDIRS += postgis_topology
endif
ifeq (,sfcgal)
	SUBDIRS += postgis_sfcgal
endif

all clean distclean install uninstall installcheck install-extension-upgrades-from-known-versions:
	for DIR in $(SUBDIRS); do \
		echo "---- Making $@ in $${DIR}"; \
		$(MAKE) -C "$${DIR}" $@ || exit 1; \
	done

all: $(SCRIPTS_BUILT)

distclean: distclean-local

distclean-local: clean-local
	rm -f Makefile

check check-unit check-regress:
	@echo "Nothing to check"

# Generate any .sql file from .sql.in files by running them through the SQL pre-processor
%.sql: %.sql.in
	$(SQLPP) -I../postgis -I.. $< > $@.tmp
	grep -v '^#' $@.tmp > $@;
	rm -f $@.tmp

clean: clean-local

clean-local:
	rm -f $(SCRIPTS_BUILT)
