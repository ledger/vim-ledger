PREFIX      = /usr/local
datarootdir = $(PREFIX)/share
vimdir      = $(datarootdir)/vim/vimfiles

CP    = install -p -m644
MKDIR = install -p -m755 -d

install: install-doc install-plugin

install-doc:
	$(MKDIR) $(DESTDIR)$(vimdir)/doc
	$(CP) doc/ledger.txt $(DESTDIR)$(vimdir)/doc/ledger.txt

install-plugin:
	$(MKDIR) $(DESTDIR)$(vimdir)/{autoload,compiler,ftdetect,ftplugin,indent,syntax}
	$(CP) autoload/ledger.vim $(DESTDIR)$(vimdir)/autoload/ledger.vim
	$(CP) compiler/ledger.vim $(DESTDIR)$(vimdir)/compiler/ledger.vim
	$(CP) ftdetect/ledger.vim $(DESTDIR)$(vimdir)/ftdetect/ledger.vim
	$(CP) ftplugin/ledger.vim $(DESTDIR)$(vimdir)/ftplugin/ledger.vim
	$(CP) indent/ledger.vim   $(DESTDIR)$(vimdir)/indent/ledger.vim
	$(CP) syntax/ledger.vim   $(DESTDIR)$(vimdir)/syntax/ledger.vim

.PHONY: install install-doc install-plugin
