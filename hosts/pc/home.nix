{ lib, pkgs, pkgs-unstable, ... }:

let
  inventory = import ../../inventory.nix;
  opencode = pkgs-unstable.opencode.overrideAttrs (old: {
    version = "2.2.5";
    src = pkgs-unstable.fetchFromGitHub {
      owner = "anomalyco";
      repo = "opencode";
      tag = "v2.2.5";
      hash = "sha256-/a1czcXi12KWPXcESqplNdOZcjEs8gWCMO7w4nQYLkw=";
    };
    node_modules = old.node_modules.overrideAttrs (_: {
      version = "2.2.5";
      src = pkgs-unstable.fetchFromGitHub {
        owner = "anomalyco";
        repo = "opencode";
        tag = "v2.2.5";
        hash = "sha256-/a1czcXi12KWPXcESqplNdOZcjEs8gWCMO7w4nQYLkw=";
      };
      outputHash = "sha256-xfOVcw1+waLVNhFDwzOtzxrUSQEogvn88YomydOlhwc=";
    });
  });
in
{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/nvim.nix
  ];

  home.username = "veeti";
  home.homeDirectory = "/home/veeti";
  home.stateVersion = "25.11";

  qt.kde.settings.powerdevilrc.AC.SuspendSession.idleTime = 0;

  programs.bash.enable = true;

  home.packages = with pkgs; [
    obsidian
    syncthing
    prismlauncher
    discord
    spotify
    (llama-cpp.override { vulkanSupport = true; })
    pkgs-unstable.pi-coding-agent
    opencode
  ];

  xdg.dataFile."icons/breeze_cursors".source = "${pkgs.kdePackages.breeze}/share/icons/breeze_cursors";

  xdg.dataFile."applications/discord.desktop".text = builtins.replaceStrings
    [ "Exec=Discord" ]
    [ "Exec=Discord --ozone-platform=wayland --force-device-scale-factor=1" ]
    (builtins.readFile "${pkgs.discord}/share/applications/discord.desktop");

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
        path = "/home/veeti/Synced";
        id = "synced-nynum-wiueh-aosdi-asfgo-hjytr-pwpre";
        ignorePerms = true;
        devices = [ "worker" ];
      };
    };
  };

  home.sessionVariables.SSH_ASKPASS_REQUIRE = "prefer";
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
