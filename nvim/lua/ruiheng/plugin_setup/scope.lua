local M = {}

M.config = function(_, opts)
    require('scope').setup(opts)
    require('telescope').load_extension('scope')

    -- hack to fix: when trying to close last buffer but find unsaved buffer
    -- nvim will show the unsaved buffer, but scope do not consider this situation.
    --[[
    vim.api.nvim_create_autocmd('BufEnter', {
      callback = function ()
        local buf_type = vim.api.nvim_get_option_value("buftype", { buf = 0 })
        if buf_type == '' and #vim.fn.getbufinfo({bufloaded = true}) == 1 then
          require('scope.core').on_tab_new_entered()
        end
      end
    })
    --]]
end

return M
