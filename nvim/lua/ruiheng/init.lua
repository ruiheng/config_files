local function save_bufer(buf)
  local buf_type = vim.api.nvim_get_option_value("buftype", { buf = buf })
  if buf_type ~= '' then return end

  if vim.api.nvim_get_option_value("readonly", { buf = buf }) then return end
  if not vim.api.nvim_get_option_value("modifiable", { buf = buf }) then return end

  local filename = vim.api.nvim_buf_get_name(buf)
  if filename == '' then return end
  if vim.startswith(filename, 'fugitive://') then return end

  print('filename: ' .. filename .. ' buf_type: ' .. buf_type)

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
      table.insert(errs, { file = vim.api.nvim_buf_get_name(buf), bufnr = buf, err = err } )
    end
  end
  return errs
end


local function current_filename_glob_patten()
  local filename = vim.api.nvim_buf_get_name(0)
  if filename == '' then return '*' end
  local i = filename:find("%.")

  if i == nil then
    return '*'
  else
    local ext = filename:sub(i+1)
    return '*.' .. ext
  end
end


return {
  save_bufer = save_bufer,
  save_all_buffers = save_all_buffers,
  current_filename_glob_patten = current_filename_glob_patten,
}
