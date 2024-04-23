local M = {}

-- to work with 'scope.nvim'
local function delete_or_unlist_buffer(target)
  local function good_to_close()
      local to_go = true
      if vim.api.nvim_get_option_value("modified", { buf = target }) then
        local choice = vim.fn.input("Discard unsaved changes? (y/n) ")
        to_go = choice:lower() == "y" or choice == "yes"
      end
      return to_go
  end

  local ok, utils = pcall(require, 'scope.utils')
  if ok then
      local tab = vim.api.nvim_get_current_tabpage()
      local buf_nums = utils.get_valid_buffers()

      if #(buf_nums) == 1 and buf_nums[1] == target then
          -- try close current tabpage if not the last one
          if vim.fn.tabpagenr('$') == tab then
              -- open an empty buffer instead
              if good_to_close() then
                  vim.cmd("enew")
                  vim.api.nvim_set_option_value("buflisted", false, { buf = target })
                  if target == vim.api.nvim_get_current_buf() then
                    vim.cmd('bnext')
                  end
              end
          else
              vim.cmd('tabclose')
          end
      else
          vim.api.nvim_set_option_value("buflisted", false, { buf = target })
          if target == vim.api.nvim_get_current_buf() then
            vim.cmd('bnext')
          end
      end
  else
      -- default behavior: :bdelete, but let user confirm to discard unsaved changes
      if good_to_close() then
        vim.api.nvim_buf_delete(target, {})
      end
  end
end

M.config = function ()
  local bufferline = require('bufferline')
  bufferline.setup {
    options = {
      diagnostics = false,
      show_buffer_icons = false,
      show_close_icons = false,
      show_buffer_close_icons = false,
      numbers = 'ordinal',

      close_command = delete_or_unlist_buffer,

      custom_filter = function(buf_num, buf_nums)
        local buf_type = vim.bo[buf_num].buftype
        if buf_type == 'quickfix' or buf_type == 'terminal' then
          return false
        end

        return true
      end,
    },
  }

  local map = vim.api.nvim_set_keymap
  local map_opts = { noremap = true, silent = true }

  for i = 1, 9 do
      map("n", "<leader>" .. i, "<cmd>BufferLineGoToBuffer " .. i .. "<CR>", map_opts)

      -- go to absolute pos
      vim.keymap.set("n", "<leader>b" .. i, function () bufferline.go_to(i, true) end, map_opts)
  end

  map("n", "<leader>0", "<cmd>BufferLineGoToBuffer 10<CR>", map_opts)
  map("n", "<leader>$", "<cmd>BufferLineGoToBuffer -1<CR>", map_opts)

  -- go to absolute pos
  vim.keymap.set("n", "<leader>b0", function () bufferline.go_to(10, true) end, map_opts)
  vim.keymap.set("n", "<leader>b$", function () bufferline.go_to(-1, true) end, map_opts)

  map("n", "gb", "<cmd>BufferLineCycleNext<CR>", map_opts)
  map("n", "gB", "<cmd>BufferLineCyclePrev<CR>", map_opts)

  map("n", "<C-T>p", "<cmd>BufferLineTogglePin<CR>", map_opts)
  map("n", "<C-T>o", "<cmd>BufferLineCloseOthers<CR>", map_opts)
  map("n", "<C-T>r", "<cmd>BufferLineCloseRight<CR>", map_opts)
  map("n", "<C-T>l", "<cmd>BufferLineCloseLeft<CR>", map_opts)

  map("n", "<C-T><", "<cmd>BufferLineMovePrev<CR>", map_opts)
  map("n", "<C-T>>", "<cmd>BufferLineMoveNext<CR>", map_opts)

  map("n", "<C-T>0", ":lua require'bufferline'.move_to(1)<CR>", map_opts)
  map("n", "<C-T>$", ":lua require'bufferline'.move_to(-1)<CR>", map_opts)

  map("n", "<leader>p", "<cmd>BufferLinePick<CR>", map_opts)
  map("n", "<leader>P", "<cmd>BufferLinePickClose<CR>", map_opts)
end

return M
