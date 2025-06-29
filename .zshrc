alias dots="/usr/bin/git --git-dir=$HOME/.dots/ --work-tree=$HOME"

alias lg="lazygit"
alias e="${EDITOR}"
alias E="sudo e"
alias ls="eza -la"
alias b="open \"/Applications/Brave Browser.app\" --args --disable-smooth-scrolling"
bindkey -e

alias gs="git status --short"

function f() {
    local selected_dir
    selected_dir=$(find ~/code -mindepth 0 -maxdepth 3 -type d | fzf)
    if [[ -n "$selected_dir" ]]; then
        cd "$selected_dir"
    fi
}

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

eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(starship init zsh)"
eval "$(fnm env --use-on-cd --shell zsh)"
