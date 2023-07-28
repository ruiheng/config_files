{
    { 'romgrk/barbar.nvim',
      dependencies =
        { 'nvim-tree/nvim-web-devicons', -- optional
          'lewis6991/gitsigns.nvim', -- optional
        },

      -- using bufferline.nvim now
      -- barbar.nvim seems have some trouble to save session
      enabled = false,

      opts = {
        animation = false,
        icons = {
          buffer_index = true,
          -- documents says 'file_type', which is wrong
          filetype = {
            enabled = false,
          },
          preset = 'slanted',
          pinned = { filename = true, },
          current = { buffer_index = false, },
        },
      },

      config = function(_, opts)
        require('barbar').setup(opts)

        local map = vim.api.nvim_set_keymap
        local map_opts = { noremap = true, silent = true }

        for i = 1, 9 do
            map("n", "<leader>" .. i, "<cmd>BufferGoto " .. i .. "<CR>", map_opts)
        end
        map("n", "<leader>0", "<cmd>BufferGoto 10<CR>", map_opts)
        map("n", "<leader>$", "<cmd>BufferLast<CR>", map_opts)

        map("n", "<C-T>c", "<cmd>BufferClose<CR>", map_opts)
        map("n", "<C-S-T>c", "<cmd>BufferRestore<CR>", map_opts)
        map("n", "<C-T>p", "<cmd>BufferPin<CR>", map_opts)
        map("n", "<C-T>o", "<cmd>BufferCloseAllButCurrentOrPinned<CR>", map_opts)
        map("n", "gb", "<cmd>BufferNext<CR>", map_opts)
        map("n", "gB", "<cmd>BufferPrevious<CR>", map_opts)

        map("n", "<C-T><", "<cmd>BufferMovePrevious<CR>", map_opts)
        map("n", "<C-T>>", "<cmd>BufferMoveNext<CR>", map_opts)

        map("n", "<leader>p", "<cmd>BufferPick<CR>", map_opts)
        map("n", "<leader>P", "<cmd>BufferPickDelete<CR>", map_opts)
      end,
    },

    { "zefei/vim-wintabs",
      -- using bufferline.nvim now
      enabled = false,
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

    { 'backdround/tabscope.nvim',
      -- with tabscope, session could not be restored with all tabs and their buffers
      -- only the 'active' buffer of each vim tab can be restored.
      enabled = false,
      config = function()
        require('tabscope').setup{}
      end,
    },

    { 'jedrzejboczar/possession.nvim',
      dependencies = 'nvim-lua/plenary.nvim',
      enabled = false,  -- using mini.session
      opts = {
        hooks = {
          before_save = function()
            vim.api.nvim_exec_autocmds('User', { pattern = 'SessionSavePre' })
            return {}
          end,
        },
      },
      config = function(_, opts)
        require('possession').setup(opts)

        local telescope = require('telescope')
        telescope.load_extension('possession')
        local map_opts = {noremap = true}
        vim.keymap.set("n", "<leader>ts", telescope.extensions.possession.list, map_opts)
      end,
    },

    { "ahmedkhalf/project.nvim",
      dependencies = { 'nvim-telescope/telescope.nvim' },
      enabled = false,
      config = function()
        require('project_nvim').setup {
          detection_methods = { 'pattern', },
          patterns = { '*.cabal', 'stack.yaml', 'package.json' },
        }

        local telescope = require('telescope')
        telescope.load_extension('projects')
        vim.keymap.set('n', '<leader>tp', telescope.extensions.projects.projects, {noremap = true})
      end
    },

    { 'nanozuki/tabby.nvim',
      enabled = false,  -- doesn't work with barbar.nvim
      config = function()
        require('my_tabby_theme')
        require('tabby').setup{}
      end,
    },


    { "yuttie/comfortable-motion.vim",
      enabled = false,
      config = function()
        vim.g.comfortable_motion_friction = 0
        vim.g.comfortable_motion_air_drag = 4
      end
    },


}
