alias dots='/usr/bin/git --git-dir=$HOME/.dots/ --work-tree=$HOME'
alias lg=lazygit
alias v=nvim
alias w='curl -s wttr.in'

export VISUAL=$(which nvim)
export EDITOR="$VISUAL"

export PATH="$PATH:$HOME/.bin"

function f() {
    local selected_dir
    selected_dir=$(find ~/Developer ~/Documents -mindepth 0 -maxdepth 2 -type d | fzf)
    if [[ -n "$selected_dir" ]]; then
	cd "$selected_dir"
    fi
}

# tmux sessions
function t() {
    selected_dir=$(find ~/Developer ~/Documents -mindepth 0 -maxdepth 2 -type d | fzf)
    if [[ -z "$selected_dir" ]]; then
        return
    fi

    local session_name=$(basename "$selected_dir")
    local is_tmux_running=$(pgrep tmux)
    local is_in_tmux=$TMUX

    if [[ -z $is_in_tmux ]] && [[ -z $is_tmux_running ]]; then
	tmux new-session -ds "$session_name" -c "$selected_dir"
        tmux attach-session -t "$session_name"
        return
    fi

    if ! tmux has-session -t "$session_name" 2>/dev/null ; then
	tmux new-session -ds "$session_name" -c "$selected_dir"
    fi

    if [[ -z $is_in_tmux ]]; then
        tmux attach-session -t "$session_name"
    else
        tmux switch-client -t "$session_name"
    fi
}

function kp() {
    local port="$1"

    kill -9 $(lsof -ti:$port)
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

str() {
    url="$1"
    output="$2"
    format="bv*[height<=2160]+ba/b[height<=2160]"

    if [[ -z "$url" ]]; then
        echo "Usage: str <url> [output]"
        return 1
    fi

    yt-dlp -f "$format" --quiet --no-warnings --downloader ffmpeg -f "$format" -o - "$url" | mpv --hwdec=auto-safe - &
    stream_pid=$!

    if [[ -n "$output" ]]; then
        yt-dlp --quiet --no-warnings --downloader ffmpeg -f "$format" "$url" -o "$output" &
        download_pid=$!
    fi

    trap 'kill $stream_pid $download_pid 2>/dev/null; return 0' SIGINT

    wait
}

# pnpm
export PNPM_HOME="/Users/veetik/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
