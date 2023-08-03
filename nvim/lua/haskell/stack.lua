local M = {}

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


-- line format: filename:error_span_str: severity
local function parse_diagnostics_beginning(line, log)
  local row, col, end_row, end_col
  local filename, severity

  local function log_error(err_msg)
    if log then log:error(line .. ": " .. err_msg) end
  end

  line = strip_prompt_prefix(line)
  if vim.trim(line) == '' then return end

  local filename_and_error_span_str, severity_str = string.match(line, '^(/.+): (%w+):')
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

  return filename, severity, row, col, end_row, end_col
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

local function qf_list_add_one(line)
  local function doit ()
    vim.fn.setqflist( { { text = line } }, 'a' )
  end

  if vim.in_fast_event() then
    vim.schedule_wrap(doit)()
  else
    doit()
  end
end


local StackBuildParser = {}

function StackBuildParser:new(init_obj)
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


function StackBuildParser:append_qf_line(line)
  if self.sync_to_qf then
    qf_list_add_one(line)
  end
end


function StackBuildParser:parse_output_other_line(line)
  self:append_qf_line(line)

  if other_normal_message(line) then
    return
  end
  if self.log then self.log:debug('unrecognized line: ' .. line) end
  table.insert(self.unrecognized_list, line)
end


function StackBuildParser:try_parse_output_final_summary(line)
  if not self.stack_summary_msg_started then
    local msg = string.match(line, '^Error: %[S%-%d+%]')
    if msg == nil then
      self:parse_output_other_line(line)
    else
      self:append_qf_line(line)
      self.stack_summary_msg_started = true
      table.insert(self.stack_summary_msg, msg)
    end
  else
    local msg = parse_indented_message_line(line)
    if msg ~= nil then
      self:append_qf_line(line)
      table.insert(self.stack_summary_msg, msg)
    else
      self:parse_output_other_line(line)
    end
  end
end


function StackBuildParser:parse_build_output_line(line)
  if self.diag == nil then
    -- looking for a diagnostic message beginning
    local filename, severity, row, col, end_row, end_col = parse_diagnostics_beginning(line, self.log)
    if filename ~= nil and severity ~= nil and row ~= nil and col ~= nil then
      self.diag = { row = row, col = col, end_row = end_row, end_col = end_col, filename = filename, severity = severity,
                    -- be compatible with diagnostic-structure
                    -- caution: missing 'bufnr'
                    lnum = row, end_lnum = end_row,
                  }
      self.msg_lines = {}
      self:append_qf_line(line)
    else
      self:try_parse_output_final_summary(line)
    end
  else
    -- looking for a diagnostic message content
    local msg = parse_indented_message_line(line)
    if msg ~= nil then
      -- ignore diagnostic message content, because it is too long, user should use diagnostics to read it
      -- self:append_qf_line(line)
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
      self.diag = nil

      self:try_parse_output_final_summary(line)
    end
  end
end


function StackBuildParser:parse_build_output_whole(output)
  local lines = vim.split(output, "\n")

  for _, line in ipairs(lines) do
    self:parse_build_output_line(line)
  end
end


-- only copy unrecognized messages and summary messages
function StackBuildParser:set_quickfix_messages()
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


function StackBuildParser:set_diagnostics(ns_id)
  local bufnr_diags = {}

  for _, diag in ipairs(self.diags) do
    if diag.bufnr == nil then
      diag.bufnr = vim.fn.bufnr( diag.filename, true )
    end

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


M.make_start_build_args = function ()
  local args = {
              "build", "--fast",
              "--ghc-options", "-fno-diagnostics-show-caret",
              "--ghc-options", "-fdefer-diagnostics",
              "--ghc-options", "-fdiagnostics-color=never",
              "--ghc-options", "-ferror-spans",
            }

  local f = io.open("stack-diagnostic-flags.txt", "rb")
  if f == nil then
      table.insert(args, ".")
  else
    for line in f:lines() do
      if line:find('#', 1, true) ~= 1 then
        table.insert(args, line)
      end
    end
    f:close()
  end

  return args
end


local namespace_name = 'stack-build'
local ns_id = vim.api.nvim_create_namespace(namespace_name)
local build_jobs = {}

-- create a new job to call 'stack build'
M.start_build_job = function ()
  local cmd_args = M.make_start_build_args()
  table.insert(cmd_args, 1, "stack")

  local parser = StackBuildParser:new { sync_to_qf = true }

  local line_leftover = nil
  local pid = nil

  local function on_exit(obj)
    print([['stack build' finished with code: ]] .. obj.code)

    vim.schedule_wrap(function()
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

  vim.fn.setqflist({}, 'r')
  vim.diagnostic.reset(ns_id, nil)

  local sys_obj = vim.system(cmd_args, { text = true, stderr = on_stderr, }, on_exit)
  table.insert(build_jobs, sys_obj)

  pid = sys_obj.pid
  qf_list_add_one([['stack build' started, PID: ]] .. sys_obj.pid)
end


M.ns_id = ns_id
M.StackBuildParser = StackBuildParser

return M
