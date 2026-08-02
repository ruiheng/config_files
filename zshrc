export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="spaceship"
bindkey -v
source "$ZSH/custom/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh"

export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    if command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1 \
        && command -v npm >/dev/null 2>&1 && npm --version >/dev/null 2>&1; then
        source "$NVM_DIR/nvm.sh" --no-use
    else
        source "$NVM_DIR/nvm.sh"
    fi
fi

plugins=(git fzf spaceship-vi-mode)
source "$ZSH/oh-my-zsh.sh"

SPACESHIP_PROMPT_ORDER=(${SPACESHIP_PROMPT_ORDER:#char} vi_mode char)
spaceship_vi_mode_enable

# Clean PATH after all tool initializers have run.
typeset -U path PATH
path=("$HOME/.local/bin" ${path:#/usr/local/games})
path=(${path:#/usr/games})
