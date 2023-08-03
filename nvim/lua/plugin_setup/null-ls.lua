local M = {}


-- a flag that enables `stack_build` source
M.stack_build_enabled = false

M.last_run = 0

M.config = function(_, _)
    local null_ls = require('null-ls')
    local helpers = require('null-ls.helpers')
    local log = require("null-ls.logger")
    local methods = require('null-ls.methods')
    local stack = require('haskell.stack')

    local stack_build = {
      name = "my-haskell-stack",
      filetypes = { "haskell", "cabal" },
      method = null_ls.methods.DIAGNOSTICS_ON_SAVE,

      generator = helpers.generator_factory{
        method = null_ls.methods.DIAGNOSTICS_ON_SAVE,  -- not the same as methods.lsp.DID_SAVE
        multiple_files = true,
        command = "stack",
        args = stack.make_start_build_args,

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

          local log = require("null-ls.logger")
          local parser = stack.StackBuildParser:new({ log = log })
          parser:parse_build_output_whole(output)
          parser:set_quickfix_messages()

          local results = parser.diags

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
