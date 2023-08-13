local function save_bufer(buf)
  local buf_type = vim.api.nvim_get_option_value("buftype", { buf = buf })
  if buf_type ~= '' then return end

  if vim.api.nvim_get_option_value("readonly", { buf = buf }) then return end
  if not vim.api.nvim_get_option_value("modifiable", { buf = buf }) then return end

  local filename = vim.api.nvim_buf_get_name(buf)
  if filename == '' then return end
  if vim.startswith(filename, 'fugitive://') then return end

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
    if vim.api.nvim_buf_is_loaded(buf) then
      local err = save_bufer(buf)
      if err then
        table.insert(errs, { file = vim.api.nvim_buf_get_name(buf), bufnr = buf, err = err } )
      end
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


local cmd_to_terminal = { }
local current_terminal = nil

local function setup_new_terminal(terminal)
  local map_opts = { buffer = terminal.bufnr, }
  -- vim.keymap.set( { 'n', 't'
end

--  create (or reuse existing one) to run a command
--  this requires 'toggleterm.nvim'
local toggle_terminal_run = function (cmd_args)
  local cmd = table.concat(cmd_args, ' ')
  local old_terminal = cmd_to_terminal[cmd]

  local on_exit = function (terminal, job, exit_code, name)
    cmd_to_terminal[cmd] = nil
    if current_terminal == terminal then
      current_terminal = nil
    end
  end

  local create_new = function()
    local new_terminal = require('toggleterm.terminal').Terminal:new {
      cmd = cmd,
      close_on_exit = true,
      hidden = true,
      on_exit = on_exit,
      on_create = setup_new_terminal,
    }
    new_terminal:toggle()
    cmd_to_terminal[cmd] = new_terminal
    current_terminal = new_terminal
  end

  if old_terminal == nil then
    create_new()
  else
    if vim.fn.jobwait( { old_terminal.job_id }, 0 )[0] == -1 then
      -- still running
      old_terminal:toggle()
      current_terminal = old_terminal
    else
      -- exit the old one, create a new one
      old_terminal:shutdown()
      create_new()
    end
  end
end


local hide_all_running_cmd_terminal = function()
  for cmd, terminal in pairs(cmd_to_terminal) do
    terminal:close()
  end
end


-- show next terminal window that was created by toggle_terminal_run
local next_running_cmd_terminal = function ()
  local pick = function (term)
    term:open()
    current_terminal = term
  end

  if current_terminal == nil then
    local the_terminal
    for cmd, term in pairs(cmd_to_terminal) do
      if the_terminal == nil then
        the_terminal = term
      else
        if the_terminal.job_id > term.job_id then
          the_terminal = term
        end
      end
    end

    if the_terminal then
      pick(the_terminal)
    end
  else
    local first_terminal = nil
    local the_terminal

    for cmd, term in pairs(cmd_to_terminal) do
      if first_terminal == nil then
        first_terminal = term
      end

      if the_terminal.job_id > term.job_id then
        the_terminal = term
      end
    end

    if the_terminal then
      pick(the_terminal)
    elseif first_terminal then
      pick(first_terminal)
    end
  end
end

return {
  save_bufer = save_bufer,
  save_all_buffers = save_all_buffers,
  current_filename_glob_patten = current_filename_glob_patten,
  toggle_terminal_run = toggle_terminal_run,

