# gentoo-functions Makefile
# Copyright 2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

VERSION = 0.12
GITREF ?= $(VERSION)
PKG ?= gentoo-functions-$(VERSION)

ROOTPREFIX ?=
ROOTSBINDIR ?= $(ROOTPREFIX)/sbin
ROOTLIBEXECDIR ?= $(ROOTPREFIX)/lib/gentoo

PREFIX ?= /usr
MANDIR ?= $(PREFIX)/share/man

PROGRAM_consoletype ?= consoletype

PROGRAMS = $(PROGRAM_consoletype)

all: $(PROGRAMS)

install: all
	install -m 0755 -d $(DESTDIR)$(ROOTLIBEXECDIR)
	install -m 0644 functions.sh $(DESTDIR)$(ROOTLIBEXECDIR)
	for p in $(PROGRAMS) ; do \
		install -m 0755 -d $(DESTDIR)$(ROOTSBINDIR) ; \
		install -m 0755 $${p} $(DESTDIR)$(ROOTSBINDIR) ; \
		install -m 0755 -d $(DESTDIR)$(MANDIR)/man1 ; \
		install -m 0644 $${p}.1 $(DESTDIR)$(MANDIR)/man1 ; \
	done

clean:
	rm -rf $(PROGRAMS)

dist:
	git archive --prefix=$(PKG)/ $(GITREF) | bzip2 > $(PKG).tar.bz2

consoletype: consoletype.c

# vim: set ts=4 :
