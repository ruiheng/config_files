local M = {}

M.config = function ()
  local lspconfig = require('lspconfig')

  local on_attach = function(client, bufnr)
    if client.name == 'ruff_lsp' then
      -- Disable hover in favor of Pyright
      client.server_capabilities.hoverProvider = false
    end
  end

  lspconfig.ruff.setup {
    -- on_attach = on_attach,
  }

  lspconfig.pyright.setup { }

  lspconfig.ts_ls.setup {}

  -- use either this or haskell-tools
  -- lspconfig.hls.setup {}
end


return M
