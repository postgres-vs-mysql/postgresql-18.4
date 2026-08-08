include ./../upgradeable_versions.mk

EXTENSION     = postgis_topology
EXTVERSION    = 3.7.0dev
MINORVERSION  = 3.7
MODULEPATH    = $$libdir/$(EXTENSION)-3

# Scripts making up the extension file
# NOTE: order matters
EXTENSION_SCRIPTS = \
	extlock.sql \
	sql/topology.sql \
	sql_bits/mark_editable_objects.sql.in

ifeq (no,yes)
MODULEPATH=$$libdir/$(EXTENSION)-$(MINORVERSION)
endif
GREP = /usr/bin/grep

MICRO_NUMBER  = $(shell echo $(EXTVERSION) | sed "s/[0-9]\.[0-9]\.\([0-9]*\)[a-zA-Z]*[0-9]*/\1/")
PREREL_NUMBER = $(shell echo $(EXTVERSION) | \
                        sed "s/[0-9]\.[0-9]\.\(.*\)/\1/" | \
                        $(GREP) "[a-zA-Z]" | \
                        sed "s/[0-9][a-zA-Z]\([0-9]*\)[a-zA-Z]*/\1/")
MICRO_PREV    = $(shell if test "$(MICRO_NUMBER)x" != "x"; then expr $(MICRO_NUMBER) - 1; fi)
PREREL_PREV   = $(shell if test "$(PREREL_NUMBER)x" != "x"; then expr $(PREREL_NUMBER) - 1; fi)

PREREL_PREFIX = $(shell echo $(EXTVERSION) | \
                        sed "s/[0-9]\.[0-9]\.\(.*\)/\1/" | \
                        $(GREP) "[a-zA-Z]" | \
                        sed "s/\([0-9][a-zA-Z]*\)[0-9]*/\1/")

DATA_built = \
	$(EXTENSION).control \
	sql/$(EXTENSION)--$(EXTVERSION).sql \
	sql/$(EXTENSION)--unpackaged.sql \
	sql/$(EXTENSION)--unpackaged--$(EXTVERSION).sql \
	$(NULL)

# Scripts making up the extension minor upgrade file
# NOTE: order matters
EXTENSION_UPGRADE_SCRIPTS = \
	extlock.sql \
	sql/topology_upgrade.sql \
	sql_bits/mark_editable_objects.sql.in

EXTRA_CLEAN = sql/


all: sql/$(EXTENSION)--$(EXTVERSION).sql sql/$(EXTENSION)--unpackaged--$(EXTVERSION).sql sql/$(EXTENSION)--ANY--$(EXTVERSION).sql

$(EXTENSION).control: $(EXTENSION).control.in Makefile
	cat $< \
		| sed -e 's|@EXTVERSION@|$(EXTVERSION)|g' \
		> $@

sql:
	mkdir -p $@

sql/$(EXTENSION)--$(EXTVERSION).sql: $(EXTENSION_SCRIPTS) | sql
	cat $^ > $@

#strip BEGIN/COMMIT since these are not allowed in extensions
#strip CREATE SCHEMA since we force extension
# to create schema by setting schema to topology in control
sql/topology.sql: ../../topology/topology.sql | sql
	sed -e 's/BEGIN;//g' -e 's/COMMIT;//g' -e '/^CREATE SCHEMA/d;'  $< > $@

sql/$(EXTENSION)--unpackaged.sql: Makefile | sql
	echo "-- Nothing to do here" > $@

sql/$(EXTENSION)--unpackaged--$(EXTVERSION).sql: ../../topology/topology.sql ../../utils/create_unpackaged.pl sql/topology_upgrade.sql Makefile | sql
	cat $< | $(PERL) ../../utils/create_unpackaged.pl postgis_topology > $@
	# Upgrade after packaging (TODO: use ANY--TARGET path?)
	cat sql/topology_upgrade.sql >> $@

#upgrade script should have everything but table, schema, type creation/alter
#NOTE: we assume all object definitions end in ;
#first expression deletes all non-removable objects defined on same line
#second deletes all non-removable defined on multiple lines
#  the end of the body of object we assume ends in ;
#aggregates are special
#they can be dropped but we need to remove
#them from the extension first
sql/topology_upgrade.sql:  ../../topology/topology_upgrade.sql | sql
	sed -e 's/BEGIN;//g' -e 's/COMMIT;//g' -e '/^CREATE SCHEMA/d;'  $< > $@

sql/$(EXTENSION)--ANY--$(EXTVERSION).sql: $(EXTENSION_UPGRADE_SCRIPTS)
	cat $^ > $@

include ./../upgrade-paths-rules.mk

distclean: clean
	rm Makefile

PG_CONFIG := /home/wangbin/pgsql_trace/bin/pg_config
PGXS := /home/wangbin/pgsql_trace/lib/pgxs/src/makefiles/pgxs.mk
include $(PGXS)
PERL=/usr/bin/perl
INSTALL=/usr/bin/install -c
INSTALL_DATA=${INSTALL} -m 644
ifneq (/usr/bin/mkdir -p,)
	MKDIR_P = /usr/bin/mkdir -p
endif



top_srcdir = ../..
top_builddir = ../..
abs_topbuilddir=$(abspath $(top_builddir))
