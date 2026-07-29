export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="spaceship"
bindkey -v
source "$ZSH/custom/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

plugins=(git fzf spaceship-vi-mode)
source "$ZSH/oh-my-zsh.sh"

SPACESHIP_PROMPT_ORDER=(${SPACESHIP_PROMPT_ORDER:#char} vi_mode char)
spaceship_vi_mode_enable

# Clean PATH after all tool initializers have run.
typeset -U path PATH
path=("$HOME/.local/bin" ${path:#/usr/local/games})
path=(${path:#/usr/games})
