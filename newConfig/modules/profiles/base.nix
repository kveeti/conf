{ lib, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "fi";

  environment.systemPackages = with pkgs; [
    btop
    git
    restic
    tmux
    vim
  ];
}
