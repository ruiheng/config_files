# for GIT
if [ -r "$HOME/.git-completion.sh" ]; then
    source "$HOME/.git-completion.sh"
fi
PS1='[\u@\h \W$(__git_ps1 " (%s)")]\$ '
