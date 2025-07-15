if !exists('quick_mode')
    let quick_mode = 0
endif

if !exists('haskell_mode')
    let haskell_mode = 0

    if !quick_mode
        if filereadable(expand('*.cabal')) || filereadable(expand('*.hs'))
            let haskell_mode = 1
        endif
    endif
endif

if !exists('rust_mode')
    let rust_mode = 0

    if !quick_mode
        if filereadable('Cargo.toml') || filereadable(expand('*.rs'))
            let rust_mode = 1
        endif
    endif
endif

if !exists('enable_lsp')
    let enable_lsp = haskell_mode || rust_mode
endif



if !quick_mode && has('nvim')
    let g:minisurround_disable=v:true
    let g:minicompletion_disable=v:true
    let g:ministarter_disable=v:true
    Plug 'echasnovski/mini.nvim'
endif

" ==== general language plugins ====

" Plug 'autozimu/LanguageClient-neovim', {
"   \ 'branch': 'next',
"   \ 'do': 'bash ./install.sh'
"   \ }

if !quick_mode && has('nvim')
    " Plug 'kevinhwang91/nvim-bqf'
endif

if !quick_mode
    " Plug 'bfrg/vim-qf-tooltip'        " syntax error ?
endif

if !quick_mode && has('nvim')
   " Plug 'kyazdani42/nvim-web-devicons'
   " Plug 'folke/trouble.nvim'
endif


if !quick_mode
   " support vim only, not nvim
   if !has('nvim')
      Plug 'bfrg/vim-qf-diagnostics'
   endif
   " if has('nvim')
   "    Plug 'nvim-lua/plenary.nvim'
   "    Plug 'nvim-lua/popup.nvim'
   " endif
endif

if !quick_mode
   Plug 'AndrewRadev/sideways.vim'
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


if enable_lsp && has('nvim')
    Plug 'neovim/nvim-lspconfig'
endif


if rust_mode && has('nvim')
    Plug 'williamboman/mason.nvim'
    Plug 'williamboman/mason-lspconfig.nvim'
    Plug 'simrat39/rust-tools.nvim'
endif


" ==== haskell ====
if haskell_mode
    " Plug 'KabbAmine/zeavim.vim'
    " Plug 'raichoo/haskell-vim'
    "Plug 'alx741/vim-stylishask'
    "Plug 'nbouscal/vim-stylish-haskell'
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


" ==== session ====
" Plug 'xolox/vim-misc' | Plug 'xolox/vim-session'
" Plug 'tpope/vim-obsession'

if has('nvim')
else
    Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
    Plug 'junegunn/fzf.vim'
endif

if !quick_mode
    "Plug 'kien/ctrlp.vim'
endif

Plug 'nathanaelkane/vim-indent-guides'

" Plug 'majutsushi/tagbar'
if !quick_mode
    Plug 'scrooloose/syntastic', { 'on': 'SyntasticToggleMode' }
endif

" Plug 'godlygeek/tabular'
" Plug 'Shougo/neocomplete.vim'

if has('nvim')
   " Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' } | Plug 'tbodt/deoplete-tabnine', { 'do': './install.sh' }
endif

" Plug 'blueyed/vim-diminactive'
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


" Add plugins to &runtimepath
call plug#end()



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

if has_key(g:plugs, 'neoformat')
    " let g:neoformat_verbose = 1
    if haskell_mode
        " let g:ormolu_ghc_opt = [ "TypeApplications", "RankNTypes" ]
        let g:neoformat_haskell_fourmolu = {
                    \ 'exe': 'fourmolu',
                    \ 'args': ['--no-cabal'],
                    \ 'stdin': 1,
                    \ }
        let g:neoformat_enabled_haskell = ['fourmolu']
    endif
endif

if has_key(g:plugs, 'lsp_config')
    if haskell_mode
lua <<EOF
        require('lspconfig')['hls'].setup{ filetypes = { 'haskell', 'lhaskell', 'cabal' }, }
EOF
    endif
endif

" ================ stack build commands ==========

if haskell_mode
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
        nnoremap <silent> <leader>ca :wa \| cexpr [] \| Neomake! stack<CR>

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
endif



if has_key(g:plugs, 'vim-session')
    let g:session_autoload = 'no'
endif




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


" ================ call stylish-haskell command ==========
if haskell_mode
    function RunStylishHaskell ()
        if &filetype == 'haskell'
            echo "running"
            %!stylish-haskell
        endif
    endfunction

    nnoremap <leader>hs call RunStylishHaskell()<CR>
endif

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

nnoremap <silent> <leader>cs :call NextFavoriteColorScheme()<CR>

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

if has_key(g:plugs, 'noice.nvim')
lua <<EOF
    require 'noice'.setup {
        messages = { enabled = false }
    }
EOF
endif



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

    nnoremap <silent> <leader>1 :WintabsGo 1<CR>
    nnoremap <silent> <leader>2 :WintabsGo 2<CR>
    nnoremap <silent> <leader>3 :WintabsGo 3<CR>
    nnoremap <silent> <leader>4 :WintabsGo 4<CR>
    nnoremap <silent> <leader>5 :WintabsGo 5<CR>
    nnoremap <silent> <leader>6 :WintabsGo 6<CR>
    nnoremap <silent> <leader>7 :WintabsGo 7<CR>
    nnoremap <silent> <leader>8 :WintabsGo 8<CR>
    nnoremap <silent> <leader>9 :WintabsGo 9<CR>
    nnoremap <silent> <leader>0 :WintabsGo 10<CR>
    nnoremap <silent> <leader>$ :WintabsLast<CR>

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

if has_key(g:plugs, 'trouble.nvim')
    nnoremap <leader>tq <cmd>TroubleToggle quickfix<cr>
    nnoremap <leader>tl <cmd>TroubleToggle loclist<cr>
endif

if has_key(g:plugs, 'vim-qf-diagnostics')
    nmap gh <plug>(qf-diagnostics-popup-quickfix)
    nmap gH <plug>(qf-diagnostics-popup-loclist)
endif


if has_key(g:plugs, 'sideways.vim')
    nnoremap <leader>xh :SidewaysLeft<cr>
    nnoremap <leader>xl :SidewaysRight<cr>
endif

if has_key(g:plugs, 'indent-blankline.nvim')
lua <<EOF
    require("indent_blankline").setup {
        -- for example, context is off by default, use this to turn it on
        show_current_context = true,
        show_current_context_start = true,
        use_treesitter = true,
    }
EOF
endif


if has_key(g:plugs, 'mini.nvim')
lua <<EOF
    require("mini.indentscope").setup {
    }
EOF
endif


if has_key(g:plugs, 'mason.nvim')
lua <<EOF
    require("mason").setup {
    }
EOF
endif


if has_key(g:plugs, 'rust-tools.nvim')
lua <<EOF
    local rt = require("rust-tools")

    rt.setup {
        server = {
            on_attach = function(_, bufnr)
                    -- Hover actions
                    vim.keymap.set("n", "<C-space>", rt.hover_actions.hover_actions, { buffer = bufnr })
                    -- code action groups
                    vim.keymap.set("n", "<leader>a", rt.code_action_group.code_action_group, { buffer = bufnr })
                end,
        },
    }
EOF
endif
