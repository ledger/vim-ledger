" Vim filetype plugin file
" filetype: ledger
" by Johann Klähn; Use according to the terms of the GPL>=2.
" vim:ts=2:sw=2:sts=2:foldmethod=marker

if exists("b:did_ftplugin")
  finish
endif

let b:did_ftplugin = 1

let b:undo_ftplugin = "setlocal ".
                    \ "foldmethod< foldtext< ".
                    \ "include< comments< commentstring< omnifunc< formatprg<"

" don't fill fold lines --> cleaner look
setl fillchars="fold: "
setl foldtext=LedgerFoldText()
setl foldmethod=syntax
setl include=^!include
setl comments=b:;
setl commentstring=;%s
setl omnifunc=LedgerComplete

" set location of ledger binary for checking and auto-formatting
if ! exists("g:ledger_bin") || empty(g:ledger_bin) || ! executable(split(g:ledger_bin, '\s')[0])
  if executable('ledger')
    let g:ledger_bin = 'ledger'
  else
    unlet! g:ledger_bin
    echohl WarningMsg
    echomsg "ledger command not found. Set g:ledger_bin or extend $PATH ".
          \ "to enable error checking and auto-formatting."
    echohl None
  endif
endif

if exists("g:ledger_bin")
  exe 'setl formatprg='.substitute(g:ledger_bin, ' ', '\\ ', 'g').'\ -f\ -\ print'
endif

" You can set a maximal number of columns the fold text (excluding amount)
" will use by overriding g:ledger_maxwidth in your .vimrc.
" When maxwidth is zero, the amount will be displayed at the far right side
" of the screen.
if !exists('g:ledger_maxwidth')
  let g:ledger_maxwidth = 0
endif

if !exists('g:ledger_fillstring')
  let g:ledger_fillstring = ' '
endif

" You can set g:ledger_separator_col and g:ledger_separator_string to
" customize the behavior of the AlignCommodity command.
if !exists("g:ledger_separator_col")
    let g:ledger_separator_col = 50
endif
if !exists("g:ledger_separator_string")
    let g:ledger_separator_string = "."
endif

" If enabled this will list the most detailed matches at the top {{{
" of the completion list.
" For example when you have some accounts like this:
"   A:Ba:Bu
"   A:Bu:Bu
" and you complete on A:B:B normal behaviour may be the following
"   A:B:B
"   A:Bu:Bu
"   A:Bu
"   A:Ba:Bu
"   A:Ba
"   A
" with this option turned on it will be
"   A:B:B
"   A:Bu:Bu
"   A:Ba:Bu
"   A:Bu
"   A:Ba
"   A
" }}}
if !exists('g:ledger_detailed_first')
  let g:ledger_detailed_first = 1
endif

" only display exact matches (no parent accounts etc.)
if !exists('g:ledger_exact_only')
  let g:ledger_exact_only = 0
endif

" display original text / account name as completion
if !exists('g:ledger_include_original')
  let g:ledger_include_original = 0
endif

let s:rx_amount = '\('.
                \   '\%([0-9]\+\)'.
                \   '\%([,.][0-9]\+\)*'.
                \ '\|'.
                \   '[,.][0-9]\+'.
                \ '\)'.
                \ '\s*\%([[:alpha:]¢$€£]\+\s*\)\?'.
                \ '\%(\s*;.*\)\?$'

function! LedgerFoldText() "{{{1
  " find amount
  let amount = ""
  let lnum = v:foldstart
  while lnum <= v:foldend
    let line = getline(lnum)

    " Skip metadata/leading comment
    if line !~ '^\%(\s\+;\|\d\)'
      " No comment, look for amount...
      let groups = matchlist(line, s:rx_amount)
      if ! empty(groups)
        let amount = groups[1]
        break
      endif
    endif
    let lnum += 1
  endwhile

  let fmt = '%s %s '
  " strip whitespace at beginning and end of line
  let foldtext = substitute(getline(v:foldstart),
                          \ '\(^\s\+\|\s\+$\)', '', 'g')

  " number of columns foldtext can use
  let columns = s:get_columns()
  if g:ledger_maxwidth
    let columns = min([columns, g:ledger_maxwidth])
  endif
  let columns -= s:multibyte_strlen(printf(fmt, '', amount))

  " add spaces so the text is always long enough when we strip it
  " to a certain width (fake table)
  if strlen(g:ledger_fillstring)
    " add extra spaces so fillstring aligns
    let filen = s:multibyte_strlen(g:ledger_fillstring)
    let folen = s:multibyte_strlen(foldtext)
    let foldtext .= repeat(' ', filen - (folen%filen))

    let foldtext .= repeat(g:ledger_fillstring,
                  \ s:get_columns()/filen)
  else
    let foldtext .= repeat(' ', s:get_columns())
  endif

  " we don't use slices[:5], because that messes up multibyte characters
  let foldtext = substitute(foldtext, '.\{'.columns.'}\zs.*$', '', '')

  return printf(fmt, foldtext, amount)
endfunction "}}}

function! LedgerComplete(findstart, base) "{{{1
  if a:findstart
    let lnum = line('.')
    let line = getline('.')
    let b:compl_context = ''
    if line =~ '^\s\+[^[:blank:];]' "{{{2 (account)
      " only allow completion when in or at end of account name
      if matchend(line, '^\s\+\%(\S \S\|\S\)\+') >= col('.') - 1
        " the start of the first non-blank character
        " (excluding virtual-transaction and 'cleared' marks)
        " is the beginning of the account name
        let b:compl_context = 'account'
        return matchend(line, '^\s\+[*!]\?\s*[\[(]\?')
      endif
    elseif line =~ '^\d' "{{{2 (description)
      let pre = matchend(line, '^\d\S\+\%(([^)]*)\|[*?!]\|\s\)\+')
      if pre < col('.') - 1
        let b:compl_context = 'description'
        return pre
      endif
    elseif line =~ '^$' "{{{2 (new line)
      let b:compl_context = 'new'
    endif "}}}
    return -1
  else
    if ! exists('b:compl_cache')
      let b:compl_cache = s:collect_completion_data()
      let b:compl_cache['#'] = changenr()
    endif
    let update_cache = 0

    let results = []
    if b:compl_context == 'account' "{{{2 (account)
      let hierarchy = split(a:base, ':')
      if a:base =~ ':$'
        call add(hierarchy, '')
      endif

      let results = ledger#find_in_tree(b:compl_cache.accounts, hierarchy)
      let exacts = filter(copy(results), 'v:val[1]')

      if len(exacts) < 1
        " update cache if we have no exact matches
        let update_cache = 1
      endif

      if g:ledger_exact_only
        let results = exacts
      endif

      call map(results, 'v:val[0]')

      if g:ledger_detailed_first
        let results = reverse(sort(results, 's:sort_accounts_by_depth'))
      else
        let results = sort(results)
      endif
    elseif b:compl_context == 'description' "{{{2 (description)
      let results = ledger#filter_items(b:compl_cache.descriptions, a:base)

      if len(results) < 1
        let update_cache = 1
      endif
    elseif b:compl_context == 'new' "{{{2 (new line)
      return [strftime('%Y/%m/%d')]
    endif "}}}


    if g:ledger_include_original
      call insert(results, a:base)
    endif

    " no completion (apart from a:base) found. update cache if file has changed
    if update_cache && b:compl_cache['#'] != changenr()
      unlet b:compl_cache
      return LedgerComplete(a:findstart, a:base)
    else
      unlet! b:compl_context
      return results
    endif
  endif
endf "}}}

command! -range AlignCommodity :call ledger#align_commodity(<line1>, <line2>)

" Deprecated functions {{{1
let s:deprecated = {
  \ 'LedgerToggleTransactionState': 'ledger#transaction_state_toggle',
  \ 'LedgerSetTransactionState': 'ledger#transaction_state_set',
  \ 'LedgerSetDate': 'ledger#transaction_date_set'
  \ }

for [s:old, s:new] in items(s:deprecated)
  let s:fun = "function! {s:old}(...)\nechohl WarningMsg\necho '" . s:old .
            \ " is deprecated. Use ".s:new." instead!'\nechohl None\n" .
            \ "call call('" . s:new . "', a:000)\nendf"
  exe s:fun
endfor
unlet s:old s:new s:fun
" }}}1

function! s:collect_completion_data() "{{{1
  let transactions = ledger#transactions()
  let cache = {'descriptions': [], 'tags': {}, 'accounts': {}}
  let accounts = []
  for xact in transactions
    " collect descriptions
    if has_key(xact, 'description') && index(cache.descriptions, xact['description']) < 0
      call add(cache.descriptions, xact['description'])
    endif
    let [t, postings] = xact.parse_body()
    let tagdicts = [t]

    " collect account names
    for posting in postings
      if has_key(posting, 'tags')
        call add(tagdicts, posting.tags)
      endif
      " remove virtual-transaction-marks
      let name = substitute(posting.account, '\%(^\s*[\[(]\?\|[\])]\?\s*$\)', '', 'g')
      if index(accounts, name) < 0
        call add(accounts, name)
      endif
    endfor

    " collect tags
    for tags in tagdicts | for [tag, val] in items(tags)
      let values = get(cache.tags, tag, [])
      if index(values, val) < 0
        call add(values, val)
      endif
      let cache.tags[tag] = values
    endfor | endfor
  endfor

  for account in accounts
    let last = cache.accounts
    for part in split(account, ':')
      let last[part] = get(last, part, {})
      let last = last[part]
    endfor
  endfor

  return cache
endf "}}}

" Helper functions {{{1

" return length of string with fix for multibyte characters
function! s:multibyte_strlen(text) "{{{2
   return strlen(substitute(a:text, ".", "x", "g"))
endfunction "}}}

" get # of visible/usable columns in current window
function! s:get_columns() " {{{2
  " As long as vim doesn't provide a command natively,
  " we have to compute the available columns.
  " see :help todo.txt -> /Add argument to winwidth()/

  let columns = (winwidth(0) == 0 ? 80 : winwidth(0)) - &foldcolumn
  if &number
    " line('w$') is the line number of the last line
    let columns -= max([len(line('w$'))+1, &numberwidth])
  endif

  " are there any signs/is the sign column displayed?
  redir => signs
  silent execute 'sign place buffer='.string(bufnr("%"))
  redir END
  if signs =~# 'id='
    let columns -= 2
  endif

  return columns
endf "}}}

function! s:sort_accounts_by_depth(name1, name2) "{{{2
  let depth1 = s:count_expression(a:name1, ':')
  let depth2 = s:count_expression(a:name2, ':')
  return depth1 == depth2 ? 0 : depth1 > depth2 ? 1 : -1
endf "}}}

function! s:count_expression(text, expression) "{{{2
  return len(split(a:text, a:expression, 1))-1
endf "}}}
