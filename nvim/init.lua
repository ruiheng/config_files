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
vim.o.title = true
vim.o.titlestring = '%f %{fnamemodify(getcwd(), ":~")} -- NVIM'
vim.o.mouse = 'a'
vim.o.shortmess = vim.o.shortmess .. 'c'
vim.o.sessionoptions = vim.o.sessionoptions .. ',globals'
vim.o.wop = 'pum'

for i = 1, 9 do
    vim.api.nvim_set_keymap('n', ','..i, ':tabn '..i..'<CR>', {noremap = true, silent = true})
end

-- about selecting and pasting text
vim.api.nvim_set_keymap('v', '<F2>', '"0p', {noremap = true})
vim.api.nvim_set_keymap('n', '<F2>', 'viw"0p', {noremap = true})

-- see: http://vim.wikia.com/wiki/Selecting_your_pasted_text
vim.cmd("nnoremap <expr> <leader>vp '`[' . strpart(getregtype(), 0, 1) . '`]'")


-- invoke 'stack build' command, set diagnostics and quickfix
vim.keymap.set('n', '<leader>bs',
    function()
      require('ruiheng.haskell.stack').start_build_job()
      require('ruiheng.quickfix').open_quickfix_win_but_not_focus()
    end ,
    {noremap = true, silent = true}
  )


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
-- vim.api.nvim_set_keymap('n', '<leader>pa', ':set paste!<CR>', {noremap = true})


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
    -- general behavior ---
    "tpope/vim-repeat",
    "vim-scripts/visualrepeat",
    "machakann/vim-sandwich",
    "jeffkreeftmeijer/vim-numbertoggle",
    "unblevable/quick-scope",
    "tpope/vim-abolish",
    "equalsraf/neovim-gui-shim",
    "machakann/vim-highlightedyank",

    -- toggl, display and navigate marks
    { 'kshenoy/vim-signature' },

    { "t9md/vim-choosewin",
      config = function ()
        vim.api.nvim_set_keymap('n',  '-',  '<Plug>(choosewin)', {noremap = true, silent = true})
        vim.g.choosewin_overlay_enable = 1
      end
    },

    "szw/vim-maximizer",

    "azabiong/vim-highlighter",

    { "akinsho/toggleterm.nvim",
      version = "*",
      opts = {
        open_mapping = [[<F12>]],
        direction = 'float',
      },
    },

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

    -- overall nvim behavior ---

    { 'akinsho/bufferline.nvim',
      dependencies =
        { 'nvim-tree/nvim-web-devicons', -- optional
        },
      version = '*',

      enabled = true,

      config = require('ruiheng.plugin_setup.bufferline').config,
    },

    { 'tiagovla/scope.nvim',
      enabled = true,
      config = require('ruiheng.plugin_setup.scope').config,
    },

    { 'backdround/tabscope.nvim',
      -- with tabscope, session could not be restored with all tabs and their buffers
      -- only the 'active' buffer of each vim tab can be restored.
      enabled = false,
    },


    -- general programming ---

    { "neomake/neomake",
      config = function()
      end
    },

    { "sbdchd/neoformat" },

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

        -- use either this or haskell-tools
        -- lspconfig.hls.setup {}
      end
    },

    { "https://git.sr.ht/~whynothugo/lsp_lines.nvim",
      config = function()
        local lsp_lines = require("lsp_lines")
        lsp_lines.setup()

        -- either use lsp_lines or nvim builtin virtual_text
        local function my_toggle()
          local old_value = vim.diagnostic.config().virtual_lines
          local new_value
          if old_value then
            new_value = false
          else
            new_value = { only_current_line = true }
          end

          vim.diagnostic.config({
            virtual_text = not new_value,
            virtual_lines = new_value,
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

    { 'machakann/vim-textobj-delimited',
      dependencies = 'kana/vim-textobj-user',
    },

    "Exafunction/codeium.vim",

    { 'neoclide/coc.nvim', branch = 'release' },

    {'kevinhwang91/nvim-ufo', dependencies = 'kevinhwang91/promise-async',
      config = function()
        vim.o.fillchars = [[eob: ,fold: ,foldopen:,foldsep: ,foldclose:]]
        vim.o.foldcolumn = '1' -- '0' is not bad
        vim.o.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
        vim.o.foldlevelstart = 99
        vim.o.foldenable = true

        -- Using ufo provider need remap `zR` and `zM`. If Neovim is 0.6.1, remap yourself
        vim.keymap.set('n', 'zR', require('ufo').openAllFolds)
        vim.keymap.set('n', 'zM', require('ufo').closeAllFolds)

        -- Option 3: treesitter as a main provider instead
        -- Only depend on `nvim-treesitter/queries/filetype/folds.scm`,
        -- performance and stability are better than `foldmethod=nvim_treesitter#foldexpr()`
        require('ufo').setup({
            provider_selector = function(bufnr, filetype, buftype)
                return {'treesitter', 'indent'}
            end
        })
      end
    },

    { 'junegunn/vim-easy-align',
      config = function()
        vim.keymap.set('v', '<Enter>', '<Plug>(EasyAlign)', {noremap = true})
        vim.keymap.set('n', 'ga', '<Plug>(EasyAlign)', {noremap = true})
      end
    },

    { 'folke/trouble.nvim',
      dependencies = 'nvim-tree/nvim-web-devicons',
      config = function(_, opts)
        local trouble = require('trouble')
        trouble.setup(opts)
        vim.keymap.set("n", "<leader>xx", function() trouble.open() end)
        vim.keymap.set("n", "<leader>xw", function() trouble.open("workspace_diagnostics") end)
        vim.keymap.set("n", "<leader>xd", function() trouble.open("document_diagnostics") end)
        -- vim.keymap.set("n", "<leader>xl", function() trouble.open("quickfix") end)
        -- vim.keymap.set("n", "<leader>xq", function() trouble.open("loclist") end)
        -- vim.keymap.set("n", "gR", function() trouble.open("lsp_references") end)
      end
    },

    { 'jose-elias-alvarez/null-ls.nvim',
      dependencies = "nvim-lua/plenary.nvim",
      enabled = true,
      config = require('ruiheng.plugin_setup.null-ls').config,
    },

    -- web --

    -- others --

    { "vim-airline/vim-airline",
      config = function()
        vim.g.airline_powerline_fonts = 1
      end
    },

    "vim-airline/vim-airline-themes",

    'nathanaelkane/vim-indent-guides',

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

        require('mini.sessions').setup {
          hooks = {
            pre = {
              write = function ()
                -- for barbar.nvim
                vim.api.nvim_exec_autocmds('User', { pattern = 'SessionSavePre' })

                local ok, scope = pcall(require, 'scope')
                if ok then
                  vim.cmd('ScopeSaveState')
                end
              end,
            },
            post = {
              read = function ()
                    local ok, scope = pcall(require, 'scope')
                    if ok then
                      vim.cmd('ScopeLoadState')
                    end
                end,
            },
          }
        }

      end
    },

    { "milkypostman/vim-togglelist",
      config = function()
        vim.g.toggle_list_no_mappings = 1
        vim.api.nvim_set_keymap('n', '<leader>lo', ':call ToggleLocationList()<CR>', {noremap = true, silent = true, script = true})
        vim.api.nvim_set_keymap('n', '<leader>q', ':call ToggleQuickfixList()<CR>', {noremap = true, silent = true, script = true})
      end,
    },


    ---- telescope and friends ----

    { "nvim-telescope/telescope.nvim",
      dependencies = "nvim-lua/plenary.nvim",
      config = function ()
        local builtin = require('telescope.builtin')
        local map_opts = {noremap = true}
        vim.keymap.set("n", "<leader>f", builtin.find_files, map_opts)
        vim.keymap.set("n", "<leader>of", builtin.oldfiles, map_opts)
        vim.keymap.set("n", "<leader>L", builtin.live_grep, map_opts)
        vim.keymap.set("n", "<leader>B", builtin.buffers, map_opts)
        vim.keymap.set("n", "<leader>H", builtin.help_tags, map_opts)
        vim.keymap.set("n", "<leader>T", function () return builtin.tags {fname_width = 70} end, map_opts)
        vim.keymap.set("n", "<leader>bt", builtin.current_buffer_tags, map_opts)
        vim.keymap.set("n", "<leader>bf", builtin.current_buffer_fuzzy_find, map_opts)
        vim.keymap.set("n", "<leader>td", builtin.diagnostics, map_opts)
        vim.keymap.set("n", "<leader>tc", builtin.commands, map_opts)
        vim.keymap.set("n", "<leader>tm", builtin.marks, map_opts)

        require('telescope').setup{
          defaults = {
            layout_strategy = 'vertical',
            layout_config = { height = 0.95 },
          },
        }
      end,
    },

    { "nvim-telescope/telescope-fzf-native.nvim",
      build = 'make',
      dependencies = { 'nvim-telescope/telescope.nvim' },
      config = function()
        require('telescope').load_extension('fzf')
      end
    },


    --- haskell ----

    -- 'neovimhaskell/haskell-vim',

    { 'alx741/yesod.vim',
      config = function()
        vim.g.yesod_disable_maps = 1
      end
    },

    { "pbrisbin/vim-syntax-shakespeare",
      ft = { 'hamlet', 'cassius', 'julius', 'haskell', }
    },

    { 'mrcjkb/haskell-tools.nvim',
      dependencies = { 'nvim-lua/plenary.nvim', 'nvim-telescope/telescope.nvim' },
      -- CAUTION for big codebase project: poor performance, huge memory footprint
      -- Also, HlsStop won't make hls process cleanly exit (it becomes a zombie)
      --       HlsRestart does not work either.
      enabled = false,
      branch = '1.x.x',
      ft = { 'haskell', 'lhaskell', 'cabal', 'cabalproject' },
      config = function()
        local ht = require('haskell-tools')
        local def_opts = { noremap = true, silent = true, }

        ht.start_or_attach {
          tools = {
            log = {
              level = vim.log.levels.DEBUG,
            },
          },

          hls = { -- LSP client options
            debug = true,
            on_attach = function(client, bufnr)
              -- opt-out of semantic highlighting
              -- not sure if this is needed or correct
              -- client.server_capabilities.semanticTokensProvider = nil

              local map_opts = vim.tbl_extend('keep', def_opts, { buffer = bufnr, })
              vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, map_opts)
              -- haskell-language-server relies heavily on codeLenses,
              -- so auto-refresh (see advanced configuration) is enabled by default
              -- vim.keymap.set('n', '<space>ca', vim.lsp.codelens.run, map_opts)
              -- vim.keymap.set('n', '<space>hs', ht.hoogle.hoogle_signature, map_opts)
              -- vim.keymap.set('n', '<space>ea', ht.lsp.buf_eval_all, map_opts)
            end,

            default_settings = {
              haskell = { -- haskell-language-server options
                formattingProvider = 'fourmolu',
                -- Setting this to true could have a performance impact on large mono repos.
                checkProject = false,
                -- ...
              },
              plugin = {
                hlint = {
                  config = {
                    flags = { "-XCPP " },
                  },
                },
              },
            },
          }
        }
      end
    },

    -- syntax highlighting --
    'lifepillar/pgsql.vim',

    --- colorschemes ----
    { "rebelot/kanagawa.nvim", priority = 100 },
    { "sainnhe/everforest", priority = 100 },
})

vim.o.bg = 'dark'
-- vim.g.everforest_background = 'soft'
-- vim.g.everforest_better_performance = 1
-- vim.cmd("colorscheme everforest")
vim.cmd("colorscheme kanagawa")


vim.keymap.set('n', '<leader>do', vim.diagnostic.open_float, { noremap = true, })
vim.keymap.set('n', '<leader>d[', vim.diagnostic.goto_prev, { noremap = true, })
vim.keymap.set('n', '<leader>d]', vim.diagnostic.goto_next, { noremap = true, })
vim.keymap.set('n', '<leader>dpe', function() vim.diagnostic.goto_prev({ severity = { min = vim.diagnostic.severity.WARN } }) end, { noremap = true, })
vim.keymap.set('n', '<leader>dne', function () vim.diagnostic.goto_next({ severity = { min = vim.diagnostic.severity.WARN } }) end, { noremap = true, })
-- If you don't want to use the telescope plug-in but still want to see all the errors/warnings, comment out the telescope line and uncomment this:
-- vim.api.nvim_set_keymap('n', '<leader>dd', '<cmd>lua vim.diagnostic.setloclist()<CR>', { noremap = true, silent = true })

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'haskell', 'html', 'lua', 'vim', },
  callback = function ()
    vim.opt_local.expandtab = true
    vim.opt_local.cuc = true
    vim.opt_local.cul = true
    vim.opt_local.number = true
    vim.opt_local.relativenumber = true

    -- for unknown reason, 'syntax' optoin is empty when opening haskell files ('filetype' has been detected correctly)
    vim.opt_local.syntax = 'ON'

    my_set_local_tab_stop(2)
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'python' },
  callback = function ()
    vim.opt_local.expandtab = true
    my_set_local_tab_stop(4)
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


vim.api.nvim_create_user_command("DiagnosticReset", function()
    vim.diagnostic.reset()
end, { desc = [[Reset diagnostics globally.]] })
