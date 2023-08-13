local M = {} 
M.config = function()
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
  vim.keymap.set("n", "<leader>ty",
    function ()
      return builtin.live_grep {
              glob_pattern = { '*.hs', '*.hamlet', '*.julius', '*.lucius', '*.cassius', 'static/*.js', 'static/*.css',}
            }
    end,
    vim.tbl_extend('force', map_opts, { desc = 'Live grep in Yesod project.' }))

  vim.keymap.set("n", "<leader>B", builtin.buffers,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: Buffers.' }))

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

  vim.keymap.set("n", "<leader>tc", builtin.commands,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: vim commands.' }))

  vim.keymap.set("n", "<leader>tm", builtin.marks,
    vim.tbl_extend('force', map_opts, { desc = 'Telescope: marks.' }))

  require('telescope').setup{
    defaults = {
      layout_strategy = 'vertical',
      layout_config = { height = 0.95 },
    },
  }
end

return M
