"============= ctrlspace ===============
if executable("ag")
    let g:CtrlSpaceGlobCommand = 'ag -l --nocolor -g ""'
endif
let g:CtrlSpaceSetDefaultMapping = 1
let g:CtrlSpaceDefaultMappingKey = "<leader><space>"
let g:airline_exclude_preview = 1

call plug#begin('~/.vim/plugged')

Plug 'tpope/vim-repeat'
Plug 'visualrepeat'
Plug 'tpope/vim-surround'
Plug 'jeffkreeftmeijer/vim-numbertoggle'
Plug 'easymotion/vim-easymotion'
Plug 'tpope/vim-abolish'

Plug 'benekastah/neomake'

" ==== color schemes ====
Plug 'altercation/vim-colors-solarized'
Plug 'spf13/vim-colors'
Plug 'chriskempson/base16-vim'
Plug 'freeo/vim-kalisi'
Plug 'tomasr/molokai'
Plug 'junegunn/seoul256.vim'

" ==== haskell ====
" Plug 'KabbAmine/zeavim.vim'
" Plug 'ruiheng/vim-haskell-cabal'
" Plug 'raichoo/haskell-vim'
Plug 'neovimhaskell/haskell-vim'
"Plug 'nbouscal/vim-stylish-haskell'
Plug 'pbrisbin/vim-syntax-shakespeare'
" Plug 'bitc/vim-hdevtools'
" Plug 'eagletmt/ghcmod-vim'
Plug 'eagletmt/neco-ghc'

" ==== web ====
" Plug 'posva/vim-vue'
" Plug 'digitaltoad/vim-pug'

" ==== git ====
Plug 'tpope/vim-fugitive'
Plug 'junegunn/gv.vim'
Plug 'mhinz/vim-signify'

" ==== session ====
" Plug 'xolox/vim-misc' | Plug 'xolox/vim-session'
" Plug 'tpope/vim-obsession'

Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'kien/ctrlp.vim'
Plug 'nathanaelkane/vim-indent-guides'

Plug 'vim-airline/vim-airline' | Plug 'vim-airline/vim-airline-themes'
Plug 'zefei/vim-wintabs'

Plug 'majutsushi/tagbar'
Plug 'scrooloose/syntastic', { 'on': 'SyntasticToggleMode' }
" Plug 'godlygeek/tabular'
Plug 'junegunn/vim-easy-align'
Plug 'kshenoy/vim-signature'
" Plug 'Shougo/neocomplete.vim'
Plug 'Shougo/deoplete.nvim'
Plug 'blueyed/vim-diminactive'
" Plug 'Shougo/vimshell.vim'
Plug 'Shougo/vimproc.vim'
" Plug 'Shougo/denite.nvim' | Plug 'Shougo/neomru.nvim'
"Plug 'vim-ctrlspace/vim-ctrlspace'
" Plug 'thinca/vim-visualstar'
Plug 'rking/ag.vim'

Plug 'milkypostman/vim-togglelist'

"Plug 'cazador481/fakeclip.neovim'

Plug 'Shougo/neosnippet'
Plug 'Shougo/neosnippet-snippets'

" === experiment ==
Plug 'junegunn/vim-peekaboo'
Plug 'junegunn/vim-slash'
Plug 'junegunn/limelight.vim'
Plug 'takac/vim-hardtime'


" Add plugins to &runtimepath
call plug#end()

set hidden
let mapleader = "\<space>"
set et
set showcmd
set sessionoptions+=globals

let $NVIM_TUI_ENABLE_CURSOR_SHAPE=1

set termguicolors

" I don't need matchparen
let loaded_matchparen = 1

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
nnoremap <expr> <F4> '`[' . strpart(getregtype(), 0, 1) . '`]'

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
nnoremap <F5> :set cuc! cul!<CR>
inoremap <F5> <C-O><F5>

" ================ cabal commands ==========
" let g:neomake_cabal_errorformat = "%+C    %m,%W%f:%l:%c: Warning:,%E%f:%l:%c:,%f:%l:%c: %m,%f:%l:%c: Warning: %m,%+G%m"
nnoremap <F8> :wa \| Neomake! cabal<CR>
inoremap <F8> <C-O><F8>


" let g:neomake_stack_maker = {
"         \ 'exe': 'stack',
"         \ 'args': ['build'],
"         \ 'errorformat': "%+C    %m,%W%f:%l:%c: Warning:,%E%f:%l:%c:,%f:%l:%c: %m,%f:%l:%c: Warning: %m,%+G%m",
"         \ }


if has_key(g:plugs, 'vim-airline')
    let g:airline_powerline_fonts = 1
endif

if has_key(g:plugs, 'fzf')
    nnoremap <leader>f :FZF<CR>
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
endif


if has_key(g:plugs, 'neco-ghc')
    " Disable haskell-vim omnifunc
    let g:haskellmode_completion_ghc = 0
    autocmd FileType haskell setlocal omnifunc=necoghc#omnifunc
endif


" ================ call stylish-haskell command ==========
function RunStylishHaskell ()
    if &filetype == 'haskell'
        echo "running"
        %!stylish-haskell
    endif
endfunction

nnoremap <leader>hs call RunStylishHaskell()<CR>


" this line cause fugitive malfunction
" au WinEnter * call s:common_buf_enter()

" In this env, shada cause nvim error, disable it.
set shada=


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
        \ [ "darkblue", "bg=dark" ],
        \ [ "base16-solarized-dark", "bg=dark" ],
        \ [ "base16-solarized-light", "bg=light" ],
        \ [ "base16-flat", "bg=dark" ],
        \ [ "base16-apathy", "bg=dark" ],
        \ [ "base16-apathy", "bg=light" ],
        \ [ "base16-codeschool", "bg=dark" ],
        \ [ "base16-codeschool", "bg=light" ],
        \ [ "base16-ocean", "bg=dark" ],
        \ [ "base16-ocean", "bg=light" ],
        \ [ "base16-eighties", "bg=dark" ],
        \ [ "base16-eighties", "bg=light" ],
        \ [ "base16-mocha", "bg=dark" ],
        \ [ "base16-mocha", "bg=light" ],
        \ [ "base16-atelier-estuary", "bg=light" ],
        \ [ "kalisi", "bg=light" ],
        \ [ "kalisi", "bg=dark" ],
        \ ]

if !exists("g:picked_favorite_color_scheme")
    let g:picked_favorite_color_scheme = RandomChooseFavoriteColorScheme()
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
  let special_filetypes_list = [ 'vim', 'qf', 'gitcommit' ]

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
    let g:wintabs_ui_show_vimtab_name = 2
    let g:wintabs_display = 'tabline'
    let g:wintabs_ui_sep_spaceline = 'GT'
endif


if has_key(g:plugs, 'deoplete.nvim')
    if has('python3')
        " Use deoplete.
        let g:deoplete#enable_at_startup = 1
        " Use smartcase.
        let g:deoplete#enable_smart_case = 1

        " <C-h>, <BS>: close popup and delete backword char.
        inoremap <expr><C-h> deoplete#mappings#smart_close_popup()."\<C-h>"
        inoremap <expr><BS>  deoplete#mappings#smart_close_popup()."\<C-h>"

        " <CR>: close popup and save indent.
        inoremap <silent> <CR> <C-r>=<SID>my_cr_function()<CR>
        function! s:my_cr_function() abort
          return deoplete#mappings#close_popup() . "\<CR>"
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
