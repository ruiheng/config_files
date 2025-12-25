local M = {}

-- Smart buffer close function that works with vertical-bufferline and scope.nvim
local function smart_delete_buffer(target)
  -- Check if vertical-bufferline is enabled and available
  if vim.g.enable_vertical_bufferline == 1 then
    local ok, vbl_integration = pcall(require, 'vertical-bufferline.bufferline-integration')
    if ok and vbl_integration.smart_close_buffer then
      return vbl_integration.smart_close_buffer(target)
    end
  end
  
  -- Fallback to scope.nvim logic if vertical-bufferline is not available
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
                  -- Safe bnext with fallback
                  local success = pcall(vim.cmd, 'bnext')
                  if not success then
                    -- If bnext fails, we're likely at the last buffer
                    vim.cmd("enew")
                  end
              end
          else
              vim.cmd('tabclose')
          end
      else
          vim.api.nvim_set_option_value("buflisted", false, { buf = target })
          if target == vim.api.nvim_get_current_buf() then
            local success = pcall(vim.cmd, 'bnext')
            if not success then
              -- If bnext fails, create a new buffer
              vim.cmd("enew")
            end
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

      close_command = smart_delete_buffer,

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
  local map_opts_wk_ignore = vim.deepcopy(map_opts)
  map_opts_wk_ignore['desc'] = '[WK-IGNORE]'

  local function mk_map_opts(desc, ignore)
    if ignore then
      desc = desc.. " [WK-IGNORE]"
    end
    return { noremap = true, silent = true, desc = desc }
  end


  for i = 1, 9 do
      map("n", "<leader>" .. i, "<cmd>BufferLineGoToBuffer " .. i .. "<CR>", map_opts_wk_ignore)

      -- go to absolute pos
      vim.keymap.set("n", "<leader>b" .. i, function () bufferline.go_to(i, true) end, map_opts_wk_ignore)
  end

  map("n", "<leader>0", "<cmd>BufferLineGoToBuffer 10<CR>", map_opts_wk_ignore)
  map("n", "<leader>$", "<cmd>BufferLineGoToBuffer -1<CR>", map_opts_wk_ignore)

  -- go to absolute pos
  vim.keymap.set("n", "<leader>b0", function () bufferline.go_to(10, true) end, map_opts_wk_ignore)
  vim.keymap.set("n", "<leader>b$", function () bufferline.go_to(-1, true) end, map_opts_wk_ignore)

  map("n", "gb", "<cmd>BufferLineCycleNext<CR>", map_opts_wk_ignore)
  map("n", "gB", "<cmd>BufferLineCyclePrev<CR>", map_opts_wk_ignore)

  map("n", "<C-T>p", "<cmd>BufferLineTogglePin<CR>", mk_map_opts('Pin the buffer [bufferline]', false))
  map("n", "<C-T>o", "<cmd>BufferLineCloseOthers<CR>", mk_map_opts('Close other buffers [bufferline]', false))
  map("n", "<C-T>r", "<cmd>BufferLineCloseRight<CR>", mk_map_opts('Close the next/right buffer [bufferline]', false))
  map("n", "<C-T>l", "<cmd>BufferLineCloseLeft<CR>", mk_map_opts('Close the prev/left buffer [bufferline]', false))

  map("n", "<C-T><", "<cmd>BufferLineMovePrev<CR>", mk_map_opts('Move the buffer to prev/left [bufferline]', false))
  map("n", "<C-T>>", "<cmd>BufferLineMoveNext<CR>", mk_map_opts('Move the buffer to next/right [bufferline]', false))

  map("n", "<C-T>0", ":lua require'bufferline'.move_to(1)<CR>", mk_map_opts('Move the buffer to first [bufferline]', false))
  map("n", "<C-T>$", ":lua require'bufferline'.move_to(-1)<CR>", mk_map_opts('Move the buffer to last [bufferline]', false))

  map("n", "<leader>p", "<cmd>BufferLinePick<CR>", map_opts_wk_ignore)
  map("n", "<leader>P", "<cmd>BufferLinePickClose<CR>", map_opts_wk_ignore)
end

return M
