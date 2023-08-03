local function quickfix_scroll_bottom()
  local cur_win_id = vim.api.nvim_get_current_win()
  local res = vim.fn.getqflist( { winid = 0, qfbufnr = 0, } )
  local qf_win_id = res.winid
  local qf_buf_id = res.qfbufnr
  if qf_win_id ~= 0 and qf_win_id ~= cur_win_id then
    local line_num = vim.api.nvim_buf_line_count(qf_buf_id)
    if line_num > 0 then
      vim.api.nvim_win_set_cursor(qf_win_id, { line_num, 0 })
    end
  end
end

local function open_quickfix_win_but_not_focus()
  local cur_win_id = vim.api.nvim_get_current_win()
  vim.cmd('copen')
  local res = vim.fn.getqflist( { winid = 0, qfbufnr = 0, } )
  local qf_win_id = res.winid
  if qf_win_id ~= 0 and qf_win_id ~= cur_win_id then
    vim.api.nvim_set_current_win(cur_win_id)
  end
end

local quickfix_scroll_bottom_event = 'QuickfixScrollBottom'

vim.api.nvim_create_autocmd('User', {
  callback = quickfix_scroll_bottom,
  pattern = quickfix_scroll_bottom_event,
  desc = [[
    Automatically scroll to the bottom of the quickfix window
  ]]
})

local M = {}
M.quickfix_scroll_bottom_event = quickfix_scroll_bottom_event
M.open_quickfix_win_but_not_focus = open_quickfix_win_but_not_focus
return M
