{ config, lib, pkgs, pkgs-unstable, ... }:

let
  inventory = import ../../inventory.nix;
in
{
  home.packages = with pkgs; [
    discord
    lazygit
    spotify
    syncthing
    thunderbird
    pkgs-unstable.opencode
    pkgs-unstable.pi-coding-agent
  ] ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.ghostty ];

  programs.firefox.enable = true;
  programs.keepassxc.enable = true;
  services.syncthing = {
    enable = true;
    settings = {
      options.relaysEnabled = false;
      devices.worker = {
        id = "HGEE7QW-DFD2DHT-BKEGK3V-5JFR52R-U3WXKFC-GLX2K6I-SVO4RA5-3J3BOQK";
        addresses = [ "tcp://${inventory.hosts.worker.ipv4}:${toString inventory.hosts.worker.ports.syncthingTransfer}" ];
      };
      folders.Synced = {
        path = "${config.home.homeDirectory}/Synced";
        id = "synced-nynum-wiueh-aosdi-asfgo-hjytr-pwpre";
        ignorePerms = true;
        devices = [ "worker" ];
      };
    };
  };

  home.activation.syncthingLogDirectory = lib.mkIf pkgs.stdenv.isDarwin (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/Library/Logs/Syncthing"
  '');

  xdg.configFile."ghostty/config".source = config.lib.file.mkOutOfStoreSymlink ./ghostty.conf;
  xdg.configFile."ghostty/themes/vague".source = config.lib.file.mkOutOfStoreSymlink ./ghostty-vague.conf;
}
