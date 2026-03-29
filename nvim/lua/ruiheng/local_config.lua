local M = {}

local function notify_error(message)
  vim.schedule(function()
    vim.notify(message, vim.log.levels.ERROR)
  end)
end

local function read_json(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local lines = vim.fn.readfile(path)
  local content = table.concat(lines, "\n")
  if content == "" then
    return {}
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    notify_error("Invalid JSON in " .. path)
    return nil
  end

  return decoded
end

function M.setup()
  local config_dir = vim.fn.stdpath("config")
  local local_override_path = config_dir .. "/coc-settings.local.json"
  if vim.fn.filereadable(local_override_path) ~= 1 then
    return
  end

  local base_config = read_json(config_dir .. "/coc-settings.json")
  local local_override = read_json(local_override_path)
  if base_config == nil or local_override == nil then
    return
  end

  local merged = vim.tbl_deep_extend("force", base_config, local_override)
  local runtime_dir = vim.fn.stdpath("state") .. "/coc-config"
  local runtime_path = runtime_dir .. "/coc-settings.json"

  vim.fn.mkdir(runtime_dir, "p")

  local ok, encoded = pcall(vim.json.encode, merged)
  if not ok then
    notify_error("Failed to encode merged coc config")
    return
  end

  local write_ok = pcall(vim.fn.writefile, { encoded }, runtime_path)
  if not write_ok then
    notify_error("Failed to write merged coc config to " .. runtime_path)
    return
  end

  vim.g.coc_config_home = runtime_dir
end

return M
