local M = {}

M.config = function ()
  local cokeline = require('cokeline')

  local is_picking_focus = require('cokeline.mappings').is_picking_focus
  local is_picking_close = require('cokeline.mappings').is_picking_close
  local get_hex = require('cokeline.hlgroups').get_hl_attr

  local red = vim.g.terminal_color_1
  local yellow = vim.g.terminal_color_3

  cokeline.setup {
    default_hl = {
      fg = function(buffer)
        return
          buffer.is_focused
          and get_hex('Normal', 'fg')
           or get_hex('Comment', 'fg')
      end,
      bg = function() return get_hex('ColorColumn', 'bg') end,
    },

    components = {
      {
        text = function(buffer) return (buffer.index ~= 1) and '▏' or '' end,
      },
      {
        text = '  ',
      },
      {
        text = function(buffer)
          return
            (is_picking_focus() or is_picking_close())
            and buffer.pick_letter .. ' '
             or buffer.devicon.icon
        end,
        fg = function(buffer)
          return
            (is_picking_focus() and yellow)
            or (is_picking_close() and red)
            or buffer.devicon.color
        end,
        italic = function()
          return
            (is_picking_focus() or is_picking_close())
        end,
        bold = function()
          return
            (is_picking_focus() or is_picking_close())
        end
      },
      {
        text = ' ',
      },
      {
        text = function(buffer) return buffer.filename .. '  ' end,
        bold = function(buffer) return buffer.is_focused end,
      },
      {
        text = '  ',
      },
    },
  }

  local map = vim.api.nvim_set_keymap
  local map_opts = { noremap = true, silent = true }

  local map = vim.api.nvim_set_keymap

  map("n", "gB", "<Plug>(cokeline-focus-prev)", map_opts)
  map("n", "gb", "<Plug>(cokeline-focus-next)", map_opts)
  -- map("n", "gB", "<Plug>(cokeline-switch-prev)", map_opts)
  -- map("n", "gb", "<Plug>(cokeline-switch-next)", map_opts)

  for i = 1, 9 do
    map(
      "n",
      ("<leader>s%s"):format(i),
      ("<Plug>(cokeline-switch-%s)"):format(i),
      map_opts
    )
    map(
      "n",
      ("<Leader>%s"):format(i),
      ("<Plug>(cokeline-focus-%s)"):format(i),
      map_opts
    )
  end

  vim.keymap.set("n", "<leader>p", function()
      require('cokeline.mappings').pick("focus")
  end, { desc = "Pick a buffer to focus" })

  vim.keymap.set("n", "<leader>P", function()
      require('cokeline.mappings').pick("close")
  end, { desc = "Pick a buffer to close" })

end

return M
