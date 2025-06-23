local M = {}

M.config = function ()
  vim.g.minisurround_disable   = true
  vim.g.minicompletion_disable = true
  vim.g.ministarter_disable    = true

  -- doesn't work, no effect. don't know why
  -- require('mini.animate').setup()

  require('mini.surround').setup()

  -- require('mini.surround').setup {
  --   -- Module mappings. Use `''` (empty string) to disable one.
  --   mappings = {
  --     add = 'sa', -- Add surrounding in Normal and Visual modes
  --     delete = 'sd', -- Delete surrounding
  --     find = 'sf', -- Find surrounding (to the right)
  --     find_left = 'sF', -- Find surrounding (to the left)
  --     highlight = 'sh', -- Highlight surrounding
  --     replace = 'sr', -- Replace surrounding
  --     update_n_lines = 'sn', -- Update `n_lines`
  --
  --     suffix_last = 'l', -- Suffix to search with "prev" method
  --     suffix_next = 'n', -- Suffix to search with "next" method
  --   },
  --
  --   -- Number of lines within which surrounding is searched
  --   n_lines = 20,
  --
  --   -- Whether to respect selection type:
  --   -- - Place surroundings on separate lines in linewise mode.
  --   -- - Place surroundings on each line in blockwise mode.
  --   respect_selection_type = false,
  --
  --   -- How to search for surrounding (first inside current line, then inside
  --   -- neighborhood). One of 'cover', 'cover_or_next', 'cover_or_prev',
  --   -- 'cover_or_nearest', 'next', 'prev', 'nearest'. For more details,
  --   -- see `:h MiniSurround.config`.
  --   search_method = 'cover',
  --
  --   -- Whether to disable showing non-error feedback
  --   silent = false,
  -- }

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

return M

