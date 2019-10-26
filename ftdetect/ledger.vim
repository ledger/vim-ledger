augroup VimLedger
	autocmd!
	autocmd BufNewFile,BufRead *.ldg,*.ledger,*.journal setlocal filetype=ledger
augroup END
