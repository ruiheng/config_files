# Neovim with vertical-bufferline aliases
# 在你的 ~/.bashrc 或 ~/.zshrc 中添加以下行来使用这些别名：
# source /home/ruiheng/config_files/nvim/aliases.sh

# 常规 nvim（不加载 vertical-bufferline）
alias nv='nvim'

# 带 vertical-bufferline 的 nvim
alias nvim-vbl='NVIM_ENABLE_VBL=1 nvim'
alias nvb='NVIM_ENABLE_VBL=1 nvim'

# 调试用 nvim（带 vertical-bufferline 和调试信息）
alias nvim-debug='NVIM_ENABLE_VBL=1 NVIM_VBL_DEBUG=1 nvim --cmd "let g:enable_vertical_bufferline=1"'
alias nvd='NVIM_ENABLE_VBL=1 NVIM_VBL_DEBUG=1 nvim --cmd "let g:enable_vertical_bufferline=1"'