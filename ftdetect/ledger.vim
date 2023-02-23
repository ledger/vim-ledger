" vint: -ProhibitAutocmdWithNoGroup

" Semi-canonical or common file extensions
autocmd BufNewFile,BufRead *.journal,*.ledger,*.hledger setfiletype ledger

" Deprecated or suspiciusly low usage extensions
" TODO: Consider hiding these behind an off-by-default config flag
autocmd BufNewFile,BufRead *.ldg,*.j, setfiletype ledger
