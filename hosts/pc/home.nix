{ lib, pkgs, pkgs-unstable, ... }:

let
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
    prismlauncher
    discord
    spotify
    (llama-cpp.override { vulkanSupport = true; })
    pkgs-unstable.pi-coding-agent
    opencode
  ];

  xdg.dataFile."icons/Cosmic".source = "${pkgs.cosmic-icons}/share/icons/Cosmic";
  xdg.dataFile."icons/Pop".source = "${pkgs.pop-icon-theme}/share/icons/Pop";

  xdg.dataFile."applications/discord.desktop".text = builtins.replaceStrings
    [ "Exec=Discord" ]
    [ "Exec=Discord --ozone-platform=wayland" ]
    (builtins.readFile "${pkgs.discord}/share/applications/discord.desktop");

  programs.keepassxc.enable = true;

  home.file.".config/jellyfin-mpv-shim/mpv.conf".text = ''
    hwdec=auto-safe
    vo=gpu-next
    target-colorspace-hint=yes
  '';

}
