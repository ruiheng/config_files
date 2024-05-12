local M = {}

M.config = function()
  harpoon = require('harpoon')
  harpoon:setup()
  local map_opts = {noremap = true}
  vim.keymap.set("n", "<leader>ha", function() harpoon:list():add() end, vim.tbl_extend('force', map_opts, { desc = 'Harpoon: add to list.' }))
  vim.keymap.set("n", "<leader>hd", function() harpoon:list():remove() end, vim.tbl_extend('force', map_opts, { desc = 'Harpoon: remove from list.' }))
  vim.keymap.set("n", "<leader>hl", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end, vim.tbl_extend('force', map_opts, { desc = 'Harpoon: open list.' }))

  for i = 1, 9 do
    vim.keymap.set("n", "<leader>h" .. i, function() harpoon:list():select(i) end, vim.tbl_extend('force', map_opts, { desc = 'Harpoon: select ' .. i .. '\'th file in list.' }))
  end

  -- Toggle previous & next buffers stored within Harpoon list
  vim.keymap.set("n", "<leader>hp", function() harpoon:list():prev() end, vim.tbl_extend('force', map_opts, { desc = 'Harpoon: open previous item in list.' }))
  vim.keymap.set("n", "<leader>hn", function() harpoon:list():next() end, vim.tbl_extend('force', map_opts, { desc = 'Harpoon: open next item in list.' }))
end

return M

