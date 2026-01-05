local M = {} 

M.load_telescope_extension = function(ext)
  local telescope = require('telescope')
  telescope.load_extension(ext)
end

M.safe_load_telescope_extension = function(ext)
  local ok = pcall(M.load_telescope_extension, ext)
  if not ok then
    vim.notify('Failed to load telescope extension: ' .. ext)
  end
  return ok
end

return M
