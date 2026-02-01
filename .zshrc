bindkey -e

alias dots="/usr/bin/git --git-dir=$HOME/.dots/ --work-tree=$HOME"

EDITOR=nvim
alias e=$EDITOR

alias ls='eza -la'
alias f='cd "$(find ~/code ~/things -maxdepth 7 \( -name "node_modules" -o -name ".git" -o -name "dist" -o -name "build" -o -name "target" \) -prune -o -type d -print0 | fzf --read0)"'

alias k=kubectl
function b() {
    open -a "Brave Browser" --args --disable-smooth-scrolling "$@"
}

alias gs='git status --short'
alias gl='git log --oneline --decorate --color'

enc() {
    local file="$1"
    if [[ -z "$file" ]]; then
        echo "usage: enc <file or dir>"
        return 1
    fi

    local passphrase1 passphrase2
    echo -n "enter passphrase: "
    read -s passphrase1
    echo
    echo -n "confirm passphrase: "
    read -s passphrase2
    echo
    if [[ "$passphrase1" != "$passphrase2" ]]; then
        echo "passphrases do not match. aborting."
        return 1
    fi

    tar -cf - "$file" | zstd -T0 | pv -c | gpg --no-symkey-cache --batch --yes --passphrase "$passphrase1" --symmetric --cipher-algo AES256 --compress-level 0 -o "${file}.tar.zst.gpg"
    echo "done"
}

dec() {
    local file="$1"
    if [[ -z "$file" ]]; then
        echo "usage: dec <file.tar.zst.gpg>"
        return 1
    fi

    local tar_name=$(basename "$file" .tar.zst.gpg)
    if [[ -e "$tar_name" ]]; then
        echo "error: '$tar_name' already exists. aborting."
        return 1
    fi

    local passphrase
    echo -n "enter passphrase: "
    read -s passphrase
    echo

    gpg --no-symkey-cache --batch --passphrase "$passphrase" --decrypt "$file" | zstd -d | pv -c | tar -xf -
    echo "done"
}
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
eval "$(/Users/veeti/.local/bin/mise activate zsh)"

# bun completions
[ -s "/Users/veeti/.bun/_bun" ] && source "/Users/veeti/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

kp() {
    if [ -z "$1" ]; then
        echo "Usage: killport <port_number>"
        return 1
    fi

    PORT=$1
    PIDS=$(lsof -ti tcp:$PORT)

    if [ -z "$PIDS" ]; then
        echo "No process found running on port $PORT"
    else
        echo "Killing process(es) on port $PORT: $PIDS"
        echo "$PIDS" | xargs kill -9
    fi
}

# pnpm
export PNPM_HOME="/Users/veeti/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# tmux sessionizer
function t() {
    if [[ $# -eq 1 ]]; then
        selected=$1
    else
        selected=$(find ~/code ~/things -maxdepth 7 \( -name "node_modules" -o -name ".git" -o -name "dist" -o -name "build" -o -name "target" \) -prune -o -type d -print0 | fzf --read0)
    fi

    if [[ -z $selected ]]; then
        exit 0
    fi

    selected_name=$(basename "$selected" | tr . _)
    tmux_running=$(pgrep tmux)

    if [[ -z $TMUX ]] && [[ -z $tmux_running ]]; then
        tmux new-session -s $selected_name -c $selected
        exit 0
    fi

    if ! tmux has-session -t=$selected_name 2> /dev/null; then
        tmux new-session -ds $selected_name -c $selected
    fi

    if [[ -z $TMUX ]]; then
        tmux attach -t $selected_name
    else
        tmux switch-client -t $selected_name
    fi
}
# tmux sessionizer
