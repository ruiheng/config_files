local M = {}

M.config = function ()
  vim.o.fillchars = [[eob: ,fold: ,foldopen:,foldsep: ,foldclose:]]
  vim.o.foldcolumn = '1' -- '0' is not bad
  vim.o.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
  vim.o.foldlevelstart = 99
  vim.o.foldnestmax = 4
  vim.o.foldenable = false

  -- Using ufo provider need remap `zR` and `zM`. If Neovim is 0.6.1, remap yourself
  vim.keymap.set('n', 'zR', require('ufo').openAllFolds)
  vim.keymap.set('n', 'zM', require('ufo').closeAllFolds)

  local handler = function(virtText, lnum, endLnum, width, truncate)
      local newVirtText = {}
      local suffix = ('  %d '):format(endLnum - lnum)
      local sufWidth = vim.fn.strdisplaywidth(suffix)
      local targetWidth = width - sufWidth
      local curWidth = 0
      for _, chunk in ipairs(virtText) do
          local chunkText = chunk[1]
          local chunkWidth = vim.fn.strdisplaywidth(chunkText)
          if targetWidth > curWidth + chunkWidth then
              table.insert(newVirtText, chunk)
          else
              chunkText = truncate(chunkText, targetWidth - curWidth)
              local hlGroup = chunk[2]
              table.insert(newVirtText, {chunkText, hlGroup})
              chunkWidth = vim.fn.strdisplaywidth(chunkText)
              -- str width returned from truncate() may less than 2nd argument, need padding
              if curWidth + chunkWidth < targetWidth then
                  suffix = suffix .. (' '):rep(targetWidth - curWidth - chunkWidth)
              end
              break
          end
          curWidth = curWidth + chunkWidth
      end
      table.insert(newVirtText, {suffix, 'MoreMsg'})
      return newVirtText
  end

  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities.textDocument.foldingRange = {
      dynamicRegistration = false,
      lineFoldingOnly = true
  }
  local language_servers = vim.lsp.get_clients() -- or list servers manually like {'gopls', 'clangd'}
  for _, ls in ipairs(language_servers) do
      require('lspconfig')[ls].setup({
          capabilities = capabilities
          -- you can add other fields for setting up lsp server in this table
      })
  end

  require('ufo').setup({
    provider_selector = function(bufnr, filetype, buftype)
        return { 'treesitter', }
      end,
    fold_virt_text_handler = handler,
    close_fold_kinds_for_ft = {
            default = {'imports', 'comment'},
            json = {'array'},
            c = {'comment', 'region'}
        },
  })

  -- Option 3: treesitter as a main provider instead
  -- Only depend on `nvim-treesitter/queries/filetype/folds.scm`,
  -- performance and stability are better than `foldmethod=nvim_treesitter#foldexpr()`
  -- require('ufo').setup({
  --   open_fold_hl_timeout = 100,
  --   provider_selector = function(bufnr, filetype, method)
  --     return { 'treesitter', 'indent' }
  --   end,
  -- })
end

return M
