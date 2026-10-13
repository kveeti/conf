{ pkgs, pkgs-unstable, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.name = "Veeti K";
      user.email = "veeti@veetik.com";
      user.signingkey = "2EC84960C7C4E4059A255048111E474490913E21";
      gpg.format = "openpgp";
      commit.gpgsign = true;
    };
  };

  programs.zsh.enable = true;
  programs.zsh.initContent = ''
    mosh() {
      local theme=light
      if [[ "$(uname -s)" == Darwin ]] && defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
        theme=dark
      fi
      command mosh --server="env NVIM_THEME=$theme mosh-server" "$@"
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

      tar -cf - "$file" | zstd -T0 | pv -c | gpg --no-symkey-cache --batch --yes --passphrase "$passphrase1" --symmetric --cipher-algo AES256 --compress-level 0 -o "$file.tar.zst.gpg"
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

    function t() {
      local selected
      if [[ $# -eq 1 ]]; then
        selected="$1"
      else
        selected=$(find ~/code -maxdepth 7 \\( -name "node_modules" -o -name ".git" -o -name "dist" -o -name "build" -o -name "target" \\) -prune -o -type d -print0 | fzf --read0)
      fi

      if [[ -z $selected ]]; then
        return 0
      fi

      local selected_name=$(basename "$selected" | tr . _)
      if [[ -z $TMUX ]] && ! tmux info >/dev/null 2>&1; then
        tmux new-session -s "$selected_name" -c "$selected"
        return 0
      fi

      if ! tmux has-session -t="$selected_name" 2>/dev/null; then
        tmux new-session -ds "$selected_name" -c "$selected"
      fi

      if [[ -z $TMUX ]]; then
        tmux attach -t "$selected_name"
      else
        tmux switch-client -t "$selected_name"
      fi
    }
  '';

  programs.tmux = {
    enable = true;
    extraConfig = builtins.readFile ./tmux.conf;
  };

  home.packages = with pkgs; [ fzf gnupg pv zstd ] ++ [ pkgs-unstable.yazi ];
}
