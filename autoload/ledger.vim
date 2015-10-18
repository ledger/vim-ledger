" vim:ts=2:sw=2:sts=2:foldmethod=marker
function! ledger#transaction_state_toggle(lnum, ...)
  if a:0 == 1
    let chars = a:1
  else
    let chars = ' *'
  endif
  let trans = s:transaction.from_lnum(a:lnum)
  if empty(trans) || has_key(trans, 'expr')
    return
  endif

  let old = has_key(trans, 'state') ? trans['state'] : ' '
  let i = stridx(chars, old) + 1
  let new = chars[i >= len(chars) ? 0 : i]

  call trans.set_state(new)

  call setline(trans['head'], trans.format_head())
endf

function! ledger#transaction_state_set(lnum, char)
  " modifies or sets the state of the transaction at the cursor,
  " removing the state alltogether if a:char is empty
  let trans = s:transaction.from_lnum(a:lnum)
  if empty(trans) || has_key(trans, 'expr')
    return
  endif

  call trans.set_state(a:char)

  call setline(trans['head'], trans.format_head())
endf

function! ledger#transaction_date_set(lnum, type, ...) "{{{1
  let time = a:0 == 1 ? a:1 : localtime()
  let trans = s:transaction.from_lnum(a:lnum)
  if empty(trans) || has_key(trans, 'expr')
    return
  endif

  let formatted = strftime('%Y/%m/%d', time)
  if has_key(trans, 'date') && ! empty(trans['date'])
    let date = split(trans['date'], '=')
  else
    let date = [formatted]
  endif

  if a:type =~? 'effective\|actual'
    echoerr "actual/effective arguments were replaced by primary/auxiliary"
    return
  endif

  if a:type ==? 'primary'
    let date[0] = formatted
  elseif a:type ==? 'auxiliary'
    if time < 0
      " remove auxiliary date
      let date = [date[0]]
    else
      " set auxiliary date
      if len(date) >= 2
        let date[1] = formatted
      else
        call add(date, formatted)
      endif
    endif
  elseif a:type ==? 'unshift'
    let date = [formatted, date[0]]
  endif

  let trans['date'] = join(date[0:1], '=')

  call setline(trans['head'], trans.format_head())
endf "}}}

" == get transactions ==

function! ledger#transaction_from_lnum(lnum)
  return s:transaction.from_lnum(a:lnum)
endf

function! ledger#transactions(...)
  if a:0 == 2
    let lnum = a:1
    let end = a:2
  elseif a:0 == 0
    let lnum = 1
    let end = line('$')
  else
    throw "wrong number of arguments for get_transactions()"
    return []
  endif

  " safe view / position
  let view = winsaveview()
  let fe = &foldenable
  set nofoldenable

  let transactions = []
  call cursor(lnum, 0)
  while lnum && lnum <= end
    let trans = s:transaction.from_lnum(lnum)
    if ! empty(trans)
      call add(transactions, trans)
      call cursor(trans['tail'], 0)
    endif
    let lnum = search('^[~=[:digit:]]', 'cW')
  endw

  " restore view / position
  let &foldenable = fe
  call winrestview(view)

  return transactions
endf

" == transaction object implementation ==

let s:transaction = {} "{{{1
function! s:transaction.new() dict
  return copy(s:transaction)
endf

function! s:transaction.from_lnum(lnum) dict "{{{2
  let [head, tail] = s:get_transaction_extents(a:lnum)
  if ! head
    return {}
  endif

  let trans = copy(s:transaction)
  let trans['head'] = head
  let trans['tail'] = tail

  " split off eventual comments at the end of line
  let line = split(getline(head), '\ze\s*\%(\t\|  \);', 1)
  if len(line) > 1
    let trans['appendix'] = join(line[1:], '')
  endif

  " parse rest of line
  " FIXME (minor): will not preserve spacing (see 'join(parts)')
  let parts = split(line[0], '\s\+')
  if parts[0] ==# '~'
    let trans['expr'] = join(parts[1:])
    return trans
  elseif parts[0] ==# '='
    let trans['auto'] = join(parts[1:])
    return trans
  elseif parts[0] !~ '^\d'
    " this case is avoided in s:get_transaction_extents(),
    " but we'll check anyway.
    return {}
  endif

  for part in parts
    if     ! has_key(trans, 'date')  && part =~ '^\d'
      let trans['date'] = part
    elseif ! has_key(trans, 'code')  && part =~ '^([^)]*)$'
      let trans['code'] = part[1:-2]
    elseif ! has_key(trans, 'state') && part =~ '^[[:punct:]]$'
      " the first character by itself is assumed to be the state of the transaction.
      let trans['state'] = part
    else
      " everything after date/code or state belongs to the description
      break
    endif
    call remove(parts, 0)
  endfor

  let trans['description'] = join(parts)
  return trans
endf "}}}

function! s:transaction.set_state(char) dict "{{{2
  if has_key(self, 'state') && a:char =~ '^\s*$'
    call remove(self, 'state')
  else
    let self['state'] = a:char
  endif
endf "}}}

function! s:transaction.parse_body(...) dict "{{{2
  if a:0 == 2
    let head = a:1
    let tail = a:2
  elseif a:0 == 0
    let head = self['head']
    let tail = self['tail']
  else
    throw "wrong number of arguments for parse_body()"
    return []
  endif

  if ! head || tail <= head
    return []
  endif

  let lnum = head
  let tags = {}
  let postings = []
  while lnum <= tail
    let line = split(getline(lnum), '\s*\%(\t\|  \);', 1)

    if line[0] =~ '^\s\+[^[:blank:];]'
      " posting
      let [state, rest] = matchlist(line[0], '^\s\+\([*!]\?\)\s*\(.*\)$')[1:2]
      if rest =~ '\t\|  '
        let [account, amount] = matchlist(rest, '^\(.\{-}\)\%(\t\|  \)\s*\(.\{-}\)\s*$')[1:2]
      else
        let amount = ''
        let account = matchstr(rest, '^\s*\zs.\{-}\ze\s*$')
      endif
      call add(postings, {'account': account, 'amount': amount, 'state': state})
    end

    " where are tags to be stored?
    if empty(postings)
      " they belong to the transaction
      let tag_container = tags
    else
      " they belong to last posting
      if ! has_key(postings[-1], 'tags')
        let postings[-1]['tags'] = {}
      endif
      let tag_container = postings[-1]['tags']
    endif

    let comment = join(line[1:], '  ;')
    if comment =~ '^\s*:'
      " tags without values
      for t in s:findall(comment, ':\zs[^:[:blank:]]\([^:]*[^:[:blank:]]\)\?\ze:')
        let tag_container[t] = ''
      endfor
    elseif comment =~ '^\s*[^:[:blank:]][^:]\+:'
      " tag with value
      let key = matchstr(comment, '^\s*\zs[^:]\+\ze:')
      if ! empty(key)
        let val = matchstr(comment, ':\s*\zs.*\ze\s*$')
        let tag_container[key] = val
      endif
    endif
    let lnum += 1
  endw
  return [tags, postings]
endf "}}}

function! s:transaction.format_head() dict "{{{2
  if has_key(self, 'expr')
    return '~ '.self['expr']
  elseif has_key(self, 'auto')
    return '= '.self['auto']
  endif

  let parts = []
  if has_key(self, 'date') | call add(parts, self['date']) | endif
  if has_key(self, 'state') | call add(parts, self['state']) | endif
  if has_key(self, 'code') | call add(parts, '('.self['code'].')') | endif
  if has_key(self, 'description') | call add(parts, self['description']) | endif

  let line = join(parts)
  if has_key(self, 'appendix') | let line .= self['appendix'] | endif

  return line
endf "}}}
"}}}

" == helper functions ==

function! s:get_transaction_extents(lnum)
  if ! (indent(a:lnum) || getline(a:lnum) =~ '^[~=[:digit:]]')
    " only do something if lnum is in a transaction
    return [0, 0]
  endif

  " safe view / position
  let view = winsaveview()
  let fe = &foldenable
  set nofoldenable

  call cursor(a:lnum, 0)
  let head = search('^[~=[:digit:]]', 'bcnW')
  let tail = search('^[^;[:blank:]]\S\+', 'nW')
  let tail = tail > head ? tail - 1 : line('$')

  " restore view / position
  let &foldenable = fe
  call winrestview(view)

  return head ? [head, tail] : [0, 0]
endf

function! ledger#find_in_tree(tree, levels)
  if empty(a:levels)
    return []
  endif
  let results = []
  let currentlvl = a:levels[0]
  let nextlvls = a:levels[1:]
  let branches = ledger#filter_items(keys(a:tree), currentlvl)
  let exact = empty(nextlvls)
  for branch in branches
    call add(results, [branch, exact])
    if ! empty(nextlvls)
      for [result, exact] in ledger#find_in_tree(a:tree[branch], nextlvls)
        call add(results, [branch.':'.result, exact])
      endfor
    endif
  endfor
  return results
endf

function! ledger#filter_items(list, keyword)
  " return only those items that start with a specified keyword
  return filter(copy(a:list), 'v:val =~ ''^\V'.substitute(a:keyword, '\\', '\\\\', 'g').'''')
endf

function! s:findall(text, rx)
  " returns all the matches in a string,
  " there will be overlapping matches according to :help match()
  let matches = []

  while 1
    let m = matchstr(a:text, a:rx, 0, len(matches)+1)
    if empty(m)
      break
    endif

    call add(matches, m)
  endw

  return matches
endf

" Move the cursor to the specified column, filling the line with spaces if necessary.
function! s:goto_col(pos)
  exec "normal" a:pos . "|"
  let diff = a:pos - virtcol('.')
  if diff > 0 | exec "normal" diff . "a " | endif
endf

" Align the amount expression after an account name at the decimal point.
"
" This function moves the amount expression of a posting so that the decimal
" separator is aligned at the column specified by g:ledger_align_at.
"
" For example, after selecting:
"
"   2015/05/09 Some Payee
"     Expenses:Other    $120,23  ; Tags here
"     Expenses:Something  $-4,99
"     Expenses:More                 ($12,34 + $16,32)
"
"  :'<,'>call ledger#align_commodity() produces:
"
"   2015/05/09 Some Payee
"      Expenses:Other                                    $120,23  ; Tags here
"      Expenses:Something                                 $-4,99
"      Expenses:More                                     ($12,34 + $16,32)
"
function! ledger#align_commodity()
  " Extract the part of the line after the account name (excluding spaces):
  let rhs = matchstr(getline('.'), '\m^\s\+[^;[:space:]].\{-}\(\t\|  \)\s*\zs.*$')
  if rhs != ''
    " Remove everything after the account name (including spaces):
    .s/\m^\s\+[^[:space:]].\{-}\zs\(\t\|  \).*$//
    if g:ledger_decimal_sep == ''
      let pos = matchend(rhs, '\m\d[^[:space:]]*')
    else
      " Find the position of the first decimal separator:
      let pos = match(rhs, '\V' . g:ledger_decimal_sep)
    endif
    " Go to the column that allows us to align the decimal separator at g:ledger_align_at:
    call s:goto_col(g:ledger_align_at - pos - 1)
    " Append the part of the line that was previously removed:
    exe 'normal a' . rhs
  endif
endf!

" Align the amount under the cursor and append/prepend the default currency.
function! ledger#align_amount_at_cursor()
  " Select and cut text:
  normal viWd
  " Find the position of the decimal separator
  let pos = match(@", g:ledger_decimal_sep) " Returns zero when the separator is the empty string
  " Paste text at the correct column and append/prepend default commodity:
  if g:ledger_commodity_before
    call s:goto_col(g:ledger_align_at - (pos > 0 ? pos : len(@"))  - len(g:ledger_default_commodity) - len(g:ledger_commodity_sep) - 1)
    exe 'normal a' . g:ledger_default_commodity . g:ledger_commodity_sep
    normal p
  else
    call s:goto_col(g:ledger_align_at - (pos > 0 ? pos : len(@")) - 1)
    exe 'normal pa' . g:ledger_commodity_sep . g:ledger_default_commodity
  endif
endf!

func! ledger#entry()
  " enter a new transaction based on the text in the current line.
  let l = line('.') - 1 " Insert transaction at the current line (i.e., below the line above the current one)
  let query = getline('.')
  normal "_dd
  exec l . 'read !' g:ledger_bin '-f' shellescape(expand('%')) 'entry' shellescape(query)
endfunc

" Report generation {{{1

" Helper functions and variables {{{2
" Position of report windows
let s:winpos_map = {
      \ "T": "to new",  "t": "abo new", "B": "bo new",  "b": "bel new",
      \ "L": "to vnew", "l": "abo vnew", "R": "bo vnew", "r": "bel vnew"
      \ }

function! s:error_message(msg)
  redraw  " See h:echo-redraw
  echohl ErrorMsg
  echo "\r"
  echomsg a:msg
  echohl NONE
endf

function! s:warning_message(msg)
  redraw  " See h:echo-redraw
  echohl WarningMsg
  echo "\r"
  echomsg a:msg
  echohl NONE
endf

" Open the quickfix/location window when it is not empty,
" closes it if it is empty.
"
" Optional parameters:
" a:1  Quickfix window title.
" a:2  Message to show when the window is empty.
"
" Returns 0 if the quickfix window is empty, 1 otherwise.
function! s:quickfixToggle(...)
  if g:ledger_use_location_list
    let l:list = 'l'
    let l:open = (len(getloclist(winnr())) > 0)
  else
    let l:list = 'c'
    let l:open = (len(getqflist()) > 0)
  endif

  if l:open
    execute (g:ledger_qf_vertical ? 'vert' : 'botright') l:list.'open' g:ledger_qf_size
    " Note that the following settings do not persist (e.g., when you close and re-open the quickfix window).
    " See: http://superuser.com/questions/356912/how-do-i-change-the-quickix-title-status-bar-in-vim
    if g:ledger_qf_hide_file
      set conceallevel=2
      set concealcursor=nc
      syntax match qfFile /^[^|]*/ transparent conceal
    endif
    if a:0 > 0
      let w:quickfix_title = a:1
    endif
    return 1
  endif

  execute l:list.'close'
  call s:warning_message((a:0 > 1) ? a:2 : 'No results')
  return 0
endf

" Populate a quickfix/location window with data. The argument must be a String
" or a List.
function! s:quickfix_populate(data)
  " Note that cexpr/lexpr always uses the global value of errorformat
  let l:efm = &errorformat  " Save global errorformat
  set errorformat=%EWhile\ parsing\ file\ \"%f\"\\,\ line\ %l:,%ZError:\ %m,%-C%.%#
  set errorformat+=%tarning:\ \"%f\"\\,\ line\ %l:\ %m
  " Format to parse command-line errors:
  set errorformat+=Error:\ %m
  set errorformat+=%f:%l\ %m
  set errorformat+=%-G%.%#
  execute (g:ledger_use_location_list ? 'l' : 'c').'getexpr' 'a:data'
  let &errorformat = l:efm  " Restore global errorformat
  return
endf

" Parse a list of ledger arguments and build a ledger command ready to be
" executed.
"
" Note that %, # and < *at the start* of an item are expanded by Vim. If you
" want to pass such characters to Ledger, escape them with a backslash.
"
" See also http://vim.wikia.com/wiki/Display_output_of_shell_commands_in_new_window
" See also https://groups.google.com/forum/#!topic/vim_use/4ZejMpt7TeU
function! s:ledger_cmd(arglist)
  let l:cmd = g:ledger_bin
  for l:part in a:arglist
    if l:part =~ '\v^[%#<]'
      let l:expanded_part = expand(l:part)
      let l:cmd .= ' ' . (l:expanded_part == "" ? l:part : shellescape(l:expanded_part))
    else
      let l:cmd .= ' ' . l:part
    endif
  endfor
  return l:cmd
endf

function! s:is_ledger_buffer()
  if getbufvar(winbufnr(winnr()), "&ft") !=# "ledger"
    call s:error_message("Please switch to a Ledger buffer first.")
    return 0
  endif
  return 1
endf
" }}}

" Run an arbitrary ledger command to process the current buffer, and show the
" output in a new buffer. If there are errors, no new buffer is opened: the
" errors are displayed in a quickfix window instead.
"
" Parameters:
" args  A string of Ledger arguments.
function! ledger#report(args)
  if !s:is_ledger_buffer() | return | endif
  let l:cmd = s:ledger_cmd(['-f', '%'] + split(a:args, ' '))
  if g:ledger_debug | return l:cmd | endif
  " Run Ledger
  let l:output = systemlist(l:cmd)
  if v:shell_error  " If there are errors, show them in a quickfix/location list.
    call s:quickfix_populate(l:output)
    call s:quickfixToggle('Errors', 'Unable to parse errors')
    return
  endif
  if empty(l:output)
    call s:warning_message('No results')
    return
  endif
  " Open a new buffer to show Ledger's output.
  execute get(s:winpos_map, g:ledger_winpos, "bo new")
  setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
  call append(0, l:output)
  setlocal nomodifiable
  " Set local mappings to quit window or lose focus.
  nnoremap <silent> <buffer> <tab> <c-w><c-w>
  nnoremap <silent> <buffer> q <c-w>c
  " Add some coloring to the report
  syntax match LedgerNumber /[^-]\d\+\([,.]\d\+\)\+/
  syntax match LedgerNegativeNumber /-\d\+\([,.]\d\+\)\+/
  syntax match LedgerImproperPerc /\d\d\d\+%/
endf

" Show a register report in a quickfix list.
function! ledger#register(args)
  if !s:is_ledger_buffer() | return | endif
  let l:cmd = s:ledger_cmd(extend([
        \ "register",
        \ "-f", "%",
        \ "--format='" . g:ledger_qf_register_format . "'",
        \ "--prepend-format='%(filename):%(beg_line) '"
        \ ], split(a:args, ' ')))
  if g:ledger_debug | return l:cmd | endif
  call s:quickfix_populate(systemlist(l:cmd))
  call s:quickfixToggle('Register report')
endf
