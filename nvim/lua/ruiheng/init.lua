local M = {}

M.save_bufer = function (buf)
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


M.save_all_buffers = function ()
  local errs = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local err = M.save_bufer(buf)
      if err then
        table.insert(errs, { file = vim.api.nvim_buf_get_name(buf), bufnr = buf, err = err } )
      end
    end
  end
  return errs
end


function M.current_filename_glob_patten()
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
-- use <localleader>x to close the terminal window (but keep the command running)
-- use <localleader>t to cycle through running terminals
  vim.keymap.set( { 'n', 't' }, '<localleader>t',
    function() M.cycle_running_cmd_terminal() end,
    vim.tbl_extend('force', map_opts, { desc = 'Cycle through running terminals.' }))

  vim.keymap.set( { 'n', 't' }, '<localleader>x',
    function() terminal:close() end,
    vim.tbl_extend('force', map_opts, { desc = 'Close terminal.' }))
end

--  create (or reuse existing one) to run a command
--  this requires 'toggleterm.nvim'
function M.toggle_terminal_run (cmd_args)
  if cmd_args == nil or cmd_args == '' or #cmd_args == 0 then
    if current_terminal ~= nil then
      current_terminal:open()
      return True
    end

    vim.notify('no running terminal', vim.log.levels.WARN)
    return False
  end

  local cmd
  if type(cmd_args) == 'string' then
    cmd = cmd_args
  elseif type(cmd_args) == 'table' then
    cmd = table.concat(cmd_args, ' ')
  else
    print('invalid argument type: ' .. type(cmd_args))
    return
  end

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
M.cycle_running_cmd_terminal = function (pattern)
  local pick = function (term)
    term:open()
    current_terminal = term
  end

  if current_terminal == nil then
    -- current terminal exited
    local the_terminal
    for cmd, term in pairs(cmd_to_terminal) do
      if pattern == nil or string.match(cmd, pattern) ~= nil then
        if the_terminal == nil then
          the_terminal = term
        else
          if the_terminal.job_id > term.job_id then
            the_terminal = term
          end
        end
      end
    end

    if the_terminal then
      pick(the_terminal)
    else
      vim.notify('no running terminal', vim.log.levels.WARN)
    end
  else
    local first_terminal = nil
    local the_terminal

    for cmd, term in pairs(cmd_to_terminal) do
      if pattern == nil or string.match(cmd, pattern) ~= nil then
        if first_terminal == nil or term.job_id < first_terminal.job_id then
          first_terminal = term
        end

        -- next terminal that job_id > current_terminal.job_id
        if term ~= current_terminal then
          if the_terminal == nil then
            the_terminal = term
          elseif the_terminal.job_id > term.job_id then
            the_terminal = term
          end
        end
      end
    end

    if the_terminal then
      pick(the_terminal)
    elseif first_terminal then
      pick(first_terminal)
    else
      vim.notify('no running terminal', vim.log.levels.WARN)
    end
  end
end

return M
