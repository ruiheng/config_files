-- 定义函数设置全局变量
local function g_set(name, value)
    vim.g[name] = value
end

-- 检查并设置 quick_mode
if vim.g.quick_mode == nil then
    g_set('quick_mode', 0)
end

-- 检查并设置 haskell_mode
if vim.g.haskell_mode == nil then
    g_set('haskell_mode', 0)

    if vim.g.quick_mode == 0 then
        if vim.fn.filereadable(vim.fn.expand('*.cabal')) == 1 or vim.fn.filereadable(vim.fn.expand('*.hs')) == 1 then
            g_set('haskell_mode', 1)
        end
    end
end

-- 检查并设置 rust_mode
if vim.g.rust_mode == nil then
    g_set('rust_mode', 0)

    if vim.g.quick_mode == 0 then
        if vim.fn.filereadable('Cargo.toml') == 1 or vim.fn.filereadable(vim.fn.expand('*.rs')) == 1 then
            g_set('rust_mode', 1)
        end
    end
end

-- 检查并设置 enable_lsp
if vim.g.enable_lsp == nil then
    g_set('enable_lsp', vim.g.haskell_mode == 1 or vim.g.rust_mode == 1)
end

---------------- options, key mappings -------------

vim.g.mapleader = " " -- make sure to set `mapleader` before lazy

vim.cmd.filetype("on")
vim.cmd.filetype("plugin on")

vim.opt.encoding = "utf-8"
vim.o.hidden = true
vim.o.expandtab = true
vim.o.showcmd = true
vim.o.mouse = 'a'
vim.o.shortmess = vim.o.shortmess .. 'c'
vim.o.sessionoptions = vim.o.sessionoptions .. ',globals'
vim.o.wop = 'pum'

for i = 1, 9 do
    vim.api.nvim_set_keymap('n', ','..i, ':tabn '..i..'<CR>', {noremap = true, silent = true})
end

vim.api.nvim_set_keymap('v', '<F2>', '"0p', {noremap = true})
vim.api.nvim_set_keymap('n', '<F2>', 'viw"0p', {noremap = true})

-- see: http://vim.wikia.com/wiki/Selecting_your_pasted_text
vim.api.nvim_set_keymap('n', '<leader>v', [[`]] .. vim.fn.strpart(vim.fn.getregtype(), 0, 1) .. [[`]], {noremap = true, expr = true})


function my_set_local_tab_stop(n)
  vim.opt_local.tabstop = n
  vim.opt_local.softtabstop = n
  vim.opt_local.shiftwidth = n
end

for _, n in ipairs({ 2, 4, 8 }) do
    vim.keymap.set('n', '<leader>t'..n, function () my_set_local_tab_stop(n) end, {noremap = true, })
  end


-- 定义 MySetWigForHaskell 函数
vim.api.nvim_exec([[
  function MySetWigForHaskell()
    set wig+=*.o,*.hi,*.dyn_hi,*.dyn_o,*/dist/*,cabal.sandbox.config,*.keter
  endfunction
]], false)


if vim.g.haskell_mode == 1 then
    vim.api.nvim_exec('call MySetWigForHaskell()', false)
end

-- Toggle cursorline and cursorcolumn
vim.api.nvim_set_keymap('n', '<leader>cc', ':set cuc! cul!<CR>', {noremap = true, silent = true})

-- Toggle number display
vim.api.nvim_set_keymap('n', '<leader>n', ':set nu! rnu!<CR>', {noremap = true, silent = true})

-- Toggle paste mode
vim.api.nvim_set_keymap('n', '<leader>p', ':set paste!<CR>', {noremap = true})


---------------- lazy.nvim plugins -------------

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end


vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    "tpope/vim-repeat",
    "vim-scripts/visualrepeat",
    "machakann/vim-sandwich",
    "jeffkreeftmeijer/vim-numbertoggle",
    "unblevable/quick-scope",
    "tpope/vim-abolish",
    "yuttie/comfortable-motion.vim",
    "equalsraf/neovim-gui-shim",
    "machakann/vim-highlightedyank",

    { "t9md/vim-choosewin",
      config = function ()
        vim.api.nvim_set_keymap('n',  '-',  '<Plug>(choosewin)', {noremap = true, silent = true})
        vim.g.choosewin_overlay_enable = 1
      end
    },

    "szw/vim-maximizer",

    "azabiong/vim-highlighter",

    { "phaazon/hop.nvim", branch = "v2"
      , config = function()
          local hop = require('hop')
          hop.setup()
          --[[
          local directions = require('hop.hint').HintDirection
          vim.keymap.set('', 'f', function()
            hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true })
          end, {remap=true})
          vim.keymap.set('', 'F', function()
            hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true })
          end, {remap=true})
          vim.keymap.set('', 't', function()
            hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true, hint_offset = -1 })
          end, {remap=true})
          vim.keymap.set('', 'T', function()
            hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 })
          end, {remap=true})
          --]]

          vim.keymap.set('', '<leader>hc', function()
            hop.hint_char1()
          end, {remap=true})

          vim.keymap.set('', '<leader>hw', function()
            hop.hint_words()
          end, {remap=true})

        end
    },

    -- git --
    { 'tpope/vim-fugitive',
      config = function ()
        vim.api.nvim_set_keymap('n', '<leader>gs', ':Gstatus<CR>', {noremap = true, })
        vim.api.nvim_set_keymap('n', '<leader>gd', ':Gdiff<CR>', {noremap = true, })
        vim.api.nvim_set_keymap('n', '<leader>gc', ':Gcommit<CR>', {noremap = true, })
        vim.api.nvim_set_keymap('n', '<leader>gl', ':Glog<CR>', {noremap = true, })
        vim.api.nvim_set_keymap('n', '<leader>gp', ':Git push<CR>', {noremap = true, })
      end,
    },
    'junegunn/gv.vim',
    'mhinz/vim-signify',

    -- general programming ---

    { "neomake/neomake",
      config = function()
      end
    },

    { "sbdchd/neoformat", lazy = true },

    { "nvim-treesitter/nvim-treesitter",
      build = ':TSUpdate', -- We recommend updating the parsers on update
      config = function()
        require'nvim-treesitter.configs'.setup {
          highlight = {
            enable = true,
          },

          textobjects = {
            select = {
              enable = true,

              -- Automatically jump forward to textobj, similar to targets.vim
              lookahead = true,

              keymaps = {
                -- You can use the capture groups defined in textobjects.scm
                ["af"] = "@function.outer",
                ["if"] = "@function.inner",
                ["ac"] = "@class.outer",
                -- You can optionally set descriptions to the mappings (used in the desc parameter of
                -- nvim_buf_set_keymap) which plugins like which-key display
                ["ic"] = { query = "@class.inner", desc = "Select inner part of a class region" },
                -- You can also use captures from other query groups like `locals.scm`
                ["as"] = { query = "@scope", query_group = "locals", desc = "Select language scope" },
              },
              -- You can choose the select mode (default is charwise 'v')
              --
              -- Can also be a function which gets passed a table with the keys
              -- * query_string: eg '@function.inner'
              -- * method: eg 'v' or 'o'
              -- and should return the mode ('v', 'V', or '<c-v>') or a table
              -- mapping query_strings to modes.
              selection_modes = {
                ['@parameter.outer'] = 'v', -- charwise
                ['@function.outer'] = 'V', -- linewise
                ['@class.outer'] = '<c-v>', -- blockwise
              },
              -- If you set this to `true` (default is `false`) then any textobject is
              -- extended to include preceding or succeeding whitespace. Succeeding
              -- whitespace has priority in order to act similarly to eg the built-in
              -- `ap`.
              --
              -- Can also be a function which gets passed a table with the keys
              -- * query_string: eg '@function.inner'
              -- * selection_mode: eg 'v'
              -- and should return true of false
              include_surrounding_whitespace = true,
            },
          },
        }
     end
    },

    { 'neovim/nvim-lspconfig',
      config = function()
        local lspconfig = require('lspconfig')
        lspconfig.pyright.setup {}
        lspconfig.tsserver.setup {}
      end
    },

    {
      "https://git.sr.ht/~whynothugo/lsp_lines.nvim",
      config = function()
        local lsp_lines = require("lsp_lines")
        lsp_lines.setup()

        -- either use lsp_lines or nvim builtin virtual_text
        local function my_toggle()
          local enabled = lsp_lines.toggle()
          vim.diagnostic.config({
            virtual_text = not enabled,
          })
        end

        -- initially disabled. because usually I use '<leader>dd' to open telescope to show diagnostics
        my_toggle()

        vim.keymap.set("n", "<leader>ll", my_toggle, { desc = "Toggle lsp_lines" })
      end,
    },

    { "nvim-treesitter/nvim-treesitter-textobjects",
      dependencies =  "nvim-treesitter/nvim-treesitter",
    },

    "Exafunction/codeium.vim",

    { 'neoclide/coc.nvim', branch = 'release' },

    -- web --
 
    -- others --

    { "vim-airline/vim-airline",
      config = function()
        vim.g.airline_powerline_fonts = 1
      end
    },
 
    "vim-airline/vim-airline-themes",

    'nathanaelkane/vim-indent-guides',

    { "zefei/vim-wintabs",
      config = function()
          for i = 1, 9 do
              vim.api.nvim_set_keymap("n", "<leader>" .. i, ":WintabsGo " .. i .. "<CR>", { noremap = true, silent = true })
          end

          vim.api.nvim_set_keymap("n", "<leader>0", ":WintabsGo 10<CR>", { noremap = true, })
          vim.api.nvim_set_keymap("n", "<leader>$", ":WintabsLast<CR>", { noremap = true, })
          vim.api.nvim_set_keymap("n", "gb", "<Plug>(wintabs_next)", { noremap = true, })
          vim.api.nvim_set_keymap("n", "gB", "<Plug>(wintabs_previous)", { noremap = true, })
          vim.api.nvim_set_keymap("n", "<C-T>c", "<Plug>(wintabs_close)", { noremap = true, })
          vim.api.nvim_set_keymap("n", "<C-T>o", "<Plug>(wintabs_only)", { noremap = true, })
          vim.api.nvim_set_keymap("n", "<C-W>c", "<Plug>(wintabs_close_window)", { noremap = true, })
          vim.api.nvim_set_keymap("n", "<C-W>o", "<Plug>(wintabs_only_window)", { noremap = true, })
          vim.cmd('command! Tabc WintabsCloseVimtab')
          vim.cmd('command! Tabo WintabsOnlyVimtab')
          vim.g.wintabs_autoclose_vimtab = 1
          vim.g.wintabs_display = 'tabline'
          vim.g.wintabs_ui_sep_spaceline = 'GT，'
          vim.g.wintabs_ui_buffer_name_format = '%o%t'
      end
    },

    "zefei/vim-wintabs-powerline",

    { "junegunn/vim-peekaboo",
      config = function()
        vim.g.peekaboo_delay = 750
      end
    },

    "junegunn/vim-slash",
    "junegunn/limelight.vim",
    "takac/vim-hardtime",
    "yssl/QFEnter",

    { "echasnovski/mini.nvim",
      config = function()
        vim.g.minisurround_disable   = true
        vim.g.minicompletion_disable = true
        vim.g.ministarter_disable    = true
      end
    },

    "Shougo/vimproc.vim",

    { "milkypostman/vim-togglelist",
      config = function()
        vim.g.toggle_list_no_mappings = 1
        vim.api.nvim_set_keymap('n', '<leader>lo', ':call ToggleLocationList()<CR>', {noremap = true, silent = true, script = true})
        vim.api.nvim_set_keymap('n', '<leader>q', ':call ToggleQuickfixList()<CR>', {noremap = true, silent = true, script = true})
      end,
    },

    "nvim-lua/plenary.nvim",

    { "nvim-telescope/telescope.nvim",
      config = function ()
        local builtin = require('telescope.builtin')
        vim.keymap.set("n", "<leader>f", builtin.find_files, {noremap = true})
        vim.keymap.set("n", "<leader>L", builtin.live_grep, {noremap = true})
        vim.keymap.set("n", "<leader>B", builtin.buffers, {noremap = true})
        vim.keymap.set("n", "<leader>H", builtin.help_tags, {noremap = true})
        vim.keymap.set("n", "<leader>T", builtin.tags, {noremap = true})
        vim.keymap.set("n", "<leader>dd", builtin.diagnostics, {noremap = true})
      end,
    },

    { "nvim-telescope/telescope-fzf-native.nvim",
      build = 'make',
    },

    { 'junegunn/vim-easy-align',
      config = function()
        vim.keymap.set('v', '<Enter>', '<Plug>(EasyAlign)', {noremap = true})
        vim.keymap.set('n', 'ga', '<Plug>(EasyAlign)', {noremap = true})
      end
    },

    { 'kshenoy/vim-signature' },

    --- haskell ----
    -- 'neovimhaskell/haskell-vim',

    { "pbrisbin/vim-syntax-shakespeare",
      ft = { 'hamlet', 'cassius', 'julius' }
    },

    { 'mrcjkb/haskell-tools.nvim',
      dependencies = { 'nvim-lua/plenary.nvim', 'nvim-telescope/telescope.nvim' },
      branch = '1.x.x',
      ft = { 'haskell', 'lhaskell', 'cabal', 'cabalproject' },
      config = function()
        local ht = require('haskell-tools')

        ht.start_or_attach {
          hls = { -- LSP client options
            default_settings = {
              haskell = { -- haskell-language-server options
                formattingProvider = 'fourmolu',
                -- Setting this to true could have a performance impact on large mono repos.
                checkProject = false,
                -- ...
              }
            }
          }
        }
      end
    },

    --- colorschemes ----
    { "rebelot/kanagawa.nvim", priority = 100 },
})

vim.cmd("colorscheme kanagawa")
vim.o.bg = 'dark'


vim.keymap.set('n', '<leader>do', vim.diagnostic.open_float, { noremap = true, })
vim.keymap.set('n', '<leader>d[', vim.diagnostic.goto_prev, { noremap = true, })
vim.keymap.set('n', '<leader>d]', vim.diagnostic.goto_next, { noremap = true, })
vim.keymap.set('n', '<leader>dpe', function() vim.diagnostic.goto_prev({ severity = { min = vim.diagnostic.severity.WARN } }) end, { noremap = true, })
vim.keymap.set('n', '<leader>dne', function () vim.diagnostic.goto_next({ severity = { min = vim.diagnostic.severity.WARN } }) end, { noremap = true, })
-- If you don't want to use the telescope plug-in but still want to see all the errors/warnings, comment out the telescope line and uncomment this:
-- vim.api.nvim_set_keymap('n', '<leader>dd', '<cmd>lua vim.diagnostic.setloclist()<CR>', { noremap = true, silent = true })

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'haskell', 'html' },
  callback = function ()
    vim.opt_local.expandtab = true
    my_set_local_tab_stop(2)
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  pattern = { '*.hamlet' },
  callback = function ()
    vim.opt_local.expandtab = true
    my_set_local_tab_stop(2)
  end,
})

vim.api.nvim_create_autocmd('BufFilePost', {
  pattern = { '*.hamlet' },
  callback = function ()
    vim.opt_local.expandtab = true
    my_set_local_tab_stop(2)
  end,
})
