function zle-line-init zle-keymap-select {
	RPS1="${${KEYMAP/vicmd/-- NORMAL --}/(main|viins)/-- INSERT --}"
	RPS2="$RPS1"
	zle reset-prompt
}
zle -N zle-line-init
zle -N zle-keymap-select

terminfo_down_sc=$terminfo[cud1]$terminfo[cuu1]$terminfo[sc]$terminfo[cud1]
function zle-line-init zle-keymap-select {
	PS1_2="${${KEYMAP/vicmd/-- NORMAL --}/(main|viins)/-- INSERT --}"
	PS1="%{$terminfo_down_sc$PS1_2$terminfo[rc]%}%~ %# "
	zle reset-prompt
}
preexec () { print -rn -- $terminfo[el]; }

set -o vi

autoload -U compinit
compinit

# for GIT
source ~/config_files/git-completion.sh
#PS1='[%n@%m %c$(__git_ps1 " (%s)")]\$ '
