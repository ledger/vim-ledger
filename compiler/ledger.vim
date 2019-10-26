" Vim Compiler File
" Compiler:	ledger
" by Johann Klähn; Use according to the terms of the GPL>=2.
" vim:ts=2:sw=2:sts=2:foldmethod=marker

scriptencoding utf-8

if exists('current_compiler')
  finish
endif
let current_compiler = 'ledger'

if exists(':CompilerSet') != 2
  command -nargs=* CompilerSet setlocal <args>
endif

" default value will be set in ftplugin
if ! exists('g:ledger_bin') || empty(g:ledger_bin) || ! executable(g:ledger_bin)
  finish
endif

" Capture Ledger errors (%-C ignores all lines between "While parsing..." and "Error:..."):
CompilerSet errorformat=%EWhile\ parsing\ file\ \"%f\"\\,\ line\ %l:,%ZError:\ %m,%-C%.%#
" Capture Ledger warnings:
CompilerSet errorformat+=%tarning:\ \"%f\"\\,\ line\ %l:\ %m
" Skip all other lines:
CompilerSet errorformat+=%-G%.%#

" Check file syntax
exe 'CompilerSet makeprg='.substitute(g:ledger_bin, ' ', '\\ ', 'g').'\ '.substitute(g:ledger_extra_options, ' ', '\\ ', 'g').'\ source\ %:S'

