# Makefile for UnZip-K
#
# Seungwon Jeong <seungwon0@gmail.com>
#
# Copyright (C) 2010 by Seungwon jeong

SHELL := /bin/sh

INSTALL := install
INSTALL_PROGRAM := $(INSTALL)
INSTALL_DATA := $(INSTALL) -m 644

program := unzip-k
manpage := $(program).1

prefix := /usr/local
exec_prefix := $(prefix)
bindir := $(exec_prefix)/bin
datarootdir := $(prefix)/share
mandir := $(datarootdir)/man
man1dir := $(mandir)/man1

.SUFFIXES :

.PHONY : all
all : $(program) $(manpage)

$(manpage) :
	pod2man $(program) > $@

.PHONY : install
install : all
	$(INSTALL) -d -m 755 $(bindir)
	$(INSTALL_PROGRAM) $(program) $(bindir)
	$(INSTALL) -d -m 755 $(man1dir)
	$(INSTALL_DATA) $(manpage) $(man1dir)

.PHONY : uninstall
uninstall :
	-rm -f $(bindir)/$(program)
	-rm -f $(man1dir)/$(manpage)

.PHONY : clean
clean :
	-rm -f $(manpage)
