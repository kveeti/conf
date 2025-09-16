bindkey -e

alias dots="/usr/bin/git --git-dir=$HOME/.dots/ --work-tree=$HOME"

EDITOR=nvim
alias e=$EDITOR

alias ls='eza -la'
alias f='cd "$(find ~/code ~/things -type d -maxdepth 7 -print0 | fzf --read0)"'

alias k=kubectl

alias gs='git status --short'
alias gl='git log --oneline --decorate --color'

eval "$(fnm env --use-on-cd --shell zsh)"

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
