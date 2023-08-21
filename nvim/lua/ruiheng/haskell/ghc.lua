local M = {}

M.locate_first_cabal_file = function ()
  local dir = vim.fn.getcwd()

  while true do
    local files = vim.fn.glob(dir .. '/*.cabal', 0, 1)
    if #files == 1 then
      return files[1]
    elseif #files > 1 then
      return nil, 'More than one cabal file found: ' .. table.concat(files, ', ')
    end

    dir = vim.fn.fnamemodify(dir, ':h')
    if dir == '/' then break end
  end

  return nil, 'No cabal file found'
end

M.get_name_from_cabal_file = function (file)
  local line
  for line in io.lines(file) do
    local name = string.match(line, '^name:%s*(.+)%s*$')
    if name then return name end
  end
end


local severity_table = {
  error = 1,
  warning = 2,
  -- info = 3,
  -- hint = 4,
}

local function strip_prompt_prefix(line)
  if line == "" then return line end

  -- may contain prefix like: xxx-lib > ....
  local line1 = string.match(line, '^[%w-]+%s*> (.+)$')
  if line1 ~= nil then line = line1 end

  return line
end

local function diag_set_bufnr(diag)
  if diag.bufnr == nil then
    diag.bufnr = vim.fn.bufnr( diag.filename, true )
  end
end


local function diag_set_line_col_one_indexed(diag)
  if diag.row then
    diag.lnum = diag.row
  end

  if diag.end_row then
    diag.end_lnum = diag.end_row
  end

  if diag._col then
    diag.col = diag._col
  end

  if diag._end_col then
    diag.end_col = diag._end_col
  end
end


-- set lnum, end_lnum, col, end_col
-- caution: in diagnostics structure, all these number a zero-indexed
local function diag_set_line_col_zero_indexed(diag)
  if diag.row then
    diag.lnum = diag.row - 1
  end

  if diag.end_row then
    diag.end_lnum = diag.end_row - 1
  end

  if diag._col then
    diag.col = diag._col - 1
  end

  if diag._end_col then
    diag.end_col = diag._end_col - 1
  end
end


local function diag_set_text(diag)
  if diag.text == nil then
    diag.text = diag.message
  end
end


-- line format: filename:error_span_str: severity
local function parse_diagnostics_beginning(line, log)
  local row, col, end_row, end_col
  local filename, severity, msg

  local function log_error(err_msg)
    if log then log:error(line .. ": " .. err_msg) end
  end

  line = strip_prompt_prefix(line)
  if vim.trim(line) == '' then return end

  local filename_and_error_span_str, severity_str, msg = string.match(line, '^(/.+): (%w+):(.*)$')
  local severity
  if filename_and_error_span_str ~= nil and severity_str ~= nil then
    severity = severity_table[severity_str]
    if severity == nil then
      log_error("unknown severity: " .. severity_str)
      return
    end

    -- if using -ferror-spans, format is one of the following:
    --   * row:col-end_col
    --   * (row, col)-(end_row, end_col)
    -- otherwise, format is one of the following:
    --   * row:col

    --   try: (row, col)-(end_row, end_col)
    local num1, num2, num3, num4
    filename, num1, num2, num3, num4 = string.match(filename_and_error_span_str, "(.+):%((%d+),(%d+)%)%-%((%d+),(%d+)%)$")
    if filename ~= nil then
      row = tonumber(num1)
      col = tonumber(num2)
      end_row = tonumber(num3)
      end_col = tonumber(num4)
    else
      -- try: row:col-end_col
      filename, num1, num2, num3 = string.match(filename_and_error_span_str, "(.+):(%d+):(%d+)-(%d+)$")
      if filename ~= nil then
        row = tonumber(num1)
        col = tonumber(num2)
        end_col = tonumber(num3)
      else
        --  try: row:col
        filename, num1, num2 = string.match(filename_and_error_span_str, "(.+):(%d+):(%d+)$")
        if filename ~= nil then
          row = tonumber(num1)
          col = tonumber(num2)
        else
          -- log_error("unknown format")
        end
      end
    end
  else
    -- other messages
    -- log:debug('line not match beginning mark: ' .. line)
  end

  return filename, severity, row, col, end_row, end_col, msg
end


-- line that begins with 4 spaces
local function parse_indented_message_line(line)
  line = strip_prompt_prefix(line)
  if line:sub(1, 4) == "    " then
    return line:sub(5)
  end
end


local other_normal_message_patterns = {
  '^configure .+',
  '^Configuring .+',
  '^build %(.+%)',
  '^Preprocessing library for .+',
  '^Preprocessing executable .+',
  '^Building executable .+',
  '^Installing executable .+',
  '^Building library for .+',
  '^Installing library in .+',
  '^Installing executable in .+',
  '^copy/register',
  '^Registering library .+',
  '^Compiling .+',
  '^Linking .+',
}

local function other_normal_message(line)
  if line == "" then return true end

  line = strip_prompt_prefix(line)

  line1 = string.match(line, '^%[%s*%d+ of%s+%d+%]%s+([^%s].+)$')
  if line1 ~= nil then line = line1 end

  for _, p in ipairs(other_normal_message_patterns) do
    if string.match(line, p) then return true end
  end
end

local function qf_list_add_one(t)
  local function doit ()
    if type(t) == 'string' then
      vim.fn.setqflist( { { text = t } }, 'a' )
    elseif type(t) == 'table' then
      diag_set_text(t)
      diag_set_line_col_one_indexed(t)
      vim.fn.setqflist( { t }, 'a' )
    end

    local qf = require('ruiheng.quickfix');
    vim.api.nvim_exec_autocmds('User', { pattern = qf.quickfix_scroll_bottom_event } )
  end

  if vim.in_fast_event() then
    vim.schedule_wrap(doit)()
  else
    doit()
  end
end


local GhcOutputParser = {}

function GhcOutputParser:new(init_obj)
  local o = vim.tbl_extend(
          'force',
          {
            -- init params
            log = nil,
            sync_to_qf = false,

            -- results
            diags = {},
            stack_summary_msg = {},
            unrecognized_list = {},

            -- internals
            diag = nil,
            msg_lines = {},
            stack_summary_msg_started = false,
          },
          init_obj
          )

  setmetatable(o, self)
  self.__index = self
  return o
end


function GhcOutputParser:append_qf_message(t)
  if self.sync_to_qf then
    qf_list_add_one(t)
  end
end


function GhcOutputParser:parse_output_other_line(line)
  self:append_qf_message(line)

  if other_normal_message(line) then
    return
  end
  if self.log then self.log:debug('unrecognized line: ' .. line) end
  table.insert(self.unrecognized_list, line)
end


function GhcOutputParser:try_parse_output_final_summary(line)
  if not self.stack_summary_msg_started then
    local msg = string.match(line, '^Error: %[S%-%d+%]')
    if msg == nil then
      self:parse_output_other_line(line)
    else
      self:append_qf_message(line)
      self.stack_summary_msg_started = true
      table.insert(self.stack_summary_msg, msg)
    end
  else
    local msg = parse_indented_message_line(line)
    if msg ~= nil then
      self:append_qf_message(line)
      table.insert(self.stack_summary_msg, msg)
    else
      self:parse_output_other_line(line)
    end
  end
end


function GhcOutputParser:parse_build_output_line(line)
  if self.diag == nil then
    -- looking for a diagnostic message beginning
    local filename, severity, row, col, end_row, end_col, msg = parse_diagnostics_beginning(line, self.log)
    if filename ~= nil and severity ~= nil and row ~= nil and col ~= nil then
      -- col/end_col maybe zero-indexed or one-indexed, depending on api usage
      -- here they are saved as _col/_end_col, which are always one-indexed
      self.diag = { row = row, _col = col, end_row = end_row, _end_col = end_col, filename = filename, severity = severity,
                  }
      self.msg_lines = {}
      if msg then
        msg = vim.trim(msg)
        if #msg > 0 then table.insert(self.msg_lines, msg) end
      end
    else
      self:try_parse_output_final_summary(line)
    end
  else
    -- looking for a diagnostic message content
    local msg = parse_indented_message_line(line)
    if msg ~= nil then
      -- ignore diagnostic message content, because it is too long, user should use diagnostics to read it
      -- self:append_qf_message(line)
      table.insert(self.msg_lines, msg)
    else
      if #self.msg_lines == 0 then
        if self.log then
          self.log:error('should be a message:' .. line)
          self.log:error('should be a message:' .. strip_prompt_prefix(line))
        end
      end

      -- end of diagnostic message
      self.diag.message = table.concat(self.msg_lines, "\n")
      table.insert(self.diags, self.diag)
      self:append_qf_message(self.diag)
      self.diag = nil

      self:try_parse_output_final_summary(line)
    end
  end
end


function GhcOutputParser:parse_build_output_whole(output)
  local lines = vim.split(output, "\n")

  for _, line in ipairs(lines) do
    self:parse_build_output_line(line)
  end
end


-- only copy unrecognized messages and summary messages
function GhcOutputParser:set_quickfix_messages()
  local qf_list = {}
  for _, line in ipairs(self.unrecognized_list) do
    table.insert(qf_list, { text = line })
  end

  for _, line in ipairs(self.stack_summary_msg) do
    table.insert(qf_list, { text = line })
  end

  if #qf_list > 0 then
    vim.fn.setqflist(qf_list, 'a')
  end
end

function GhcOutputParser:set_diagnostics(ns_id)
  local bufnr_diags = {}

  for _, diag in ipairs(self.diags) do
    diag_set_bufnr(diag)
    diag_set_line_col_zero_indexed(diag)

    if diag.bufnr == -1 then
      vim.notify("no bufnr for " .. diag.filename, vim.log.ERROR)
    else
      if bufnr_diags[diag.bufnr] == nil then
        bufnr_diags[diag.bufnr] = {}
      end

      table.insert(bufnr_diags[diag.bufnr], diag)
    end
  end

  for bufnr, diags in pairs(bufnr_diags) do
    vim.diagnostic.set(ns_id, bufnr, diags)
  end
end


M.make_start_build_args_wd = function (cmd)
  local working_dir = vim.fn.getcwd()
  local package_name

  if cmd == nil or cmd == 'stack' then
    local args = {
                "build",
                "--ghc-options", "-fno-diagnostics-show-caret",
                "--ghc-options", "-fdefer-diagnostics",
                "--ghc-options", "-fdiagnostics-color=never",
                "--ghc-options", "-ferror-spans",
              }

    local cabal_file = M.locate_first_cabal_file()
    if cabal_file ~= nil then
      qf_list_add_one('Found cabal file: ' .. cabal_file)
      package_name = M.get_name_from_cabal_file(cabal_file)
      qf_list_add_one('Package name: ' .. package_name)
      working_dir = vim.fn.fnamemodify(cabal_file, ':p:h')
    end

    local f = io.open("stack-diagnostic-flags.txt", "rb")
    if f == nil then
      qf_list_add_one('stack-diagnostic-flags.txt not found')

    else
      qf_list_add_one('found stack-diagnostic-flags.txt')
      for line in f:lines() do
        if line:find('#', 1, true) ~= 1 then
          table.insert(args, line)
        end
      end
      f:close()
    end

    if package_name ~= nil then
      table.insert(args, package_name)
    else
      table.insert(args, ".")
    end

    return args, working_dir
  else
    return { "build", }, working_dir
  end
end


local namespace_name = 'ruiheng-ghc-compile'
local ns_id = vim.api.nvim_create_namespace(namespace_name)
local build_jobs = {}

-- create a new job to call 'stack build'
M.start_build_job = function (cmd, init_cmd_args, init_wd)
  vim.fn.setqflist({}, ' ' )

  local wd = '.'

  if cmd == nil then
    cmd = 'stack'
  end

  if init_wd ~= nil then wd = init_wd end

  local cmd_args
  if init_cmd_args then
    cmd_args = init_cmd_args
  else
    cmd_args, wd = M.make_start_build_args_wd(cmd)
  end

  table.insert(cmd_args, 1, cmd)

  local parser = GhcOutputParser:new { sync_to_qf = true }

  local line_leftover = nil
  local pid = nil
  local job_start, job_end

  local function on_exit(obj)
    job_end = vim.uv.hrtime()
    local duration = ( job_end - job_start ) / 1000000000
    vim.schedule_wrap(function()
      qf_list_add_one('Job finished at ' .. vim.fn.strftime('%T') .. ', with code: ' .. obj.code)
      print([['stack build' finished with code: ]] .. obj.code .. ' in ' .. duration .. 's')

      parser:set_diagnostics(ns_id)
    end)()

    for i, job in ipairs(build_jobs) do
      if job.pid == pid then
        table.remove(build_jobs, i)
      end
    end
  end

  local function on_stderr(err, data)
    assert(not err, err)
    if data then
      if line_leftover then
        data = line_leftover .. data
        line_leftover = nil
      end

      if #data > 0 then
        local lines = vim.split(data, "\n")

        if data[-1] ~= '\n' then
          -- incomplete line?
          line_leftover = lines[#lines]
          table.remove(lines, #lines)
        end

        for _, line in ipairs(lines) do
          parser:parse_build_output_line(line)
        end

      end

    else
      -- output finished

      if line_leftover then
          parser:parse_build_output_line(line_leftover)
      end

    end
  end

  vim.diagnostic.reset(ns_id, nil)

  qf_list_add_one(table.concat(cmd_args, ' '))
  local sys_obj = vim.system(cmd_args, { text = true, stderr = on_stderr, cwd = wd, }, on_exit)
  job_start = vim.uv.hrtime()
  table.insert(build_jobs, sys_obj)

  pid = sys_obj.pid
  qf_list_add_one('Job started at ' .. vim.fn.strftime('%T') .. ', PID: ' .. sys_obj.pid)
end


M.fs_event_handle = nil

M.watch_ghci_output = function (path)
  if fs_event_handle == nil then
    M.fs_event_handle = vim.uv.new_fs_event()
  else
    vim.uv.fs_event_stop(M.fs_event_handle)
  end

  local parse_output_file = function (filename, f)
    if f == nil then
      f = io.open(filename, "rb")
    end

    if f == nil then
        vim.notify("Cannot open file: " .. filename)
    else
      local output = f:read("*a")
      f:close()

      if vim.startswith(output, 'All good') then
          vim.fn.setqflist({}, 'r')
          vim.diagnostic.reset(ns_id, nil)
          qf_list_add_one(output)
          vim.notify('All good', vim.log.INFO)

      else
        if output == '' then
            vim.notify('output is empty', vim.log.INFO)
        end

          vim.fn.setqflist({}, 'r')
          vim.diagnostic.reset(ns_id, nil)

          vim.notify("updated output from file: " .. filename)
          local parser = GhcOutputParser:new { sync_to_qf = true }
          parser:parse_build_output_whole(output)
          parser:set_diagnostics(ns_id)
      end
    end
  end

  local event_cb = function(err, filename, events)
    vim.schedule_wrap(function ()
        if err then
          vim.notify(err, vim.log.ERROR)
        else
          -- delay a little while to wait full content written to the file?
          vim.uv.sleep(100)
          parse_output_file(filename)
        end
    end)()
  end

  vim.uv.fs_event_start(M.fs_event_handle, path, {}, event_cb)

  -- parse output file immediately
  local f = io.open(path, "rb")
  if f then
    parse_output_file(path, f)
  end
end


M.unwatch_ghci_output = function ()
  if fs_event_handle then
    vim.uv.fs_event_stop(M.fs_event_handle)
    vim.notify("Watching stopped.")
  end
end


M.create_user_command_for_watching = function ()
  vim.api.nvim_create_user_command('GhcidWatchOutput',
      function (args)
        local filename = "ghcid-output.txt"
        if #args.fargs > 0 then
          filename = args.fargs[1]
        end

        M.watch_ghci_output(filename)
      end,
      { nargs = '?',
        complete = 'file',
        desc = 'Watch ghcid generated output file, default to "ghcid-output.txt".'
      })

  vim.api.nvim_create_user_command('GhcidUnwatchOutput', M.unwatch_ghci_output,
      { nargs = 0,
        desc = 'Stop watching ghcid generated output file.'
      })
end

M.ns_id = ns_id
M.GhcOutputParser = GhcOutputParser

return M
