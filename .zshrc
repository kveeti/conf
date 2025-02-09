alias dots='/usr/bin/git --git-dir=$HOME/.dots/ --work-tree=$HOME'
alias lg=lazygit
alias v=nvim
alias w='curl -s wttr.in'

export VISUAL=v
export EDITOR="$VISUAL"

function f() {
  local selected_dir
  selected_dir=$(find ~/Developer ~/Documents -mindepth 0 -maxdepth 2 -type d | fzf)
  if [[ -n "$selected_dir" ]]; then
    cd "$selected_dir"
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

