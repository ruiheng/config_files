# for GIT
if [ -r "$HOME/.git-completion.sh" ]; then
    source "$HOME/.git-completion.sh"
fi
PS1='[\u@\h \W$(__git_ps1 " (%s)")]\$ '

export PATH="$HOME/.local/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
