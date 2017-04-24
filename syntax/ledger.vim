" Vim syntax file
" filetype: ledger
" by Johann Klähn; Use according to the terms of the GPL>=2.
" by Stefan Karrmann; Use according to the terms of the GPL>=2.
" by Wolfgang Oertl; Use according to the terms of the GPL>=2.
" vim:ts=2:sw=2:sts=2:foldmethod=marker

if version < 600
  syntax clear
elseif exists("b:current_sytax")
  finish
endif

" Force old regex engine (:help two-engines)
let s:oe = v:version < 704 ? '' : '\%#=1'
let s:lb1 = v:version < 704 ? '\@<=' : '\@1<='

let s:fb = get(g:, 'ledger_fold_blanks', 0)
let s:skip = s:fb > 0 ? '\|^\n' : ''
if s:fb == 1
  let s:skip .= '\n\@!'
endif

" for debugging
syntax clear

" DATE[=EDATE] [*|!] [(CODE)] DESC <-- first line of transaction
"   ACCOUNT AMOUNT [; NOTE]  <-- posting

exe 'syn region ledgerTransaction start=/^[[:digit:]~=]/ '.
  \ 'skip=/^\s'. s:skip . '/ end=/^/ fold keepend transparent '.
  \ 'contains=ledgerTransactionDate,ledgerMetadata,ledgerPosting,ledgerTransactionExpression'
syn match ledgerTransactionDate /^\d\S\+/ contained
syn match ledgerTransactionExpression /^[=~]\s\+\zs.*/ contained
syn match ledgerPosting /^\s\+[^[:blank:];][^;]*\ze\%($\|;\)/
    \ contained transparent contains=ledgerAccount,ledgerAmount,ledgerMetadata
" every space in an account name shall be surrounded by two non-spaces
" every account name ends with a tab, two spaces or the end of the line
exe 'syn match ledgerAccount '.
  \ '/'.s:oe.'^\s\+\zs\%(\S'.s:lb1.' \S\|\S\)\+\ze\%(  \|\t\|\s*$\)/ contained'
exe 'syn match ledgerAmount '.
  \ '/'.s:oe.'\S'.s:lb1.'\%(  \|\t\)\s*\zs\%([^;[:space:]]\|\s\+[^;[:space:]]\)\+/ contained'

syn region ledgerPreDeclaration start=/^\(account\|payee\|commodity\|tag\)/ skip=/^\s/ end=/^/
    \ keepend transparent
    \ contains=ledgerPreDeclarationType,ledgerPreDeclarationName,ledgerPreDeclarationDirective
syn match ledgerPreDeclarationType /^\(account\|payee\|commodity\|tag\)/ contained
syn match ledgerPreDeclarationName /^\S\+\s\+\zs.*/ contained
syn match ledgerPreDeclarationDirective /^\s\+\zs\S\+/ contained

syn match ledgerComment /^;.*$/
" comments at eol must be preceded by at least 2 spaces / 1 tab
syn region ledgerMetadata start=/\%(  \|\t\|^\s\+\);/ skip=/^\s\+;/ end=/^/
    \ keepend contained contains=ledgerTags,ledgerValueTag,ledgerTypedTag
exe 'syn match ledgerTags '.
    \ '/'.s:oe.'\%(\%(;\s*\|^tag\s\+\)\)\@<='.
    \ ':[^:[:space:]][^:]*\%(::\?[^:[:space:]][^:]*\)*:\s*$/ '.
    \ 'contained contains=ledgerTag'
syn match ledgerTag /:\zs[^:]\+\ze:/ contained
exe 'syn match ledgerValueTag '.
  \ '/'.s:oe.'\%(\%(;\|^tag\)[^:]\+\)\@<=[^:]\+:\ze.\+$/ contained'
exe 'syn match ledgerTypedTag '.
  \ '/'.s:oe.'\%(\%(;\|^tag\)[^:]\+\)\@<=[^:]\+::\ze.\+$/ contained'

syn region ledgerApply
    \ matchgroup=ledgerStartApply start=/^apply\>/
    \ matchgroup=ledgerEndApply end=/^end\s\+apply\>/
    \ contains=ledgerApplyHead,ledgerApply,ledgerTransaction,ledgerComment
exe 'syn match ledgerApplyHead '.
  \ '/'.s:oe.'\%(^apply\s\+\)\@<=\S.*$/ contained'

highlight default link ledgerComment Comment
highlight default link ledgerTransactionDate Constant
highlight default link ledgerTransactionExpression Statement
highlight default link ledgerMetadata Tag
highlight default link ledgerTypedTag Keyword
highlight default link ledgerValueTag Type
highlight default link ledgerTag Type
highlight default link ledgerStartApply Tag
highlight default link ledgerEndApply Tag
highlight default link ledgerApplyHead Type
highlight default link ledgerAccount Identifier
highlight default link ledgerAmount Number
highlight default link ledgerPreDeclarationType Type
highlight default link ledgerPreDeclarationName Identifier
highlight default link ledgerPreDeclarationDirective Type
 
" syncinc is easy: search for the first transaction.
syn sync clear
syn sync match ledgerSync grouphere ledgerTransaction "^[[:digit:]~=]"
 
let b:current_syntax = "ledger"
