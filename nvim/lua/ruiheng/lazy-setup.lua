-- If opening from inside neovim termnal, do not load all the other plugins
if os.getenv('NVIM') then
  require("lazy").setup({
    { 'willothy/flatten.nvim',
      -- enure that it run first to minimize delay when open file from terminal
      lazy = false, priority = 1001,
      config = true, -- or set opts
    },
  })

  return
end

require("lazy").setup({
    -- general behavior ---
    "tpope/vim-repeat",
    "vim-scripts/visualrepeat",
    "jeffkreeftmeijer/vim-numbertoggle",
    "unblevable/quick-scope",
    "tpope/vim-abolish",
    "equalsraf/neovim-gui-shim",
    "machakann/vim-highlightedyank",

    -- use sandwich or surround
    -- "machakann/vim-sandwich",
    {
        "kylechui/nvim-surround",
        version = "*", -- Use for stability; omit to use `main` branch for the latest features
        event = "VeryLazy",
        config = function()
            require("nvim-surround").setup({
                -- Configuration here, or leave empty to use defaults
            })
        end
    },

    -- toggle, display and navigate marks
    { 'kshenoy/vim-signature' },

    { "t9md/vim-choosewin",
      enabled = false, -- sems to break undo history
      config = function ()
        vim.api.nvim_set_keymap('n',  '-',  '<Plug>(choosewin)', {noremap = true, silent = true})
        vim.g.choosewin_overlay_enable = 1
        vim.g.choosewin_statusline_replace = 0
        vim.g.choosewin_tabline_replace = 0 -- otherwise, bufferline.nvim may not work properly
      end
    },

    "szw/vim-maximizer",

    "azabiong/vim-highlighter",

    -- motion --
    { "phaazon/hop.nvim", branch = "v2",
      enabled = false, -- use leap
      config = function()
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

    { 'ggandor/leap.nvim',
      config = function ()
        require('leap').add_default_mappings()
      end
    },

    -- terminal --

    { 'willothy/flatten.nvim',
      -- enure that it run first to minimize delay when open file from terminal
      lazy = false, priority = 1001,
      config = true, -- or set opts
    },

    { "akinsho/toggleterm.nvim",
      version = "*",
      opts = {
        open_mapping = [[<F12>]],
        direction = 'float',
      },
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
    {
        "ThePrimeagen/harpoon",
        branch = "harpoon2",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = require('ruiheng.plugin_setup.harpoon').config,
    },

    {
      "willothy/nvim-cokeline",
      dependencies = {
        "nvim-lua/plenary.nvim",        -- Required for v0.4.0+
        "nvim-tree/nvim-web-devicons", -- If you want devicons
        "stevearc/resession.nvim"       -- Optional, for persistent history
      },
      enabled = false, -- alternative to bufferline.nvim
      -- config = true
      config = require('ruiheng.plugin_setup.cokeline').config,
    },

    { 'akinsho/bufferline.nvim',
      dependencies =
        { 'nvim-tree/nvim-web-devicons', -- optional
        },
      branch = "main",
      commit = "73540cb95f8d95aa1af3ed57713c6720c78af915",

      enabled = true, -- some issues in current version, use nvim-cokeline for now

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

    {
      "folke/todo-comments.nvim",
      dependencies = { "nvim-lua/plenary.nvim" },
      opts = {
      },
    },

    { "lukas-reineke/indent-blankline.nvim",
      main = 'ibl',
      config = function()
        vim.opt.termguicolors = true
        vim.cmd [[highlight IndentBlanklineIndent1 guibg=#1f1f1f gui=nocombine]]
        vim.cmd [[highlight IndentBlanklineIndent2 guibg=#1a1a1a gui=nocombine]]

        require("ibl").setup {
           debounce = 100,
           indent = { char = "|" },
           whitespace = { highlight = { "Whitespace", "NonText" } },
           scope = { exclude = { language = { "lua" } } },
        }
      end,
    },

    'mrcjkb/haskell-snippets.nvim',

    {
      "L3MON4D3/LuaSnip",
      -- follow latest release.
      version = "2.*", -- Replace <CurrentMajor> by the latest released major (first number of latest release)
      -- install jsregexp (optional!).
      build = "make install_jsregexp",
      config = function ()
        local ls = require("luasnip")
        ls.setup {}
        vim.keymap.set({"i"}, "<C-K>", function() ls.expand() end, {silent = true})
        vim.keymap.set({"i", "s"}, "<C-L>", function() ls.jump( 1) end, {silent = true})
        vim.keymap.set({"i", "s"}, "<C-J>", function() ls.jump(-1) end, {silent = true})

        vim.keymap.set({"i", "s"}, "<C-E>", function()
          if ls.choice_active() then
            ls.change_choice(1)
          end
        end, {silent = true})

        require('luasnip.loaders.from_snipmate').lazy_load()

        local ok, haskell_snippets = pcall(require, 'haskell-snippets')
        if ok then
          haskell_snippets = haskell_snippets.all
          ls.add_snippets('haskell', haskell_snippets, { key = 'haskell' })
        end

      end
    },

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

          indent = {
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

        -- vim.o.foldmethod = 'expr'
        -- vim.o.foldexpr = 'nvim_treesitter#foldexpr()'
        -- vim.o.foldenable = false
     end
    },

    { 'nvim-treesitter/nvim-treesitter-context',
      config = function()
        vim.keymap.set("n", "[c", function()
          require("treesitter-context").go_to_context()
        end, { silent = true })

        vim.cmd('hi TreesitterContextBottom gui=underline guisp=Grey')
      end,
    },

    { 'neovim/nvim-lspconfig',
      enabled = true,
      config = require('ruiheng.plugin_setup.lspconfig').config,
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

    -- { "Exafunction/codeium.vim",
    --   config = function()
    --     -- vim.g.codeium_no_map_tab = true
    --     -- vim.keymap.set('i', '<C-g>', function () return vim.fn['codeium#Accept']() end, { expr = true })
    --   end,
    -- },

    {
      "supermaven-inc/supermaven-nvim",
      config = function()
        require("supermaven-nvim").setup({})
      end,
    },

    -- use lspconfig instead: works better with telescope
    -- { 'neoclide/coc.nvim', branch = 'release' },

    -- 'anuvyklack/pretty-fold.nvim',  -- use this or nvim-ufo

    {'kevinhwang91/nvim-ufo', dependencies = 'kevinhwang91/promise-async',
      enabled = true, -- or use pretty-fold.nvim instead
      config = require('ruiheng.plugin_setup.nvim-ufo').config,
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
        vim.keymap.set("n", "<leader>xx", function() trouble.toggle() end)
        vim.keymap.set("n", "<leader>xw", function() trouble.toggle("workspace_diagnostics") end)
        vim.keymap.set("n", "<leader>xd", function() trouble.toggle("document_diagnostics") end)
        vim.keymap.set("n", "<leader>xq", function() trouble.toggle("quickfix") end)
        vim.keymap.set("n", "<leader>xl", function() trouble.toggle("loclist") end)
        -- vim.keymap.set("n", "gR", function() trouble.open("lsp_references") end)
      end
    },

    { 'jose-elias-alvarez/null-ls.nvim',
      dependencies = "nvim-lua/plenary.nvim",
      enabled = true,
      config = require('ruiheng.plugin_setup.null-ls').config,
    },

    -- web --

    'posva/vim-vue',

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
      init = function ()
        vim.g.toggle_list_no_mappings = 1
      end,
      config = function()
        vim.api.nvim_set_keymap('n', '<leader>lo', ':call ToggleLocationList()<CR>', {noremap = true, silent = true, script = true})
        vim.api.nvim_set_keymap('n', '<leader>q', ':call ToggleQuickfixList()<CR>', {noremap = true, silent = true, script = true})
      end,
    },

    ---- telescope and friends ----

    { "nvim-telescope/telescope.nvim",
      dependencies = "nvim-lua/plenary.nvim",
      config = require('ruiheng.plugin_setup.telescope').config,
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

    -- 'itchyny/vim-haskell-indent',

    { 'sdiehl/vim-ormolu',
      enabled = false, -- or use 'haskell-tools'
      ft = { 'haskell' },
      config = function()
        vim.g.ormolu_command = 'fourmolu'
        vim.g.ormolu_options = { '-o -XTypeApplications', '-q', '--no-cabal', }
        vim.g.ormolu_disabled = 1
      end,
    },

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
      enabled = function ()
        -- only enable when neccessary
        return os.getenv('HASKELL_TOOLS') == '1'
      end,

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
    { "ellisonleao/gruvbox.nvim", priority = 1000 },
})

