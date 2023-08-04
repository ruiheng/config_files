local function save_bufer(buf)
  local filename = vim.api.nvim_buf_get_name(buf)
  if filename == '' then return end

  local ok, err = pcall(vim.api.nvim_buf_call, buf,
                        function()
                          vim.cmd('write')
                        end
                        )

  if not ok then
    return err
  end
end


local function save_all_buffers()
  local errs = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local err = save_bufer(buf)
    if err then
      table.insert(errs, err)
    end
  end
  return errs
end

return {
  save_bufer = save_bufer,
  save_all_buffers = save_all_buffers,
}
