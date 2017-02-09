" NOTE: You must, of course, install ag / the_silver_searcher

" FIXME: Delete deprecated options below on or after 2016-4 (6 months from when the deprecation warning was added) {{{

if exists("g:agprg")
  let g:ag_prg = g:agprg
  echohl WarningMsg
  call input('g:agprg is deprecated and will be removed. Please use g:ag_prg')
  echohl None
endif

if exists("g:aghighlight")
  let g:ag_highlight = g:aghighlight
  echohl WarningMsg
  call input('g:aghighlight is deprecated and will be removed. Please use g:ag_highlight')
  echohl None
endif

if exists("g:agformat")
  let g:ag_format = g:agformat
  echohl WarningMsg
  call input('g:agformat is deprecated and will be removed. Please use g:ag_format')
  echohl None
endif

" }}} FIXME: Delete the deprecated options above on or after 15-7 (6 months from when they were changed)

" Location of the ag utility
if !exists("g:ag_prg")
  " --vimgrep (consistent output we can parse) is available from version  0.25.0+
  if split(system("ag --version"), "[ \n\r\t]")[2] =~ '\d\+.\(\(2[5-9]\)\|\([3-9][0-9]\)\)\(.\d\+\)\?'
    let g:ag_prg="ag --vimgrep"
  else
    " --noheading seems odd here, but see https://github.com/ggreer/the_silver_searcher/issues/361
    let g:ag_prg="ag --column --nogroup --noheading"
  endif
endif

if !exists("g:ag_apply_qmappings")
  let g:ag_apply_qmappings=1
endif

if !exists("g:ag_apply_lmappings")
  let g:ag_apply_lmappings=1
endif

if !exists("g:ag_qhandler")
  let g:ag_qhandler="botright copen"
endif

if !exists("g:ag_lhandler")
  let g:ag_lhandler="botright lopen"
endif

if !exists("g:ag_mapping_message")
  let g:ag_mapping_message=1
endif

if !exists("g:ag_working_path_mode")
    let g:ag_working_path_mode = 'c'
endif

function! ag#AgBuffer(cmd, bang, args)
  let l:bufs = filter(range(1, bufnr('$')), 'buflisted(v:val)')
  let l:files = []
  for buf in l:bufs
    let l:file = fnamemodify(bufname(buf), ':p')
    if !isdirectory(l:file)
      call add(l:files, l:file)
    endif
  endfor
  call ag#Ag(a:cmd, a:bang, a:args . ' ' . join(l:files, ' '))
endfunction

function! ag#Ag(cmd, bang, args)
  let l:ag_executable = get(split(g:ag_prg, " "), 0)

  " Ensure that `ag` is installed
  if !executable(l:ag_executable)
    echoe "Ag command '" . l:ag_executable . "' was not found. Is the silver searcher installed and on your $PATH?"
    return
  endif

  " If no pattern is provided, search for the word under the cursor
  if empty(a:args)
    let l:grepargs = expand("<cword>")
  else
    let l:grepargs = a:args . join(a:000, ' ')
  end

  if empty(l:grepargs)
    echo "Usage: ':Ag {pattern}' (or just :Ag to search for the word under the cursor). See ':help :Ag' for more information."
    return
  endif

  " Format, used to manage column jump
  if a:cmd =~# '-g$'
    let s:ag_format_backup=g:ag_format
    let g:ag_format="%f"
  elseif exists("s:ag_format_backup")
    let g:ag_format=s:ag_format_backup
  elseif !exists("g:ag_format")
    let g:ag_format="%f:%l:%c:%m"
  endif

  let l:grepprg_bak=&grepprg
  let l:grepformat_bak=&grepformat
  let l:t_ti_bak=&t_ti
  let l:t_te_bak=&t_te
  try
    let &grepprg=g:ag_prg
    let &grepformat=g:ag_format
    set t_ti=
    set t_te=
    let l:args_path_type = <SID>argsContainsPath(l:grepargs)
    let l:path = ""
    let l:cwd = getcwd()
    if l:args_path_type == 2
      let l:root = s:guessProjectRoot()
      let l:path = substitute(l:grepargs, '.*\s\s*!\(\S*\)$', l:root.'\1', '')
      let l:grepargs = substitute(l:grepargs, '\(.*\)\s\s*!\S*$', '\1', '')
    elseif l:args_path_type == 1
      let l:path = ""
    else
      let l:path = input("Path: ", l:cwd, "dir")
      exec "normal <cr>"
      if l:path =~# "^!"
        let l:root = s:guessProjectRoot()
        let l:path = substitute(l:path, '^!\(\S*\)$', l:root.'\1', '')
      endif
    endif
    if !empty(l:path)
      let l:path = substitute(l:path, '\/\{2,}', '/', 'g')
      if !empty(l:path) && !isdirectory(l:path)
          echohl ErrorMsg | echom l:path . " is not a valid path" | echohl None
          return
      endif
      let l:path = fnamemodify(l:path, ':~:.')
    endif
    let l:bang = ""
    if a:bang == ""
        let l:bang = "!"
    else
        let l:bang = ""
    endif
    silent! execute a:cmd . l:bang . " " . escape(l:grepargs, '|') . " " . l:path
  finally
    let &grepprg=l:grepprg_bak
    let &grepformat=l:grepformat_bak
    let &t_ti=l:t_ti_bak
    let &t_te=l:t_te_bak
  endtry

  if a:cmd =~# '^l'
    let l:match_count = len(getloclist(winnr()))
  else
    let l:match_count = len(getqflist())
  endif

  if a:cmd =~# '^l' && l:match_count
    lclose
    exe g:ag_lhandler
    let l:apply_mappings = g:ag_apply_lmappings
    let l:matches_window_prefix = 'l' " we're using the location list
  elseif l:match_count
    cclose
    exe g:ag_qhandler
    let l:apply_mappings = g:ag_apply_qmappings
    let l:matches_window_prefix = 'c' " we're using the quickfix window
  endif

  " If highlighting is on, highlight the search keyword.
  if exists('g:ag_highlight')
    let @/ = matchstr(a:args, "\\v(-)\@<!(\<)\@<=\\w+|['\"]\\zs.{-}\\ze['\"]")
    call feedkeys(":let &hlsearch=1 \| echo \<CR>", 'n')
  end

  redraw!

  if l:match_count
    if l:apply_mappings
      nnoremap <silent> <buffer> h  <C-W><CR><C-w>K
      nnoremap <silent> <buffer> H  <C-W><CR><C-w>K<C-w>b
      nnoremap <silent> <buffer> o  <CR>
      nnoremap <silent> <buffer> t  <C-w><CR><C-w>T
      nnoremap <silent> <buffer> T  <C-w><CR><C-w>TgT<C-W><C-W>
      nnoremap <silent> <buffer> v  <C-w><CR><C-w>H<C-W>b<C-W>J<C-W>t

      exe 'nnoremap <silent> <buffer> e <CR><C-w><C-w>:' . l:matches_window_prefix .'close<CR>'
      exe 'nnoremap <silent> <buffer> go <CR>:' . l:matches_window_prefix . 'open<CR>'
      exe 'nnoremap <silent> <buffer> q  :' . l:matches_window_prefix . 'close<CR>'

      exe 'nnoremap <silent> <buffer> gv :let b:height=winheight(0)<CR><C-w><CR><C-w>H:' . l:matches_window_prefix . 'open<CR><C-w>J:exe printf(":normal %d\<lt>c-w>_", b:height)<CR>'
      " Interpretation:
      " :let b:height=winheight(0)<CR>                      Get the height of the quickfix/location list window
      " <CR><C-w>                                           Open the current item in a new split
      " <C-w>H                                              Slam the newly opened window against the left edge
      " :copen<CR> -or- :lopen<CR>                          Open either the quickfix window or the location list (whichever we were using)
      " <C-w>J                                              Slam the quickfix/location list window against the bottom edge
      " :exe printf(":normal %d\<lt>c-w>_", b:height)<CR>   Restore the quickfix/location list window's height from before we opened the match

      if g:ag_mapping_message && l:apply_mappings
        echom "ag.vim keys: q=quit <cr>/e/t/h/v=enter/edit/tab/split/vsplit go/T/H/gv=preview versions of same"
      endif
    endif
  else " Close the split window automatically:
    cclose
    lclose
    echohl WarningMsg
    echom 'No matches for "'.a:args.'"'
    echohl None
  endif
endfunction

function! ag#AgFromSearch(cmd, bang, args)
  let search =  getreg('/')
  " translate vim regular expression to perl regular expression.
  let search = substitute(search,'\(\\<\|\\>\)','\\b','g')
  call ag#Ag(a:cmd, a:bang, '"' .  search .'" '. a:args)
endfunction

function! ag#GetDocLocations()
  let dp = ''
  for p in split(&runtimepath,',')
    let p = p.'/doc/'
    if isdirectory(p)
      let dp = p.' '.dp
    endif
  endfor
  echom "dp:". dp
  return dp
endfunction

function! ag#AgHelp(cmd, bang, args)
  let args = a:args.' '.ag#GetDocLocations()
  call ag#Ag(a:cmd, a:bang, args)
endfunction

function! s:guessProjectRoot()
  let l:splitsearchdir = split(getcwd(), "/")

  while len(l:splitsearchdir) > 2
    let l:searchdir = '/'.join(l:splitsearchdir, '/').'/'
    for l:marker in ['.rootdir', '.git', '.hg', '.svn', 'bzr', '_darcs', 'build.xml']
      " found it! Return the dir
      if filereadable(l:searchdir.l:marker) || isdirectory(l:searchdir.l:marker)
        return l:searchdir
      endif
    endfor
    let l:splitsearchdir = l:splitsearchdir[0:-2] " Splice the list to get rid of the tail directory
  endwhile

  " Nothing found, fallback to current working dir
  return getcwd()
endfunction

" {{{ s:argsContainsPath
" if args last item is '!' will return 2, use root path
" if args contains path, return 1
function! s:argsContainsPath(args) 
  " if args is empty, it must be not contains path
  if empty(a:args)
    return 0
  endif

  let l:items = split(a:args)
  " if args length is 1, the args must be the pattern
  if len(l:items) == 1
    return 0
  endif

  let l:last_item = l:items[-1]
  " if the last item is begin with '-', it must be an option
  " else it must be a path
  if l:last_item[0] ==# '-'
    return 0
  elseif l:last_item[0] ==# '!'
    return 2
  else
    return 1
  endif
endfunction
" }}}

