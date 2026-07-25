{ pkgs, nixvim, ... }:

{
  imports = [ nixvim.homeModules.nixvim ../../../mac/nvim.nix ];

  home = {
    username = "veeti";
    homeDirectory = "/home/veeti";
    stateVersion = "25.11";
    packages = with pkgs; [
      git gh gnumake gcc
      nodejs_22 go python3 cargo rustc
      ripgrep fd fzf jq curl direnv
      ghostty.terminfo
      claude-code
      codex
      (pkgs.callPackage ../../../mac/pi-coding-agent.nix { })
      (pkgs.callPackage ./dev-url.nix { })
    ];
  };

  programs.home-manager.enable = true;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    history = {
      path = "$HOME/.histfile";
      size = 1000;
      save = 1000;
    };
    initContent = ''
      setopt autocd extendedglob nomatch notify
      bindkey -v
      bindkey '^R' history-incremental-search-backward
    '';
  };

  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [ resurrect continuum ];
    extraConfig = (builtins.readFile ../../../mac/tmux.conf) + ''
      set -g @resurrect-dir '/home/veeti/.local/share/tmux/resurrect'
      set -g @continuum-restore 'on'
      set -g @continuum-save-interval '15'
    '';
  };
}
