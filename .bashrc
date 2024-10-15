# if not running interactively, don't do anything
[[ $- != *i* ]] && return

# prompt
PS1='[\u@\h \W]\$ '

# sway wrapped with ssh-agent
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" == "/dev/tty1" ]; then
  ssh-agent sway
fi

# aliases
alias dots='/usr/bin/git --git-dir=$HOME/.dots/ --work-tree=$HOME'
alias bz='bluetoothctl'
alias lz='lazygit'

# scripts
export SCRIPTS_DIR="$HOME/bin"
export PATH=$SCRIPTS_DIR:$PATH
bind -x '"\C-f": tmux-sessionizer'

# pnpm
export PNPM_HOME="/home/veeti/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
