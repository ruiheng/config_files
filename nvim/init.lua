-- 定义函数设置全局变量
local function g_set(name, value)
    vim.g[name] = value
end

-- 检查并设置 quick_mode
if vim.g.quick_mode == nil then
    g_set('quick_mode', 0)
end

-- 检查并设置 haskell_mode
if vim.g.haskell_mode == nil then
    g_set('haskell_mode', 0)

    if vim.g.quick_mode == 0 then
        if vim.fn.filereadable(vim.fn.expand('*.cabal')) == 1 or vim.fn.filereadable(vim.fn.expand('*.hs')) == 1 then
            g_set('haskell_mode', 1)
        end
    end
end

-- 检查并设置 rust_mode
if vim.g.rust_mode == nil then
    g_set('rust_mode', 0)

    if vim.g.quick_mode == 0 then
        if vim.fn.filereadable('Cargo.toml') == 1 or vim.fn.filereadable(vim.fn.expand('*.rs')) == 1 then
            g_set('rust_mode', 1)
        end
    end
end

-- 检查并设置 enable_lsp
if vim.g.enable_lsp == nil then
    g_set('enable_lsp', vim.g.haskell_mode == 1 or vim.g.rust_mode == 1)
end

---------------- options, key mappings -------------

vim.g.mapleader = " " -- make sure to set `mapleader` before lazy
vim.g.maplocalleader = ","

vim.cmd.filetype("on")
vim.cmd.filetype("plugin on")

vim.opt.encoding = "utf-8"
vim.o.hidden = true
vim.o.expandtab = true
vim.o.showcmd = true
vim.o.title = true
vim.o.titlestring = '%f %{fnamemodify(getcwd(), ":~")} -- NVIM'
vim.o.mouse = 'a'
vim.o.shortmess = vim.o.shortmess .. 'c'
vim.o.sessionoptions = vim.o.sessionoptions .. ',globals'
vim.o.wop = 'pum'
vim.o.cuc = true
vim.o.cul = true
vim.o.number = true
vim.o.relativenumber = true

for i = 1, 9 do
    vim.api.nvim_set_keymap('n', ','..i, ':tabn '..i..'<CR>', {noremap = true, silent = true})
end

-- about selecting and pasting text
vim.api.nvim_set_keymap('v', '<F2>', '"0p', {noremap = true})
vim.api.nvim_set_keymap('n', '<F2>', 'viw"0p', {noremap = true})

-- see: http://vim.wikia.com/wiki/Selecting_your_pasted_text
vim.cmd("nnoremap <expr> <leader>vp '`[' . strpart(getregtype(), 0, 1) . '`]'")


-- invoke 'stack build' command, set diagnostics and quickfix
vim.keymap.set('n', '<leader>bs',
    function()
      local errs = require('ruiheng').save_all_buffers()
      if #errs > 0 then
        print('some buffer not saved: ' .. vim.inspect(errs))
      else
        require('ruiheng.haskell.ghc').start_build_job()
        require('ruiheng.quickfix').open_quickfix_win_but_not_focus()
      end
    end ,
    {noremap = true, silent = true}
  )

-- create GhcidWatchOutput and GhcidUnwatchOutput
require('ruiheng.haskell.ghc').create_user_command_for_watching()

-- run a command (usually long-running) in a terminal and show
-- use <localleader>x to close the terminal window (but keep the command running)
-- use <localleader>t to cycle through running terminals
vim.api.nvim_create_user_command("ToggleTerminalRun",
  function (args)
    if #args.fargs == 0 then
      print('usage: ToggleTerminalRun [command] [args...]')
      return
    end
    require('ruiheng').toggle_terminal_run(args.fargs)
  end,
  { nargs = "+",
    complete = 'file_in_path',
    desc = [[Run a command in a terminal.]],
  })

-- resume the last terminal window that was created by ToggleTerminalRun
vim.keymap.set('n', '<leader>R',
    function()
      require('ruiheng').toggle_terminal_run()
    end ,
    {noremap = true, silent = true, desc = 'resume last terminal that was created by ToggleTerminalRun'}
  )

vim.keymap.set('n', '<leader>lg',
    function()
      require('ruiheng').toggle_terminal_run('lazygit')
    end ,
    {noremap = true, silent = true, desc = 'run lazygit in a terminal'}
  )

vim.keymap.set('n', '<leader>tr', ':ToggleTerminalRun ',
    {noremap = true, desc = 'invoke ToggleTerminalRun'}
  )

function my_set_local_tab_stop(n)
  vim.opt_local.tabstop = n
  vim.opt_local.softtabstop = n
  vim.opt_local.shiftwidth = n
end

for _, n in ipairs({ 2, 4, 8 }) do
    vim.keymap.set('n', '<leader>t'..n, function () my_set_local_tab_stop(n) end, {noremap = true, })
  end


-- 定义 MySetWigForHaskell 函数
vim.api.nvim_exec([[
  function MySetWigForHaskell()
    set wig+=*.o,*.hi,*.dyn_hi,*.dyn_o,*/dist/*,cabal.sandbox.config,*.keter
  endfunction
]], false)


if vim.g.haskell_mode == 1 then
    vim.api.nvim_exec('call MySetWigForHaskell()', false)
end

-- Toggle cursorline and cursorcolumn
vim.api.nvim_set_keymap('n', '<leader>cc', ':set cuc! cul!<CR>', {noremap = true, silent = true})

-- Toggle number display
vim.api.nvim_set_keymap('n', '<leader>n', ':set nu! rnu!<CR>', {noremap = true, silent = true})

-- Toggle paste mode
-- vim.api.nvim_set_keymap('n', '<leader>pa', ':set paste!<CR>', {noremap = true})


---------------- lazy.nvim plugins -------------

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end


vim.opt.rtp:prepend(lazypath)
require('ruiheng.lazy-setup')

vim.o.bg = 'dark'
-- vim.g.everforest_background = 'soft'
-- vim.g.everforest_better_performance = 1
-- vim.cmd("colorscheme everforest")
-- vim.cmd("colorscheme kanagawa")
-- vim.cmd("colorscheme gruvbox")
vim.cmd("colorscheme tokyonight")


vim.keymap.set('n', '<leader>do', vim.diagnostic.open_float, { noremap = true, })
vim.keymap.set('n', '<leader>d[', vim.diagnostic.goto_prev, { noremap = true, })
vim.keymap.set('n', '<leader>d]', vim.diagnostic.goto_next, { noremap = true, })
vim.keymap.set('n', '<leader>dpe', function() vim.diagnostic.goto_prev({ severity = { min = vim.diagnostic.severity.WARN } }) end, { noremap = true, })
vim.keymap.set('n', '<leader>dne', function () vim.diagnostic.goto_next({ severity = { min = vim.diagnostic.severity.WARN } }) end, { noremap = true, })
-- If you don't want to use the telescope plug-in but still want to see all the errors/warnings, comment out the telescope line and uncomment this:
-- vim.api.nvim_set_keymap('n', '<leader>dd', '<cmd>lua vim.diagnostic.setloclist()<CR>', { noremap = true, silent = true })

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'haskell', 'html', 'lua', 'vim', },
  callback = function ()
    local opt_local = vim.opt_local
    opt_local.expandtab = true
    opt_local.cuc = true
    opt_local.cul = true
    opt_local.number = true
    opt_local.relativenumber = true

    -- for unknown reason, 'syntax' optoin is empty when opening haskell files ('filetype' has been detected correctly)
    vim.opt_local.syntax = 'ON'

    opt_local.foldmethod = 'expr'
    opt_local.foldexpr = 'nvim_treesitter#foldexpr()'
    opt_local.foldenable = false

    my_set_local_tab_stop(2)
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'javascript', },
  callback = function ()
    local opt_local = vim.opt_local
    opt_local.expandtab = true
    opt_local.cuc = true
    opt_local.cul = true
    opt_local.number = true
    opt_local.relativenumber = true

    -- for unknown reason, 'syntax' optoin is empty when opening haskell files ('filetype' has been detected correctly)
    vim.opt_local.syntax = 'ON'

    -- opt_local.foldmethod = 'expr'
    -- opt_local.foldexpr = 'nvim_treesitter#foldexpr()'
    opt_local.foldenable = false

    my_set_local_tab_stop(4)
  end,
})


vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'python' },
  callback = function ()
    vim.opt_local.expandtab = true
    my_set_local_tab_stop(4)
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  pattern = { '*.hamlet' },
  callback = function ()
    vim.opt_local.expandtab = true
    my_set_local_tab_stop(2)
  end,
})

vim.api.nvim_create_autocmd('BufFilePost', {
  pattern = { '*.hamlet' },
  callback = function ()
    vim.opt_local.expandtab = true
    my_set_local_tab_stop(2)
  end,
})


vim.api.nvim_create_user_command("DiagnosticReset", function()
    vim.diagnostic.reset()
end, { desc = [[Reset diagnostics globally.]] })


-- WORKAROUND: telescope.nvim may open a file buffer in insert mode
vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave" }, {
  callback = function(event)
    if vim.bo[event.buf].filetype == "TelescopePrompt" then
      vim.api.nvim_exec2("silent! stopinsert!", {})
    end
  end
})
