# gentoo-functions Makefile
# Copyright 2014-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

VERSION = 0.18
GITREF ?= $(VERSION)
PKG ?= gentoo-functions-$(VERSION)

ROOTPREFIX ?=
ROOTSBINDIR ?= $(ROOTPREFIX)/sbin
ROOTLIBEXECDIR ?= $(ROOTPREFIX)/lib/gentoo

PREFIX ?= /usr
MANDIR ?= $(PREFIX)/share/man

PROGRAMS = consoletype

all: $(PROGRAMS)

check: all
	./test-functions

install: all
	install -m 0755 -d $(DESTDIR)$(ROOTSBINDIR)
	install -m 0755 consoletype $(DESTDIR)$(ROOTSBINDIR)
	install -m 0755 -d $(DESTDIR)$(ROOTLIBEXECDIR)
	install -m 0644 functions.sh $(DESTDIR)$(ROOTLIBEXECDIR)
	install -m 0755 -d $(DESTDIR)$(MANDIR)/man1
	install -m 0644 consoletype.1 $(DESTDIR)$(MANDIR)/man1

clean:
	rm -rf $(PROGRAMS)

dist:
	git archive --prefix=$(PKG)/ $(GITREF) | xz > $(PKG).tar.xz

consoletype: consoletype.c

# vim: set ts=4 :
