local M = {} 
M.config = function()
  require('codecompanion').setup{
    strategies = {
      chat = {
        adapter = "openrouter_gpt_oss_20b",
      },
      inline = {
        adapter = "openrouter_gpt_oss_20b",
      },
      cmd = {
        adapter = "openrouter_gpt_oss_20b",
      },
    },
    -- NOTE: The log_level is in `opts.opts`
    opts = {
      log_level = "DEBUG",
    },
    adapters = {
      http = {
        opts = {
            allow_insecure = true,
            proxy = "socks5://vm-host:7890",
        },
        openrouter_gpt_oss_20b = function()
          return require("codecompanion.adapters").extend("openai_compatible", {
            name = "openrouter_gpt_oss_20b",
            env = {
              api_key = "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",
              url = "https://openrouter.ai/api",
              chat_url = "/v1/chat/completions",
            },
            schema = {
              model = {
                default = "openai/gpt-oss-20b",
              },
            },
          })
        end
      }
    }
  }
end

return M
