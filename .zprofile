export PATH="$HOME/Library/pnpm:$PATH"
. "$HOME/.cargo/env"
eval "$(/opt/homebrew/bin/brew shellenv)"

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init.zsh 2>/dev/null || :

autoload -Uz compinit
compinit

