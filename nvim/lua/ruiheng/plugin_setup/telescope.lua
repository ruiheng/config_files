local M = {} 
M.config = function()
  local telescope = require('telescope')
  local builtin = require('telescope.builtin')
  local map_opts = {noremap = true}

  vim.keymap.set("n", "<leader>f", builtin.find_files,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: find files.' }))

  vim.keymap.set("n", "<leader>of", builtin.oldfiles,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: previously open files.' }))

  vim.keymap.set("n", "<leader>L", builtin.live_grep,
    vim.tbl_extend('force', map_opts, { desc = 'Live grep.' }))

  vim.keymap.set("n", "<leader>tl",
    function ()
      local patten = require('ruiheng').current_filename_glob_patten()
      return builtin.live_grep { glob_pattern = patten, }
    end,
    vim.tbl_extend('force', map_opts, { desc = 'Live grep in files with same extension name of the current file.' }))

  -- specially for Yesod project
  vim.keymap.set("n", "<leader>tY",
    function ()
      return builtin.live_grep {
              glob_pattern = { '*.hs', '*.hamlet', '*.julius', '*.lucius', '*.cassius', 'static/*.js', 'static/*.css',}
            }
    end,
    vim.tbl_extend('force', map_opts, { desc = 'Live grep in Yesod project.' }))

  vim.keymap.set("n", "<leader>B", builtin.buffers,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: Buffers.' }))

  local treble_ok, treble = pcall(require, 'treble')
  if treble_ok then
    vim.keymap.set("n", "<leader>B", treble.buffers,
      vim.tbl_extend('force', map_opts, { desc = 'Telescope: Bufferline Buffers.' }))
  end

  vim.keymap.set("n", "<leader>H", builtin.help_tags,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: Search Help.' }))

  vim.keymap.set("n", "<leader>T",
    function () return builtin.tags {fname_width = 70} end,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: Tags.' }))

  vim.keymap.set("n", "<leader>bt", builtin.current_buffer_tags, map_opts)

  vim.keymap.set("n", "<leader>bf", builtin.current_buffer_fuzzy_find,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: fuzzy find in current buffer.' }))

  vim.keymap.set("n", "<leader>td", builtin.diagnostics,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: diagnostics.' }))

  vim.keymap.set("n", "<leader>ds", builtin.lsp_document_symbols,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: LSP Document Symbols.' }))

  -- lsp_workspace_symbols doesn't work, use lsp_dynamic_workspace_symbols instead
  vim.keymap.set("n", "<leader>ws", builtin.lsp_dynamic_workspace_symbols,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: LSP Dynamic Workspace Symbols.' }))

  vim.keymap.set("n", "<leader>ts", builtin.treesitter,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: Treesitter.' }))

  vim.keymap.set("n", "<leader>tc", builtin.commands,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: vim commands.' }))

  vim.keymap.set("n", "<leader>tm", builtin.marks,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: marks.' }))

  vim.keymap.set("n", "<leader>tb", builtin.builtin,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: all builtin pickers.' }))

  local function safe_load_extension(ext)
    local ok = pcall(telescope.load_extension, ext)
    return ok
  end

  telescope.setup{
    defaults = {
      layout_strategy = 'vertical',
      layout_config = { height = 0.95 },
    },
    pickers = {
      lsp_document_symbols = {
        symbol_width = 60,
      },
      treesitter = {
        symbol_width = 60,
      },
    },
    extensions = {
        ast_grep = {
            command = {
                "ast-grep",
                "--json=stream",
            }, -- must have --json=stream
            grep_open_files = false, -- search in opened files
            lang = nil, -- string value, specify language for ast-grep `nil` for default
      }
    },
  }

  if safe_load_extension("yank_history") then
    vim.keymap.set("n", "<leader>ty", ":Telescope yank_history<CR>",
      vim.tbl_extend('force', map_opts, { desc = 'Telescope: yanky history' }))
  end

  if safe_load_extension("ast_grep") then
    vim.keymap.set('n', '<leader>sg', ':Telescope ast_grep<CR>',
        {noremap = true, desc = 'invoke Telelescope for AST Grep' })
  end
end

return M
