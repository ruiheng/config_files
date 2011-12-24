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
