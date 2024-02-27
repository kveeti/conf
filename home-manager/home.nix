{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  nixpkgs = {
    overlays = [
      outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  };

  home = {
    username = "kveeti";
    homeDirectory = "/home/kveeti";
  };

  programs.home-manager.enable = true;
  programs.git.enable = true;

  home.file."./.config/nvim/" = {
    source = ./nvim;
    recursive = true;
  };

  home.file."./.config/tmux/" = {
    source = ./tmux;
    recursive = true;
  };

  systemd.user.startServices = "sd-switch";

  home.stateVersion = "23.11";
}
