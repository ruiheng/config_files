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
    {
      "folke/snacks.nvim",
      priority = 1000,
      lazy = false,
      ---@type snacks.Config
      opts = {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
        bigfile = { enabled = true },
        -- dashboard = { enabled = true },
        explorer = { enabled = true },
        indent = { enabled = true },
        input = { enabled = true },
        picker = { enabled = true },
        notifier = { enabled = true },
        quickfile = { enabled = true },
        scope = { enabled = true },
        -- scroll = { enabled = true },
        statuscolumn = { enabled = true },
        -- words = { enabled = true },
        -- zen = { enabled = true },
      },
    },

    {
      "folke/which-key.nvim",
      event = "VeryLazy",
      opts = {
        delay = 500,
        filter = function(mapping)
          -- 示例：如果描述包含 "WK-IGNORE"，则不显示
          if mapping.desc and mapping.desc:find("[WK-IGNORE]") then
            return false
          end
          -- 默认显示
          return true
        end,
        plugins = {
          presets = {
            operators = false,    -- 隐藏运算符帮助 (如 d, y, c)
            -- motions = false,      -- 隐藏移动帮助 (如 h, j, k, l)
            text_objects = false, -- 隐藏文本对象帮助 (如 a, i)
            -- windows = false,      -- 隐藏窗口导航帮助 (<c-w>)
            nav = false,          -- 隐藏杂项导航 (如 G, gg)
            -- z = false,            -- 隐藏 z 键前缀的绑定 (折叠等)
            -- g = false,            -- 隐藏 g 键前缀的绑定
          },
        },
      },
      keys = {
        {
          "<leader>?",
          function()
            require("which-key").show({ global = false })
          end,
          desc = "Buffer Local Keymaps (which-key)",
        },
      },
    },

    "tpope/vim-repeat",
    "vim-scripts/visualrepeat",
    "jeffkreeftmeijer/vim-numbertoggle",
    -- "unblevable/quick-scope", -- use snacks.nvim
    "tpope/vim-abolish",
    "equalsraf/neovim-gui-shim",

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

    {
      'MagicDuck/grug-far.nvim',
      -- Note (lazy loading): grug-far.lua defers all it's requires so it's lazy by default
      -- additional lazy config to defer loading is not really needed...
      config = function()
        -- optional setup call to override plugin options
        -- alternatively you can set options with vim.g.grug_far = { ... }
        require('grug-far').setup({
          -- options, see Configuration section below
          -- there are no required options atm
        });
      end
    },

    { 'kevinhwang91/nvim-bqf' },

    -- toggle, display and navigate marks
    { 'kshenoy/vim-signature' },

    {
      'saghen/blink.cmp',
      enabled = true,
      -- optional: provides snippets for the snippet source
      dependencies = {
        'rafamadriz/friendly-snippets',
        -- 'Exafunction/windsurf.nvim',
      },

      -- use a release tag to download pre-built binaries
      version = '1.*',
      -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
      -- build = 'cargo build --release',
      -- If you use nix, you can build from source using latest nightly rust with:
      -- build = 'nix run .#build-plugin',

      ---@module 'blink.cmp'
      ---@type blink.cmp.Config
      opts = {
        -- 'default' (recommended) for mappings similar to built-in completions (C-y to accept)
        -- 'super-tab' for mappings similar to vscode (tab to accept)
        -- 'enter' for enter to accept
        -- 'none' for no mappings
        --
        -- All presets have the following mappings:
        -- C-space: Open menu or open docs if already open
        -- C-n/C-p or Up/Down: Select next/previous item
        -- C-e: Hide menu
        -- C-k: Toggle signature help (if signature.enabled = true)
        --
        -- See :h blink-cmp-config-keymap for defining your own keymap
        keymap = {
          preset = 'default',
          ['<C-space>'] = {},
          ['<A-space>'] = { function(cmp) cmp.show({ providers = { 'snippets' } }) end },
          },

        signature = { enabled = true },

        appearance = {
          -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
          -- Adjusts spacing to ensure icons are aligned
          nerd_font_variant = 'mono'
        },

        -- (Default) Only show the documentation popup when manually triggered
        completion = { documentation = { auto_show = false } },

        -- Default list of enabled providers defined so that you can extend it
        -- elsewhere in your config, without redefining it, due to `opts_extend`
        sources = {
          default = { 'lsp', 'path', 'snippets', 'buffer', },
          -- providers = {
          --   codeium = { name = "codeium", module = "codeium.blink", async = true },
          -- },
        },

        -- (Default) Rust fuzzy matcher for typo resistance and significantly better performance
        -- You may use a lua implementation instead by using `implementation = "lua"` or fallback to the lua implementation,
        -- when the Rust fuzzy matcher is not available, by using `implementation = "prefer_rust"`
        --
        -- See the fuzzy documentation for more information
        fuzzy = { implementation = "prefer_rust_with_warning" }
      },
      opts_extend = { "sources.default" }
    },

    "szw/vim-maximizer",

    "azabiong/vim-highlighter",

    {
      'tadaa/vimade',
      -- default opts (you can partially set these or configure them however you like)
      opts = {
        -- Recipe can be any of 'default', 'minimalist', 'duo', and 'ripple'
        -- Set animate = true to enable animations on any recipe.
        -- See the docs for other config options.
        recipe = {'default', {animate=false}},
        -- ncmode = 'windows' will fade inactive windows.
        -- ncmode = 'focus' will only fade after you activate the `:VimadeFocus` command.
        ncmode = 'buffers',
        -- fadelevel = 0.8, -- any value between 0 and 1. 0 is hidden and 1 is opaque.
        -- Changes the real or theoretical background color. basebg can be used to give
        -- transparent terminals accurating dimming.  See the 'Preparing a transparent terminal'
        -- section in the README.md for more info.
        -- basebg = [23,23,23],
        fadelevel = function(style, state)
          if style.win.buf_opts.syntax == 'vertical-bufferline' then
            return 1
          else
            return 0.8
          end
        end,
        basebg = '',
        tint = {
          -- bg = {rgb={0,0,0}, intensity=0.3}, -- adds 30% black to background
          -- fg = {rgb={0,0,255}, intensity=0.3}, -- adds 30% blue to foreground
          -- fg = {rgb={120,120,120}, intensity=1}, -- all text will be gray
          -- sp = {rgb={255,0,0}, intensity=0.5}, -- adds 50% red to special characters
          -- you can also use functions for tint or any value part in the tint object
          -- to create window-specific configurations
          -- see the `Tinting` section of the README for more details.
        },
        -- prevent a window or buffer from being styled. You 
        blocklist = {
          default = {
            highlights = {
              laststatus_3 = function(win, active)
                -- Global statusline, laststatus=3, is currently disabled as multiple windows take
                -- ownership of the StatusLine highlight (see #85).
                if vim.go.laststatus == 3 then
                    -- you can also return tables (e.g. {'StatusLine', 'StatusLineNC'})
                    return 'StatusLine'
                end
              end,
              -- Prevent ActiveTabs from highlighting.
              'TabLineSel',
              'Pmenu',
              'PmenuSel',
              'PmenuKind',
              'PmenuKindSel',
              'PmenuExtra',
              'PmenuExtraSel',
              'PmenuSbar',
              'PmenuThumb',
              -- Lua patterns are supported, just put the text between / symbols:
              -- '/^StatusLine.*/' -- will match any highlight starting with "StatusLine"
            },
            buf_opts = { buftype = {'prompt'} },
            -- buf_name = {'name1','name2', name3'},
            -- buf_vars = { variable = {'match1', 'match2'} },
            -- win_opts = { option = {'match1', 'match2' } },
            -- win_vars = { variable = {'match1', 'match2'} },
            -- win_type = {'name1','name2', name3'},
            -- win_config = { variable = {'match1', 'match2'} },
          },
          default_block_floats = function (win, active)
            return win.win_config.relative ~= '' and
              (win ~= active or win.buf_opts.buftype =='terminal') and true or false
          end,
          -- any_rule_name1 = {
          --   buf_opts = {}
          -- },
          -- only_behind_float_windows = {
          --   buf_opts = function(win, current)
          --     if (win.win_config.relative == '')
          --       and (current and current.win_config.relative ~= '') then
          --         return false
          --     end
          --     return true
          --   end
          -- },
        },
        -- Link connects windows so that they style or unstyle together.
        -- Properties are matched against the active window. Same format as blocklist above
        link = {},
        groupdiff = true, -- links diffs so that they style together
        groupscrollbind = false, -- link scrollbound windows so that they style together.
        -- enable to bind to FocusGained and FocusLost events. This allows fading inactive
        -- tmux panes.
        enablefocusfading = false,
        -- Time in milliseconds before re-checking windows. This is only used when usecursorhold
        -- is set to false.
        checkinterval = 1000,
        -- enables cursorhold event instead of using an async timer.  This may make Vimade
        -- feel more performant in some scenarios. See h:updatetime.
        usecursorhold = false,
        -- when nohlcheck is disabled the highlight tree will always be recomputed. You may
        -- want to disable this if you have a plugin that creates dynamic highlights in
        -- inactive windows. 99% of the time you shouldn't need to change this value.
        nohlcheck = true,
        focus = {
           providers = {
              filetypes = {
                default = {
                  -- If you use mini.indentscope, snacks.indent, or hlchunk, you can also highlight
                  -- using the same indent scope!
                  -- {'snacks', {}},
                  -- {'mini', {}},
                  -- {'hlchunk', {}},
                  {'treesitter', {
                    min_node_size = 2, 
                    min_size = 1,
                    max_size = 0,
                    -- exclude types either too large and/or mundane
                    exclude = {
                      'script_file',
                      'stream',
                      'document',
                      'source_file',
                      'translation_unit',
                      'chunk',
                      'module',
                      'stylesheet',
                      'statement_block',
                      'block',
                      'pair',
                      'program',
                      'switch_case',
                      'catch_clause',
                      'finally_clause',
                      'property_signature',
                      'dictionary',
                      'assignment',
                      'expression_statement',
                      'compound_statement',
                    }
                  }},
                  -- if treesitter fails or there isn't a good match, fallback to blanks
                  -- (similar to limelight)
                  {'blanks', {
                    min_size = 1,
                    max_size = '35%'
                  }},
                  -- if blanks fails to find a good match, fallback to static 35%
                  {'static', {
                    size = '35%'
                  }},
                },
                -- You can make custom configurations for any filetype.  Here are some examples.
                -- markdown ={{'blanks', {min_size=0, max_size='50%'}}, {'static', {max_size='50%'}}}
                -- javascript = {
                  -- -- only use treesitter (no fallbacks)
                --   {'treesitter', { min_node_size = 2, include = {'if_statement', ...}}},
                -- },
                -- typescript = {
                --   {'treesitter', { min_node_size = 2, exclude = {'if_statement'}}}, 
                --   {'static', {size = '35%'}}
                -- },
                -- java = {
                  -- -- mini with a fallback to blanks
                  -- {'mini', {min_size = 1, max_size = 20}},
                  -- {'blanks', {min_size = 1, max_size = '100%' }}, 
                -- },
              },
            }
          },
      }
    },

    -- motion --
    { "t9md/vim-choosewin",
      enabled = false, -- seems to break undo history
      config = function ()
        vim.api.nvim_set_keymap('n',  '-',  '<Plug>(choosewin)', {noremap = true, silent = true})
        vim.g.choosewin_overlay_enable = 1
        vim.g.choosewin_statusline_replace = 0
        vim.g.choosewin_tabline_replace = 0 -- otherwise, bufferline.nvim may not work properly
      end
    },

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
      enabled = false, -- use 'flash.nvim' instead
      config = function ()
        local leap = require('leap')
        leap.set_default_mappings()
        leap.opts.preview_filter =
          function (ch0, ch1, ch2)
            return not (
              ch1:match('%s') or
              ch0:match('%a') and ch1:match('%a') and ch2:match('%a')
            )
          end
      end
    },

    {
      "folke/flash.nvim",
      enabled = true,
      event = "VeryLazy",
      ---@type Flash.Config
      opts = {
        modes = {
          search = {
            enabled = false,
          },
        },
      },
      -- stylua: ignore
      keys = {
        { "<leader>s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
        { "<leader>S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
        { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
        { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
        { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
      },
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

    'voldikss/vim-floaterm',

    -- git --
    {
        "kdheepak/lazygit.nvim",
        lazy = true,
        cmd = {
            "LazyGit",
            "LazyGitConfig",
            "LazyGitCurrentFile",
            "LazyGitFilter",
            "LazyGitFilterCurrentFile",
        },
        -- optional for floating window border decoration
        dependencies = {
            "nvim-lua/plenary.nvim",
        },
        -- setting the keybinding for LazyGit with 'keys' is recommended in
        -- order to load the plugin when the command is run for the first time
        keys = {
            { "<leader>lg", "<cmd>LazyGit<cr>", desc = "LazyGit" }
        },
    },
        
    { 'tpope/vim-fugitive',
      config = function ()
        -- vim.api.nvim_set_keymap('n', '<leader>gs', ':Gstatus<CR>', {noremap = true, })
        -- vim.api.nvim_set_keymap('n', '<leader>gd', ':Gdiff<CR>', {noremap = true, })
        -- vim.api.nvim_set_keymap('n', '<leader>gc', ':Gcommit<CR>', {noremap = true, })
        -- vim.api.nvim_set_keymap('n', '<leader>gl', ':Glog<CR>', {noremap = true, })
        -- vim.api.nvim_set_keymap('n', '<leader>gp', ':Git push<CR>', {noremap = true, })
      end,
    },
    'junegunn/gv.vim',
    -- 'mhinz/vim-signify', -- use gitsigns.nvim instead

    { 'lewis6991/gitsigns.nvim',
      config = require('ruiheng.plugin_setup.gitsigns').config,
    },


    -- overall nvim behavior ---

    { 'akinsho/bufferline.nvim',
      dependencies =
        { 'nvim-tree/nvim-web-devicons', -- optional
        },
      branch = "main",
      -- commit = "73540cb95f8d95aa1af3ed57713c6720c78af915",

      enabled = false,

      config = require('ruiheng.plugin_setup.bufferline').config,
    },

    {
      -- Our custom vertical bufferline
      'vertical-bufferline',
      dir = '/home/ruiheng/config_files/nvim/lua/vertical-bufferline',
      -- dependencies = { 'akinsho/bufferline.nvim' },
      enabled = true,
      -- enabled = function()
      --   -- 只有在启用时才加载这个插件
      --   return vim.g.enable_vertical_bufferline == 1
      -- end,
      config = function()
        local vbl = require('vertical-bufferline')

        -- VBL keymap preset (opt-in)
        local preset = vbl.keymap_preset({
          history_prefix = '<leader>h',
          buffer_prefix = '<leader>',
          group_prefix = '<leader>g',
        })
        vbl.apply_keymaps(preset)

        -- 快速切换到历史文件（通过历史位置编号）
        for i = 1, 9 do
          vim.keymap.set('n', '<leader>h' .. i, function()
            vbl.switch_to_history_file(i)
          end, { noremap = true, silent = true, desc = "Switch to history file " .. i })
        end
      end,
    },

    -- general programming ---

    {
      'piersolenski/import.nvim',
      lazy = true,
      event = { "User LazyLoadProgramming" },
      dependencies = {
        -- One of the following pickers is required:
        'nvim-telescope/telescope.nvim',
     -- 'folke/snacks.nvim',
     -- 'ibhagwan/fzf-lua',
      },
      opts = {
        picker = "telescope", -- or 'fzf-lua' , 'snacks'
      },
      keys = {
        {
          "<leader>im",
          function()
            require("import").pick()
          end,
          desc = "Import",
        },
      },
    },

    {
      "folke/zen-mode.nvim",
      opts = {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    },

    {
      "folke/twilight.nvim",
      opts = {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    },

    {
      "folke/todo-comments.nvim",
      lazy = true,
      event = { "User LazyLoadProgramming" },
      dependencies = { "nvim-lua/plenary.nvim" },
      opts = {
      },
    },

    { "lukas-reineke/indent-blankline.nvim",
      lazy = true,
      event = { "User LazyLoadProgramming" },
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

    {
      "L3MON4D3/LuaSnip",
      lazy = true,
      event = { "User LazyLoadProgramming" },
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
      lazy = true,
      event = { "User LazyLoadProgramming" },
      config = function()
      end
    },

    -- { "sbdchd/neoformat" },
    {
      'stevearc/conform.nvim',
      lazy = true,
      event = { "User LazyLoadProgramming" },
      opts = {
        formatters_by_ft = {
          -- lua = { "stylua" },
          -- Conform will run multiple formatters sequentially
          python = { "ruff" },
          -- You can customize some of the format options for the filetype (:help conform.format)
          -- rust = { "rustfmt", lsp_format = "fallback" },
          -- Conform will run the first available formatter
          -- javascript = { "prettierd", "prettier", stop_after_first = true },
        },
      },
    },

    { "nvim-treesitter/nvim-treesitter",
      lazy = true,
      event = { "User LazyLoadProgramming" },
      branch = 'master',
      build = ':TSUpdate', -- We recommend updating the parsers on update
      config = function()
        local configs = require("nvim-treesitter.configs")
        configs.setup {
          ensure_installed = { "c", "cpp", "haskell", "python", "javascript", "css", "html", "markdown", "markdown_inline", "git_rebase", "gitcommit", "gitignore", "json", "lua", "make", "toml", "yaml", "vim", "vimdoc", "zig" },
          highlight = {
            enable = true,
            additional_vim_regex_highlighting = false,
          },
          injections = {
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
      enabled = false,
      config = function()
        vim.keymap.set("n", "[c", function()
          require("treesitter-context").go_to_context()
        end, { silent = true })

        vim.cmd('hi TreesitterContextBottom gui=underline guisp=Grey')
      end,
    },

    -- LSP --

    { 'neovim/nvim-lspconfig',
      lazy = true,
      event = { "User LazyLoadLSP", "User LazyLoadProgramming" },
      enabled = true,
      config = require('ruiheng.plugin_setup.lspconfig').config,
    },

    {
      "mason-org/mason.nvim",
      lazy = true,
      event = { "User LazyLoadLSP", "User LazyLoadProgramming" },
      opts = {
          ui = {
              icons = {
                  package_installed = "✓",
                  package_pending = "➜",
                  package_uninstalled = "✗"
              }
          }
      }
    },

    { "https://git.sr.ht/~whynothugo/lsp_lines.nvim",
      lazy = true,
      event = { "User LazyLoadLSP", "User LazyLoadProgramming" },
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

    { 'stevearc/aerial.nvim',
      opts = {},
      dependencies = { 'nvim-tree/nvim-web-devicons', 'nvim-treesitter/nvim-treesitter', },
      config = function()
        require('aerial').setup({
        })

        vim.keymap.set('n', '<leader>a', '<cmd>AerialToggle!<CR>', {noremap = true, silent = true})
      end,
    },

    -- AI --
    { "Exafunction/codeium.vim",
      enabled = false,
      config = function()
        -- vim.g.codeium_no_map_tab = true
        -- vim.keymap.set('i', '<C-g>', function () return vim.fn['codeium#Accept']() end, { expr = true })
      end,
    },

    {
      "supermaven-inc/supermaven-nvim",
      config = function()
        require("supermaven-nvim").setup({})
      end,
      enabled = false,
    },

    {
      "github/copilot.vim",
      enabled = false,
    },

    {
      "olimorris/codecompanion.nvim",
      enabled = false,
      dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-treesitter/nvim-treesitter",
      },
      config = require('ruiheng.plugin_setup.codecompanion').config,
    },

    {
        "Exafunction/windsurf.nvim",
        enabled = false,
        dependencies = {
            "nvim-lua/plenary.nvim",
            -- "saghen/blink.cmp",
            "hrsh7th/nvim-cmp",
        },
        config = function()
            require("codeium").setup({
              -- enable_cmp_source = false,
            })
        end
    },

    { 'codota/tabnine-nvim',
      build = "./dl_binaries.sh",
      lazy = true,
      event = { "User LazyLoadAI" },
      enabled = true,
      config = function ()
        require('tabnine').setup({
          disable_auto_comment=true,
          accept_keymap="<Tab>",
          dismiss_keymap = "<C-]>",
          debounce_ms = 800,
          suggestion_color = {gui = "#808080", cterm = 244},
          exclude_filetypes = {"TelescopePrompt", "NvimTree"},
          log_file_path = nil, -- absolute path to Tabnine log file
          ignore_certificate_errors = false,
          workspace_folders = {
            paths = { "/home/ruiheng/lyceum" },
          },
        })
      end,
    },


    -- use lspconfig instead: works better with telescope
    -- { 'neoclide/coc.nvim', branch = 'release' },

    -- 'anuvyklack/pretty-fold.nvim',  -- use this or nvim-ufo

    {'kevinhwang91/nvim-ufo',
      dependencies = 'kevinhwang91/promise-async',
      lazy = true,
      event = { "User LazyLoadProgramming" },
      enabled = true, -- or use pretty-fold.nvim instead
      config = require('ruiheng.plugin_setup.nvim-ufo').config,
    },


    { 'junegunn/vim-easy-align',
      lazy = true,
      event = { "User LazyLoadProgramming" },
      config = function()
        vim.keymap.set('v', '<Enter>', '<Plug>(EasyAlign)', {noremap = true})
        vim.keymap.set('n', 'ga', '<Plug>(EasyAlign)', {noremap = true})
      end
    },

    { 'folke/trouble.nvim',
      dependencies = 'nvim-tree/nvim-web-devicons',
      lazy = true,
      event = { "User LazyLoadProgramming" },
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

    { 'nvimtools/none-ls.nvim',
      lazy = true,
      event = { "User LazyLoadProgramming" },
      dependencies = "nvim-lua/plenary.nvim",
      enabled = true,
      config = require('ruiheng.plugin_setup.null-ls').config,
    },

    -- web --

    { 'posva/vim-vue',
      lazy = true,
      event = { "User LazyLoadVue" },
    },

    -- others --

    { "vim-airline/vim-airline",
      config = function()
        vim.g.airline_powerline_fonts = 1
      end
    },

    "vim-airline/vim-airline-themes",

    -- TODO: remove?
    -- 'nathanaelkane/vim-indent-guides',

    -- clipboard --
    -- "machakann/vim-highlightedyank", -- obsoleted by yanky.nvim

    { "junegunn/vim-peekaboo",
      config = function()
        vim.g.peekaboo_delay = 750
      end
    },

    {
      "gbprod/yanky.nvim",
      opts = {
        system_clipboard = {
          sync_with_ring = not vim.env.SSH_CONNECTION,
        },
        highlight = { timer = 300 },
        textobj = {
          enabled = true,
        },
      },
      keys = {
          { "p", "<Plug>(YankyPutAfter)", mode = { "n", "x" } },
          { "P", "<Plug>(YankyPutBefore)", mode = { "n", "x" } },
          { "<c-n>", "<Plug>(YankyCycleForward)", mode = "n" }, -- 粘贴后按 Ctrl-n 切换下一个历史
          { "<c-p>", "<Plug>(YankyCycleBackward)", mode = "n" },
          { "=p", "<Plug>(YankyPutAfterFilter)", mode = "n" },
          { "=P", "<Plug>(YankyPutBeforeFilter)", mode = "n" },
          { "iy", function() require("yanky.textobj").last_put() end, mode = { "o", "x" } },
      },
    },


    "junegunn/vim-slash",
    "junegunn/limelight.vim",
    "takac/vim-hardtime",
    "yssl/QFEnter",

    { "echasnovski/mini.nvim",
      version = '*',
      config = require('ruiheng.plugin_setup.mini').config,
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
      tag = 'v0.2.0',
      config = require('ruiheng.plugin_setup.telescope').config,
    },

    { "nvim-telescope/telescope-fzf-native.nvim",
      build = 'make',
      dependencies = { 'nvim-telescope/telescope.nvim' },
      config = function()
        require('telescope').load_extension('fzf')
      end
    },

    "Marskey/telescope-sg",

    --- Python ----

    {
      "alexpasmantier/pymple.nvim",
      lazy = true,
      event = { "User LazyLoadPython" },
      dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        -- optional (nicer ui)
        "nvim-tree/nvim-web-devicons",
      },
      build = ":PympleBuild",
      config = function()
        require("pymple").setup()
      end,
    },

    --- haskell ----

    -- 'neovimhaskell/haskell-vim',

    -- 'itchyny/vim-haskell-indent',

    {
      'mrcjkb/haskell-snippets.nvim',
      lazy = true,
      event = { "User LazyLoadHaskell" },
    },

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
      lazy = true,
      event = { "User LazyLoadHaskell" },
      config = function()
        vim.g.yesod_disable_maps = 1
      end
    },

    { "pbrisbin/vim-syntax-shakespeare",
      lazy = true,
      event = { "User LazyLoadHaskell" },
      ft = { 'hamlet', 'cassius', 'julius', 'haskell', }
    },

    { 'mrcjkb/haskell-tools.nvim',
      lazy = true,
      event = { "User LazyLoadHaskell" },
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
    -- 'glench/vim-jinja2-syntax', # not working
    'HiPhish/jinja.vim',

    -- "ixru/nvim-markdown",

    {
        'MeanderingProgrammer/render-markdown.nvim',
        dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.nvim' }, -- if you use the mini.nvim suite
        -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.icons' }, -- if you use standalone mini plugins
        -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
        ---@module 'render-markdown'
        ---@type render.md.UserConfig
        opts = {},
    },

    {
      -- Our custom vertical bufferline
      'jinja-mixied',
      dir = '/home/ruiheng/config_files/nvim/jinja-mixed',
    },

    --- colorschemes ----
    { "catppuccin/nvim", name = "catppuccin", priority = 3000 },
    { 'ribru17/bamboo.nvim',
      priority = 2100,
      config = function()
        require('bamboo').setup {
        }
        require('bamboo').load()
      end,
    },
    { "rebelot/kanagawa.nvim", priority = 100 },
    -- { "sainnhe/everforest", priority = 100 },
    -- { "ellisonleao/gruvbox.nvim", priority = 1000 },
    -- { "folke/tokyonight.nvim", priority = 2000 },
})


local normalize_lazy_load_group_names = {
  python = "Python",
  ai = "AI",
  haskell = "Haskell",
  programming = "Programming",
  lsp = "LSP",
  go = "Go",
  markdown = "Markdown",
  vue = "Vue",
}

local lazy_load_group_deps = {
  python = { "programming", "lsp", },
  haskell = { "programming", "lsp", },
}

-- trigger user event: LazyLoadPython, LazyLoadHaskell, etc
local function lazy_load_group(names)
  local real_names = {}

  for _, name in ipairs(names) do
    name = string.lower(name)
    real_names[name] = true
    deps = lazy_load_group_deps[name] or {}
    for _, dep in ipairs(deps) do
      real_names[dep] = true
    end
  end

  for name, _ in pairs(real_names) do
    name = normalize_lazy_load_group_names[string.lower(name)] or name
    vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad" .. name })
    print("Group [" .. name .. "] has been activated!")
  end
end

-- 注册一个手动命令
vim.api.nvim_create_user_command("LazyLoadGroup", function(opts)
    lazy_load_group(opts.fargs)
end, {
    nargs = '+',
    complete = function()
        -- 这里可以手动列出你定义的组名，方便补全
        local names = {}
        for _, v in pairs(normalize_lazy_load_group_names) do
          table.insert(names, v)
        end
        return names
    end
})


vim.keymap.set('n', '<leader>llg', ':LazyLoadGroup ')

local nvim_mode = vim.env.NViM_MODE or "default"

if nvim_mode == "python" then
  lazy_load_group({ "AI", "LSP", "Programming", "Python" })
end
