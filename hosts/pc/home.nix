{ lib, pkgs, pkgs-unstable, ... }:

let
  inventory = import ../../inventory.nix;
in
{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/desktop.nix
    ../../modules/home/nvim.nix
  ];

  home.username = "veeti";
  home.homeDirectory = "/home/veeti";
  home.stateVersion = "25.11";

  qt.kde.settings.powerdevilrc.AC.SuspendSession.idleTime = 0;

  programs.bash.enable = true;

  home.packages = with pkgs; [
    obsidian
    prismlauncher
    (llama-cpp.override { vulkanSupport = true; })
  ];

  xdg.dataFile."icons/breeze_cursors".source = "${pkgs.kdePackages.breeze}/share/icons/breeze_cursors";

  xdg.dataFile."applications/discord.desktop".text = builtins.replaceStrings
    [ "Exec=Discord" ]
    [ "Exec=Discord --ozone-platform=wayland --force-device-scale-factor=1" ]
    (builtins.readFile "${pkgs.discord}/share/applications/discord.desktop");

  home.file.".ssh/config".text = ''
    AddKeysToAgent yes

    Host router
      HostName ${inventory.hosts.router.ipv4}

    Host atx
      HostName ${inventory.hosts.atx.ipv4}

    Host worker
      HostName ${inventory.hosts.worker.ipv4}

    Host o11y
      HostName ${inventory.hosts.o11y.ipv4}
  '';

  home.file.".config/jellyfin-mpv-shim/mpv.conf".text = ''
    hwdec=auto-safe
    vo=gpu-next
    target-colorspace-hint=yes
  '';

}
