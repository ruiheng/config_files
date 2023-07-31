local M = {}


local severity_table = {
  error = 1,
  warning = 2,
  -- info = 3,
  -- hint = 4,
}

local function strip_some_prefix(line)
  if line == "" then return line end

  -- may contain prefix like: xxx-lib > ....
  local line1 = string.match(line, '^[%w-]+%s*> (.+)$')
  if line1 ~= nil then line = line1 end

  return line
end

-- line format: filename:error_span_str: severity
local function parse_diagnostics_beginning(line)
  local log = require("null-ls.logger")
  local row, col, end_row, end_col
  local filename, severity

  local function log_error(err_msg)
    log:error(line .. ": " .. err_msg)
  end

  line = strip_some_prefix(line)
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

  --[[
  log:debug('filename: ' .. (filename or "nil"))
  log:debug('severity: ' .. (severity or "nil"))
  log:debug('row: ' .. (row or "nil"))
  log:debug('col: ' .. (col or "nil"))
  --]]
  return filename, severity, row, col, end_row, end_col
end


-- line that begins with 4 spaces
local function parse_indented_message_line(line)
  line = strip_some_prefix(line)
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
  '^Building library for .+',
  '^Installing library in .+',
  '^Installing executable in .+',
  '^copy/register',
  '^Registering library in .+',
  '^Compiling .+',
  '^Linking .+',
}

local function other_normal_message(line)
  if line == "" then return true end

  line = strip_some_prefix(line)

  line1 = string.match(line, '^%[%s*%d+ of%s+%d+%]%s+([^%s].+)$')
  if line1 ~= nil then line = line1 end

  for _, p in ipairs(other_normal_message_patterns) do
    if string.match(line, p) then return true end
  end

  -- require("null-ls.logger"):debug('unrecognized line: ' .. line)
end


local function parse_ghc_build_output(output)
  local log = require("null-ls.logger")
  local lines = vim.split(output, "\n")
  local diags = {}
  local diag = nil
  local msg_lines = {}
  local stack_summary_msg = nil

  local function handle_other_line(line)
    if other_normal_message(line) then
      return
    end
    log:debug('unrecognized line: ' .. line)
  end

  local function try_stack_final_summary(line)
    if stack_summary_msg == nil then
      stack_summary_msg = string.match(line, '^Error: %[S%-%d+%]')
      if stack_summary_msg == nil then
        handle_other_line(line)
      end
    else
      local msg = parse_indented_message_line(line)
      if msg ~= nil then
        -- ignore
      else
        handle_other_line(line)
      end
    end
  end

  for _, line in ipairs(lines) do
    if diag == nil then
      -- looking for a diagnostic message beginning
      local filename, severity, row, col, end_row, end_col = parse_diagnostics_beginning(line)
      if filename ~= nil and severity ~= nil and row ~= nil and col ~= nil then
        diag = { row = row, col = col, end_row = end_row, end_col = end_col, filename = filename, severity = severity }
        msg_lines = {}
      else
        try_stack_final_summary(line)
      end
    else
      -- looking for a diagnostic message
      local msg = parse_indented_message_line(line)
      if msg ~= nil then
        -- log:debug('got msg line: ' .. msg)
        table.insert(msg_lines, msg)
      else
        if #msg_lines == 0 then
          log:error('should be a message:' .. line)
          log:error('should be a message:' .. strip_some_prefix(line))
        end

        -- end of diagnostic message
        diag.message = table.concat(msg_lines, "\n")
        table.insert(diags, diag)
        diag = nil

        try_stack_final_summary(line)
      end
    end
  end

  return diags
end

-- a flag that enables `stack_build` source
M.stack_build_enabled = false

M.last_run = 0

M.config = function(_, _)
    local null_ls = require('null-ls')
    local helpers = require('null-ls.helpers')
    local log = require("null-ls.logger")
    local methods = require('null-ls.methods')

    local stack_build = {
      name = "my-haskell-stack",
      filetypes = { "haskell", "cabal" },
      method = null_ls.methods.DIAGNOSTICS_ON_SAVE,

      generator = helpers.generator_factory{
        method = null_ls.methods.DIAGNOSTICS_ON_SAVE,  -- not the same as methods.lsp.DID_SAVE
        multiple_files = true,
        command = "stack",

        args = function()
            local args = { "build", "--fast",
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
        end,

        timeout = 100000, -- stack build may take a long time
        check_exit_code = function(code)
            return code <= 1
        end,
        to_stdin = false,
        to_temp_file = false,
        from_stderr = true,
        format = "raw",

        on_output = function(params, done)
          local output = params.output
          if not output then
            return done()
          end

          local results = parse_ghc_build_output(output)
          if (results == nil or #results == 0) then
            print([['stack build' command fininshed.]])
          else
            local errors = 0
            local warnings = 0

            for _, r in ipairs(results) do
              if r.severity == 1 then
                errors = errors + 1
              elseif r.severity == 2 then
                warnings = warnings + 1
              end
            end

            print([['stack build' command fininshed with some diagnostics: ]] .. errors .. [[ errors and ]] .. warnings .. [[ warnings. Total ]] .. #results .. [[ diagnostics.]] )
          end

          return done( results )
        end,

        runtime_condition = function(params)
          if not M.stack_build_enabled then return false end

          if params.lsp_method ~= methods.lsp.DID_SAVE then
            return false
          end

          -- Either LspStop or HlsStop will not stop HLS reliablly. Why?
          --
          -- local lsp_clients = vim.lsp.get_active_clients()
          -- for _, client in ipairs(lsp_clients) do
          --   if client.id ~= params.client_id then
          --     print([[There is other clients active, 'my-stack-build' will not run]])
          --     return
          --     -- log:debug("other client active: " .. client.id)
          --   end
          -- end

          local now = vim.loop.hrtime()
          local diff = (now - M.last_run) / 1000000000
          if diff < 5 then
            log:debug("stack build still running or restart too fast, do nothing.")
            return false
          end
          M.last_run = now

          return true
        end,
      },
    }

    vim.api.nvim_create_user_command("StackBuildStart", function()
      M.stack_build_enabled = true
    end, { desc = [[Enable automatically using 'stack build' to generate diagnostics]] })

    vim.api.nvim_create_user_command("StackBuildStop", function()
      M.stack_build_enabled = false
    end, { desc = [[Disable automatically using 'stack build' to generate diagnostics]] })

    null_ls.setup {
      debug = true,
      name = "my-haskell-stack",
      sources = {
        stack_build,
      },
    }
end

return M
