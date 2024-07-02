# if not running interactively, don't do anything
[[ $- != *i* ]] && return

# aliases
alias dots='/usr/bin/git --git-dir=$HOME/.dots/ --work-tree=$HOME'

# prompt
PS1='[\u@\h \W]\$ '

# sway wrapped with ssh-agent
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" == "/dev/tty1" ]; then
  ssh-agent sway
fi
