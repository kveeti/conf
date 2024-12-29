alias dots='/usr/bin/git --git-dir=$HOME/.dots/ --work-tree=$HOME'
alias lz=lazygit
alias d='cd ~/Developer'
alias v=nvim
alias ls='ls -la'
bindkey -s ^f "tmux-sessions\n"

enc() {
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

    tar -cf - "$1" | zstd -T0 | pv -c | gpg --no-symkey-cache --batch --yes --passphrase "$passphrase1" --symmetric --cipher-algo AES128 --compress-level 0 -o "${1}.tar.zst.gpg"
    echo "done"
}

dec() {
    local file="$1"
    if [[ -z "$file" ]]; then
        echo "usage: decrypt_tar <file.tar.zst.gpg>"
        return 1
    fi

    local tar_name=$(basename "$file" .tar.zst.gpg)
    if [[ -e "$tar_name" ]]; then
        echo "error: '$tar_name' already exists. Aborting."
        return 1
    fi

    local passphrase
    echo -n "enter passphrase: "
    read -s passphrase
    echo

    gpg --no-symkey-cache --batch --passphrase "$passphrase" --decrypt "$file" | zstd -d | pv -c | tar -xf -
    echo "done"
}

export PATH="$HOME/.scripts:$PATH"
export PATH="$HOME/Library/pnpm:$PATH"
. "$HOME/.cargo/env"
export VISUAL=nvim
export EDITOR="$VISUAL"
