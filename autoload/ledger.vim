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

" Align currency on decimal point.
function! ledger#align_commodity(line1, line2)
    " Saving cursor position to adjust it if necessary.
    let cursor_col = col('.')
    let cursor_line = line('.')
    let separator_regex = '^\V\[^;]\{-}' . g:ledger_separator_string
    " This lets me increment at start of loop, because of continue statements.
    let i = a:line1 - 1
    while i < a:line2
        let i += 1
        let s = getline(i)
        " This matches an account name followed by two spaces. There may be
        " some conflicts with non-transaction syntax that I don't know about.
        " It won't match a comment or any non-indented line.
        let end_acc = matchend(s, '^\v +[^ ;].{-} {2}')
        if end_acc < 0 | continue | endif
        " Where does commodity amount begin?
        let end_space = matchend(s, '^ *', end_acc)
        " Find the first decimal point, not counting comments.
        let separator = matchend(s, separator_regex, end_space)
        if separator < 0
            " If there is no separator, pretend there's one after the last digit.
            let separator = matchend(s, '^\v[^;]*\d+') + 1
        endif
        if separator < 0 | continue | endif
        let has_spaces = end_space - end_acc
        let need_spaces = g:ledger_separator_col - separator + has_spaces
        if need_spaces < 0 | continue | endif
        call setline(i, s[0 : end_acc - 1] . repeat(" ", need_spaces) . s[ end_space : -1])
        if i == cursor_line && cursor_col >= end_acc
            " Adjust cursor position for continuity.
            call cursor(0, cursor_col + need_spaces - has_spaces)
        endif
    endwhile
endfunction
