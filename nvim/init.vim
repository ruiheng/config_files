if !exists('quick_mode')
    let quick_mode = 0
endif

"============= ctrlspace ===============
if executable("ag")
    let g:CtrlSpaceGlobCommand = 'ag -l --nocolor -g ""'
endif
let g:CtrlSpaceSetDefaultMapping = 1
let g:CtrlSpaceDefaultMappingKey = "<leader><space>"
let g:airline_exclude_preview = 1

call plug#begin('~/.vim/plugged')

Plug 'tpope/vim-repeat'
Plug 'vim-scripts/visualrepeat'
" Plug 'tpope/vim-surround'
Plug 'machakann/vim-sandwich'
Plug 'jeffkreeftmeijer/vim-numbertoggle'
Plug 'easymotion/vim-easymotion'
Plug 'unblevable/quick-scope'
Plug 'tpope/vim-abolish'
Plug 'yuttie/comfortable-motion.vim'
Plug 'equalsraf/neovim-gui-shim'
Plug 'machakann/vim-highlightedyank'

if !quick_mode
    Plug 'benekastah/neomake'
endif

"Plug 'w0rp/ale'

Plug 'kana/vim-textobj-user' | Plug 'machakann/vim-textobj-delimited'

Plug 'chrisbra/unicode.vim'


" ==== general language plugins ====

" Plug 'autozimu/LanguageClient-neovim', {
"   \ 'branch': 'next',
"   \ 'do': 'bash ./install.sh'
"   \ }

if !quick_mode
    " Plug 'neoclide/coc.nvim', {'branch': 'release'}
    Plug 'codota/tabnine-vim'
endif

if !quick_mode
    " Plug 'bfrg/vim-qf-tooltip'        " syntax error ?
endif

" ==== color schemes ====
Plug 'altercation/vim-colors-solarized'
Plug 'icymind/NeoSolarized'

if !quick_mode
    Plug 'spf13/vim-colors'
    Plug 'chriskempson/base16-vim'
    Plug 'freeo/vim-kalisi'
    Plug 'tomasr/molokai'
    Plug 'junegunn/seoul256.vim'
    Plug 'joshdick/OneDark.vim'
    Plug 'rakr/vim-one'
    Plug 'cormacrelf/vim-colors-github'
    Plug 'Luxed/ayu-vim'
endif

" ==== haskell ====
if !quick_mode
    " Plug 'KabbAmine/zeavim.vim'
    " Plug 'raichoo/haskell-vim'
    Plug 'neovimhaskell/haskell-vim'
    "Plug 'alx741/vim-stylishask'
    "Plug 'nbouscal/vim-stylish-haskell'
    Plug 'pbrisbin/vim-syntax-shakespeare', { 'for': [ 'hamlet', 'cassius', 'julius' ] }
    " Plug 'bitc/vim-hdevtools'
    " Plug 'eagletmt/ghcmod-vim'
    " Plug 'eagletmt/neco-ghc'
    " Plug 'kana/vim-textobj-user' | Plug 'gilligan/vim-textobj-haskell'
    " Plug 'ndmitchell/ghcid', { 'rtp': 'plugins/nvim' }

    " Plug 'parsonsmatt/intero-neovim'

    " Plug 'enomsg/vim-haskellConcealPlus'
endif

" ==== JavaScript JS ====
if !quick_mode
    Plug 'pangloss/vim-javascript'
endif

" ==== TypeScript ====
if !quick_mode
    " conflicts with <c-^>
    " Plug 'Quramy/tsuquyomi'

    Plug 'HerringtonDarkholme/yats.vim'
endif

" ==== HTML CSS ====
if !quick_mode
    Plug 'mattn/emmet-vim'
endif

" ==== VUE ====
if !quick_mode
    Plug 'posva/vim-vue'
endif

" ==== git ====
Plug 'tpope/vim-fugitive'
Plug 'junegunn/gv.vim'
Plug 'mhinz/vim-signify'

" ==== session ====
" Plug 'xolox/vim-misc' | Plug 'xolox/vim-session'
" Plug 'tpope/vim-obsession'

Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'

if !quick_mode
    "Plug 'kien/ctrlp.vim'
endif

Plug 'nathanaelkane/vim-indent-guides'

if !quick_mode
    Plug 'vim-airline/vim-airline' | Plug 'vim-airline/vim-airline-themes'
    Plug 'zefei/vim-wintabs'
    Plug 'zefei/vim-wintabs-powerline'
endif

" Plug 'majutsushi/tagbar'
if !quick_mode
    Plug 'scrooloose/syntastic', { 'on': 'SyntasticToggleMode' }
endif

" Plug 'godlygeek/tabular'
Plug 'junegunn/vim-easy-align'
Plug 'kshenoy/vim-signature'
" Plug 'Shougo/neocomplete.vim'

if has('nvim')
   " Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' } | Plug 'tbodt/deoplete-tabnine', { 'do': './install.sh' }
endif

Plug 'blueyed/vim-diminactive'
" Plug 'Shougo/vimshell.vim'
Plug 'Shougo/vimproc.vim'
" Plug 'Shougo/denite.nvim' | Plug 'Shougo/neomru.nvim'
"Plug 'vim-ctrlspace/vim-ctrlspace'
" Plug 'thinca/vim-visualstar'
" Plug 'rking/ag.vim'

Plug 'milkypostman/vim-togglelist'

"Plug 'cazador481/fakeclip.neovim'

" Plug 'Shougo/neosnippet'
" Plug 'Shougo/neosnippet-snippets'

" === SQL ==
if !quick_mode
    Plug 'lifepillar/pgsql.vim'
endif

" === experiment ==
Plug 'junegunn/vim-peekaboo'
Plug 'junegunn/vim-slash'
Plug 'junegunn/limelight.vim'
Plug 'takac/vim-hardtime'
Plug 'yssl/QFEnter'


" Add plugins to &runtimepath
call plug#end()

set hidden
let mapleader = "\<space>"
set et
set showcmd
" wintabs needs globals in sessionoptions to support sessions
set sessionoptions+=globals
"set sessionoptions+=options
set mouse=a
set shortmess+=c

if has('nvim')
    set wop=pum
endif

if has('termguicolors')
    set termguicolors
endif

" I don't need matchparen
let loaded_matchparen = 1

if executable('rg')
  set gp=rg\ --vimgrep
elseif executable('ag')
  set gp=ag\ --vimgrep
endif

nnoremap ,1 :tabn 1<CR>
nnoremap ,2 :tabn 2<CR>
nnoremap ,3 :tabn 3<CR>
nnoremap ,4 :tabn 4<CR>
nnoremap ,6 :tabn 6<CR>
nnoremap ,7 :tabn 7<CR>
nnoremap ,8 :tabn 8<CR>
nnoremap ,9 :tabn 9<CR>

vnoremap <F2> "0p
nnoremap <F2> viw"0p

" see
" http://vim.wikia.com/wiki/Selecting_your_pasted_text
nnoremap <expr> <leader>v '`[' . strpart(getregtype(), 0, 1) . '`]'

function MySetLocalTabStop (n)
        exec 'setlocal ts=' . a:n . ' sts=' . a:n . ' sw=' . a:n
endfunction

nnoremap <leader>t2 :call MySetLocalTabStop(2)<CR>
nnoremap <leader>t4 :call MySetLocalTabStop(4)<CR>
nnoremap <leader>t8 :call MySetLocalTabStop(8)<CR>

function MySetWigForHaskell ()
    set wig+=*.o,*.hi,*.dyn_hi,*.dyn_o,*/dist/*,cabal.sandbox.config,*.keter
endfunction

if filereadable(expand('*.cabal'))
    call MySetWigForHaskell()
endif

cabbrev lvim
      \ lvim /\<lt><C-R><C-W>\>/gj
      \ **/*<C-R>=(expand("%:e")=="" ? "" : ".".expand("%:e"))<CR>
      \ <Bar> lw
      \ <C-Left><C-Left><C-Left>

set titlestring=nvim\ %f\ [%{substitute(getcwd(),$HOME,\'~\',\'\')}]
set title

if v:version >= 700
  au BufLeave * let b:winview = winsaveview()
  au BufEnter * if(exists('b:winview')) | call winrestview(b:winview) | endif
endif


" switch to last activated tab
let g:lasttab = 1
nmap <Leader>tt :exe "tabn ".g:lasttab<CR>
au TabLeave * let g:lasttab = tabpagenr()


" do not highlight current item in quickfix window
highlight! link QuickFixLine Normal

if has_key(g:plugs, 'tabnine-vim') || has_key(g:plugs, 'YouCompleteMe')
    let g:ycm_key_list_select_completion = ['<Down>']
endif

if has_key(g:plugs, 'unicode.vim')
    " vmap <leader>dg <Plug>(MakeDigraph)
    " nmap <leader>dg <Plug>(MakeDigraph)
endif

" =============== ag =====================
let g:ag_prg="ag --vimgrep --smart-case"

cabbrev ag
      \ Ag -w <C-R><C-W>
      \ **/*<C-R>=(expand("%:e")=="" ? "" : ".".expand("%:e"))<CR>
      \ <C-Left><C-Left><C-Left>

cabbrev lag
      \ LAg -w <C-R><C-W>
      \ **/*<C-R>=(expand("%:e")=="" ? "" : ".".expand("%:e"))<CR>
      \ <C-Left><C-Left><C-Left>

" =============== toggle cursorline and cursorcolumn ===========
nnoremap <leader>cc :set cuc! cul!<CR>

" =============== toggle number display ===========
nnoremap <leader>n :set nu! rnu!<CR>

" =============== toggle paste mode ===========
nnoremap <leader>p :set paste!<CR>

" ================ stack build commands ==========

let g:ghc_error_format = join([
                \ '%E%f:%l:%c: error:%m',
                \ '%E%f:%l:%c: error:',
                \ '%W%f:%l:%c: warning:%m',
                \ '%W%f:%l:%c: warning:',
                \ '%-C %[ ]%#|',
                \ '%-C %[ %\\d]%#|%.%#',
                \ '%C %[ ]%#%m',
                \ '%-Z',
                \ '%-G%.%#: unregistering %.%#',
                \ '%-G%.%#: build %.%#',
                \ '%-G%.%#: copy/register',
                \ '%-GPreprocessing library for %.%#',
                \ '%-GPreprocessing executable %.%#',
                \ '%-GBuilding library for %.%#',
                \ '%-GBuilding executable %.%#',
                \ ], ',')


if has_key(g:plugs, 'neomake')
    nnoremap <leader>ca :wa \| cexpr [] \| Neomake! stack<CR>

    " let g:neomake_cabal_errorformat = "%+C    %m,%W%f:%l:%c: Warning:,%E%f:%l:%c:,%f:%l:%c: %m,%f:%l:%c: Warning: %m,%+G%m"
    " let g:neomake_cabal_maker = neomake#makers#cabal#cabal()

    " 'errorformat': "%+C    %m,%W%f:%l:%c: Warning:,%E%f:%l:%c:,%f:%l:%c: %m,%f:%l:%c: Warning: %m,%+G%m",
                " \ '%-GInstalling library in %.%#',
                " \ '%-GRegistering library for %.%#',

    let haskell_stack_build_flags_file = "stack-build-flags.txt"
    let haskell_stack_build_flags = []

    if filereadable(haskell_stack_build_flags_file)
        let haskell_stack_build_flags = readfile(haskell_stack_build_flags_file)
    endif

    let haskell_stack_build_args = ['build', '--no-terminal', '--fast', '.' ]
    if len(haskell_stack_build_flags) > 0
        let haskell_stack_build_args = ['build'] + haskell_stack_build_flags
    endif

    let g:neomake_stack_maker = {
            \ 'exe': 'stack',
            \ 'args': haskell_stack_build_args,
            \ 'buffer_output': 0,
            \ 'errorformat': g:ghc_error_format
            \ }

    let ghc_compile_flags_file = "ghc-compile-flags.txt"
    let ghc_compile_flags = []

    if filereadable(ghc_compile_flags_file)
        let ghc_compile_flags = readfile(ghc_compile_flags_file)
        let ghc_compile_output_dir = trim(system('stack path --dist-dir')) . '/build'
        let ghc_compile_args = ['ghc', '--', '-odir', ghc_compile_output_dir, '-hidir', ghc_compile_output_dir, '-c']
        if len(ghc_compile_flags) > 0
            let ghc_compile_args = ghc_compile_args + ghc_compile_flags
        endif

        let g:neomake_haskell_ghc_maker = {
                \ 'exe': 'stack',
                \ 'args': ghc_compile_args,
                \ 'buffer_output': 0,
                \ 'errorformat': g:ghc_error_format
                \ }
        let g:neomake_haskell_enabled_makers = [ 'ghc' ]
    endif

endif


if has_key(g:plugs, 'ale')
    if !exists('g:ale_fixers')
        let g:ale_fixers = {}
    endif
    let g:ale_fixers['haskell'] = [ 'cabal-ghc' ]
endif

if has_key(g:plugs, 'vim-airline')
    let g:airline_powerline_fonts = 1
endif

if has_key(g:plugs, 'fzf.vim')
    nnoremap <leader>f :Files<CR>
    nnoremap <leader>B :Buffers<CR>
    nnoremap <leader>T :Tags<CR>
endif

if has_key(g:plugs, 'ctrlp.vim')
    let g:ctrlp_open_new_file = 'r'
    let g:ctrlp_map = '<leader>p'

    function s:init_ctrlp ()
        if ( exists('g:loaded_ctrlp') && g:loaded_ctrlp )
            " nmap <leader>p :CtrlP<cr>
            " Easy bindings for its various modes
            nnoremap <leader>bb :CtrlPBuffer<cr>
            nnoremap <leader>bm :CtrlPMixed<cr>
            nnoremap <leader>bs :CtrlPMRU<cr>
        endif
    endfunction

    au VimEnter * call s:init_ctrlp()
endif


if has_key(g:plugs, 'vim-fugitive')
    function s:init_fugitive ()
        if exists('g:loaded_fugitive') || &cp
            nnoremap <leader>gs :Gstatus<CR>
            nnoremap <leader>gd :Gdiff<CR>
            nnoremap <leader>gc :Gcommit<CR>
            nnoremap <leader>gl :Glog<CR>
            nnoremap <leader>gp :Git push<CR>
        endif
    endfunction

    au VimEnter * call s:init_fugitive()
endif


if has_key(g:plugs, 'vim-easymotion')
    nmap <Plug>(easymotion-prefix)S <Plug>(easymotion-overwin-f)
endif


if has_key(g:plugs, 'comfortable-motion.vim')
    let g:comfortable_motion_friction = 0.0
    let g:comfortable_motion_air_drag = 5.0
endif


if has_key(g:plugs, 'vim-easy-align')
    function s:init_easy_align ()
        vmap <Enter> <Plug>(EasyAlign)
        nmap ga <Plug>(EasyAlign)
    endfunction

    au VimEnter * call s:init_easy_align()
endif


if has_key(g:plugs, 'vim-session')
    let g:session_autoload = 'no'
endif


if has_key(g:plugs, 'vim-togglelist')
    let g:toggle_list_no_mappings = 1
    nmap <script> <silent> <leader>lo :call ToggleLocationList()<CR>
    nmap <script> <silent> <leader>q :call ToggleQuickfixList()<CR>
endif


autocmd FileType haskell setlocal expandtab | call MySetLocalTabStop(2)
autocmd FileType elm setlocal expandtab | call MySetLocalTabStop(2)
autocmd FileType html setlocal noexpandtab si | call MySetLocalTabStop(2)
autocmd BufEnter *.hamlet setlocal expandtab si | call MySetLocalTabStop(2)
autocmd BufFilePost *.hamlet setlocal expandtab si | call MySetLocalTabStop(2)

" ======= quickfix window =======
" au TextChanged quickfix normal G " not working

" highlight current line of commit window and fugitive status window
au FileType gitcommit setlocal cul | syn on


function s:common_buf_enter()
    let filetypes_list = [ 'qf', 'gitcommit' ]
    if index(filetypes_list, &filetype) >= 0
        setlocal cul
        syn on
    endif
endfunction


if has_key(g:plugs, 'neosnippet')
    imap <C-k>     <Plug>(neosnippet_expand_or_jump)
    smap <C-k>     <Plug>(neosnippet_expand_or_jump)
    xmap <C-k>     <Plug>(neosnippet_expand_target)
    let g:neosnippet#snippets_directory = g:neosnippet#snippets_directory . ',' . expand('<sfile>:p') . '/snippets'
endif


if has_key(g:plugs, 'neco-ghc')
    " Disable haskell-vim omnifunc
    let g:haskellmode_completion_ghc = 0
    autocmd FileType haskell setlocal omnifunc=necoghc#omnifunc
endif


if has_key(g:plugs, 'intero-neovim')
    map <silent> <leader>T <Plug>InteroGenericType
endif

            " 'haskell': [ 'hie-wrapper', '--lsp' ],
if has_key(g:plugs, 'LanguageClient-neovim')
    let g:LanguageClient_serverCommands = {
            \ 'haskell': [ 'hie-wrapper', '+RTS', '-c', '-M1500M', '-K1G', '-A16M', '-RTS', '--lsp' ],
            \ }

    nnoremap <F7> :call LanguageClient_contextMenu()<CR>
    map <Leader>lk :call LanguageClient#textDocument_hover()<CR>
    map <Leader>lg :call LanguageClient#textDocument_definition()<CR>
    map <Leader>lr :call LanguageClient#textDocument_rename()<CR>
    map <Leader>lf :call LanguageClient#textDocument_formatting()<CR>
    map <Leader>lb :call LanguageClient#textDocument_references()<CR>
    map <Leader>la :call LanguageClient#textDocument_codeAction()<CR>
    map <Leader>ls :call LanguageClient#textDocument_documentSymbol()<CR>

    let g:LanguageClient_diagnosticsList = "Disabled"

    let g:LanguageClient_rootMarkers = ['stack.yaml']

    let g:LanguageClient_loggingFile = "/tmp/language-client.log"
    " let g:LanguageClient_loggingLevel = "DEBUG"
    let g:LanguageClient_serverStderr = "/tmp/language-server.log"

endif

" ================ call stylish-haskell command ==========
function RunStylishHaskell ()
    if &filetype == 'haskell'
        echo "running"
        %!stylish-haskell
    endif
endfunction

nnoremap <leader>hs call RunStylishHaskell()<CR>


if has_key(g:plugs, 'haskell-vim')
    let g:haskell_indent_disable=0
    nmap <leader>hi :let g:haskell_indent_disable=!g:haskell_indent_disable \| echo g:haskell_indent_disable<CR>
endif

" this line cause fugitive malfunction
" au WinEnter * call s:common_buf_enter()

" In this env, shada cause nvim error, disable it.
if has('nvim')
    " set shada=
endif


let g:session_autosave = 'no'


function RandomChooseFavoriteColorScheme ()
    let lst_len = len(g:favorite_color_schemes)
    if !lst_len
        return
    endif
    let idx = localtime() % lst_len
    exec "set" g:favorite_color_schemes[idx][1]
    exec "colorscheme" g:favorite_color_schemes[idx][0]
    redraw
    return idx
endfunction

function NextFavoriteColorScheme()
    if !exists("g:picked_favorite_color_scheme")
        return
    endif
    let lst_len = len(g:favorite_color_schemes)
    if !lst_len
        return
    endif
    let g:picked_favorite_color_scheme = (g:picked_favorite_color_scheme + 1) % lst_len
    let idx = g:picked_favorite_color_scheme
    exec "set" g:favorite_color_schemes[idx][1]
    exec "colorscheme" g:favorite_color_schemes[idx][0]
    redraw
endfunction

nnoremap <F3> :call NextFavoriteColorScheme()<CR>

" a list of color scheme to be picked randomly.
let g:favorite_color_schemes = [
        \ [ "base16-solarized-dark", "bg=dark" ],
        \ [ "base16-solarized-light", "bg=light" ],
        \ [ "base16-flat", "bg=dark" ],
        \ [ "base16-ocean", "bg=dark" ],
        \ [ "base16-ocean", "bg=light" ],
        \ [ "base16-eighties", "bg=dark" ],
        \ [ "base16-eighties", "bg=light" ],
        \ [ "kalisi", "bg=light" ],
        \ [ "kalisi", "bg=dark" ],
        \ [ "ayu", "bg=light" ],
        \ [ "ayu", "bg=dark" ],
        \ ]

if has_key(g:plugs, 'OneDark.vim')
    let g:onedark_terminal_italics = 1
    let g:favorite_color_schemes += [ [ 'onedark', 'bg=dark' ], [ 'onedark', 'bg=light' ] ]
endif

if has_key(g:plugs, 'NeoSolarized')
    let g:favorite_color_schemes += [ [ 'NeoSolarized', 'bg=dark' ], [ 'NeoSolarized', 'bg=light' ] ]
endif

if !quick_mode
    if !exists("g:picked_favorite_color_scheme")
        let g:picked_favorite_color_scheme = RandomChooseFavoriteColorScheme()
    endif
else
    set bg=dark
    colorscheme NeoSolarized
endif

" ---------------------------------------------
" copied from:
" https://github.com/neovim/neovim/issues/2127
"
augroup AutoSwap
        autocmd!
        autocmd SwapExists *  call AS_HandleSwapfile(expand('<afile>:p'), v:swapname)
augroup END

function! AS_HandleSwapfile (filename, swapname)
        " if swapfile is older than file itself, just get rid of it
        if getftime(v:swapname) < getftime(a:filename)
                call delete(v:swapname)
                let v:swapchoice = 'e'
        endif
endfunction

autocmd CursorHold,BufWritePost,BufReadPost,BufLeave *
  \ if isdirectory(expand("<amatch>:h")) | let &swapfile = &modified | endif

function! s:run_checktime()
  let special_filetypes_list = [ '', 'vim', 'qf', 'gitcommit' ]

  if index(special_filetypes_list, &filetype) < 0
        checktime
  endif
endfunction

augroup checktime
    au!
    if !has("gui_running")
        "silent! necessary otherwise throws errors when using command
        "line window.
        autocmd BufEnter,CursorHold,CursorHoldI,FocusGained,BufEnter,FocusLost,WinLeave *
                \ call s:run_checktime()
   endif
augroup END
" ---------------------------------------------


if has_key(g:plugs, 'tagbar')
    let g:tagbar_type_haskell = {
        \ 'ctagsbin'  : 'hasktags',
        \ 'ctagsargs' : '-x -c -o-',
        \ 'kinds'     : [
            \  'm:modules:0:1',
            \  'd:data: 0:1',
            \  'd_gadt: data gadt:0:1',
            \  't:type names:0:1',
            \  'nt:new types:0:1',
            \  'c:classes:0:1',
            \  'cons:constructors:1:1',
            \  'c_gadt:constructor gadt:1:1',
            \  'c_a:constructor accessors:1:1',
            \  'ft:function types:1:1',
            \  'fi:function implementations:0:1',
            \  'o:others:0:1'
        \ ],
        \ 'sro'        : '.',
        \ 'kind2scope' : {
            \ 'm' : 'module',
            \ 'c' : 'class',
            \ 'd' : 'data',
            \ 't' : 'type'
        \ },
        \ 'scope2kind' : {
            \ 'module' : 'm',
            \ 'class'  : 'c',
            \ 'data'   : 'd',
            \ 'type'   : 't'
        \ }
    \ }

    nnoremap <F9> :TagbarToggle<CR>
    imap <F9> <C-O><F9>
endif


if has_key(g:plugs, 'vim-wintabs')

    nnoremap <leader>1 :WintabsGo 1<CR>
    nnoremap <leader>2 :WintabsGo 2<CR>
    nnoremap <leader>3 :WintabsGo 3<CR>
    nnoremap <leader>4 :WintabsGo 4<CR>
    nnoremap <leader>5 :WintabsGo 5<CR>
    nnoremap <leader>6 :WintabsGo 6<CR>
    nnoremap <leader>7 :WintabsGo 7<CR>
    nnoremap <leader>8 :WintabsGo 8<CR>
    nnoremap <leader>9 :WintabsGo 9<CR>
    nnoremap <leader>0 :WintabsGo 10<CR>
    nnoremap <leader>$ :WintabsLast<CR>

    nmap gb <Plug>(wintabs_next)
    nmap gB <Plug>(wintabs_previous)
    nmap <C-T>c <Plug>(wintabs_close)
    nmap <C-T>o <Plug>(wintabs_only)
    nmap <C-W>c <Plug>(wintabs_close_window)
    nmap <C-W>o <Plug>(wintabs_only_window)
    command! Tabc WintabsCloseVimtab
    command! Tabo WintabsOnlyVimtab
    let g:wintabs_autoclose_vimtab = 1
    " let g:wintabs_ui_show_vimtab_name = 0
    let g:wintabs_display = 'tabline'
    let g:wintabs_ui_sep_spaceline = 'GT，'
    let g:wintabs_ui_buffer_name_format = '%o%t'
endif


if has_key(g:plugs, 'deoplete.nvim')
    if has('python3')
        " Use deoplete.
        call deoplete#custom#option({
          \ 'enable_at_startup': 1,
          \ 'enable_smart_case': 1,
          \ })

        " <C-h>, <BS>: close popup and delete backword char.
        inoremap <expr><C-h> deoplete#smart_close_popup()."\<C-h>"
        inoremap <expr><BS>  deoplete#smart_close_popup()."\<C-h>"

        " <CR>: close popup and save indent.
        inoremap <silent> <CR> <C-r>=<SID>my_cr_function()<CR>
        function! s:my_cr_function() abort
          return deoplete#close_popup() . "\<CR>"
        endfunction
    endif
endif


if has_key(g:plugs, 'denite')
    nnoremap <C-P>    :Denite -buffer-name=files file_rec<cr>
    nnoremap <space>/ :Denite -no-empty grep<cr>
    nnoremap <space>s :Denite buffer<cr>
endif


if has_key(g:plugs, 'vim-peekaboo')
    let g:peekaboo_delay = 750
endif

if has_key(g:plugs, 'vim-javascript')
    augroup javascript_folding
        au!
        au FileType javascript setlocal foldmethod=syntax
    augroup END
endif

if has_key(g:plugs, 'tsuquyomi')
    if has_key(g:plugs, 'syntastic')
        let g:tsuquyomi_disable_quickfix = 1
        let g:syntastic_typescript_checkers = ['tsuquyomi']
    endif
endif
