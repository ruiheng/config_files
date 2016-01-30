call plug#begin('~/.vim/plugged')

Plug 'tpope/vim-repeat'
Plug 'visualrepeat'
Plug 'tpope/vim-surround'
Plug 'jeffkreeftmeijer/vim-numbertoggle'
" Plug 'KabbAmine/zeavim.vim'
" Plug 'ruiheng/vim-haskell-cabal'
" Plug 'raichoo/haskell-vim'
Plug 'altercation/vim-colors-solarized'
Plug 'pbrisbin/vim-syntax-shakespeare'
Plug 'easymotion/vim-easymotion'
Plug 'kien/ctrlp.vim'
Plug 'tpope/vim-fugitive'
Plug 'spf13/vim-colors'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'bling/vim-airline'
Plug 'majutsushi/tagbar'
Plug 'scrooloose/syntastic', { 'on': 'SyntasticToggleMode' }
Plug 'bitc/vim-hdevtools'
" Plug 'eagletmt/ghcmod-vim'
" Plug 'godlygeek/tabular'
Plug 'junegunn/vim-easy-align'
Plug 'kshenoy/vim-signature'
" Plug 'Shougo/neocomplete.vim'
Plug 'blueyed/vim-diminactive'
" Plug 'Shougo/vimshell.vim'
Plug 'Shougo/vimproc.vim'
Plug 'chriskempson/base16-vim'
Plug 'szw/vim-ctrlspace'
Plug 't9md/vim-choosewin'
Plug 'thinca/vim-visualstar'
Plug 'rking/ag.vim'
Plug 'xolox/vim-misc' | Plug 'xolox/vim-session'

Plug 'tpope/vim-obsession'
Plug 'tpope/vim-sensible'

Plug 'freeo/vim-kalisi'
Plug 'cazador481/fakeclip.neovim'
Plug 'benekastah/neomake'
Plug 'Floobits/floobits-neovim'

" Add plugins to &runtimepath
call plug#end()

set hidden
let mapleader = ","
set et

let $NVIM_TUI_ENABLE_CURSOR_SHAPE=1

vmap <F2> "0p
nmap <F2> viw"0p

" see
" http://vim.wikia.com/wiki/Selecting_your_pasted_text
nnoremap <expr> <F4> '`[' . strpart(getregtype(), 0, 1) . '`]'

function MySetLocalTabStop (n)
        exec 'setlocal ts=' . a:n . ' sts=' . a:n . ' sw=' . a:n
endfunction

nmap <leader>t2 :call MySetLocalTabStop(2)<CR>
nmap <leader>t4 :call MySetLocalTabStop(4)<CR>
nmap <leader>t8 :call MySetLocalTabStop(8)<CR>

function MySetWigForHaskell ()
    set wig+=*.o,*.hi,*.dyn_hi,*.dyn_o,*/dist/*,cabal.sandbox.config
endfunction

if filereadable(expand('*.cabal'))
    call MySetWigForHaskell()
endif

cabbrev lvim
      \ lvim /\<lt><C-R><C-W>\>/gj
      \ **/*<C-R>=(expand("%:e")=="" ? "" : ".".expand("%:e"))<CR>
      \ <Bar> lw
      \ <C-Left><C-Left><C-Left>

" =============== toggle cursorline and cursorcolumn ===========
nnoremap <F5> :set cuc! cul!<CR>
imap <F5> <C-O><F5>

" ================ cabal commands ==========
nnoremap <F8> :wa<CR>:Neomake! cabal<CR>
imap <F8> <C-O><F8>

let g:neomake_cabal_errorformat = "%+C    %m,%W%f:%l:%c: Warning:,%E%f:%l:%c:,%f:%l:%c: %m,%f:%l:%c: Warning: %m,%+G%m"

"============= ctrlp =============
let g:ctrlp_open_new_file = 'r'
let g:ctrlp_map = '<leader>p'

function s:init_ctrlp ()
    if ( exists('g:loaded_ctrlp') && g:loaded_ctrlp )
        " nmap <leader>p :CtrlP<cr>
        " Easy bindings for its various modes
        nmap <leader>bb :CtrlPBuffer<cr>
        nmap <leader>bm :CtrlPMixed<cr>
        nmap <leader>bs :CtrlPMRU<cr>
    endif
endfunction

au VimEnter * call s:init_ctrlp()

"============= fugitive ================
function s:init_fugitive ()
    if exists('g:loaded_fugitive') || &cp
        nmap <leader>gs :Gstatus<CR>
        nmap <leader>gd :Gdiff<CR>
        nmap <leader>gc :Gcommit<CR>
        nmap <leader>gl :Glog<CR>
        nmap <leader>gp :Git push<CR>
    endif
endfunction

au VimEnter * call s:init_fugitive()

"============= ctrlspace ===============
function s:init_ctrlspace ()
    if exists("g:CtrlSpaceLoaded")
        if executable("ag")
            let g:CtrlSpaceGlobCommand = 'ag -l --nocolor -g ""'
        endif
        let g:CtrlSpaceDefaultMappingKey = "<leader><space>"
        let g:airline_exclude_preview = 1
    endif
endfunction

au VimEnter * call s:init_ctrlspace()

"=========== easy-align ================
function s:init_easy_align ()
    if exists("g:loaded_easy_align_plugin")
        vmap <Enter> <Plug>(EasyAlign)
        nmap ga <Plug>(EasyAlign)
    endif
endfunction

au VimEnter * call s:init_easy_align()

" ============= vim-session ==========
let g:session_autoload = 'no'

autocmd FileType haskell setlocal expandtab | call MySetLocalTabStop(4) | set cul
autocmd FileType elm setlocal expandtab | call MySetLocalTabStop(2)
autocmd FileType html setlocal noexpandtab si | call MySetLocalTabStop(4)
autocmd BufEnter *.hamlet setlocal expandtab si | call MySetLocalTabStop(4)
autocmd BufFilePost *.hamlet setlocal expandtab si | call MySetLocalTabStop(4)

" ======= quickfix window =======
" au TextChanged quickfix normal G " not working

" highlight current line of commit window and fugitive status window
au FileType gitcommit setlocal cul | syn on


function s:common_buf_enter()
    let filetypes_list = [ 'qt', 'gitcommit' ]
    if index(filetypes_list, &filetype) >= 0
        setlocal cul
        syn on
    endif
endfunction

" this line cause fugitive malfunction
" au WinEnter * call s:common_buf_enter()
