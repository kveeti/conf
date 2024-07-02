# if not running interactively, don't do anything
[[ $- != *i* ]] && return

# aliases
alias dots='/usr/bin/git --git-dir=$HOME/.dots/ --work-tree=$HOME'

# prompt
PS1='[\u@\h \W]\$ '

# sway
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
  exec sway
fi
