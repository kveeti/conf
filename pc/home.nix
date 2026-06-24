{ pkgs, ... }:

let
  notwaita-cursor = pkgs.stdenvNoCC.mkDerivation {
    pname = "notwaita-cursor";
    version = "1.0.0-alpha1";
    src = pkgs.fetchurl {
      url = "https://github.com/ful1e5/notwaita-cursor/releases/download/v1.0.0-alpha1/Notwaita-Black.tar.xz";
      sha256 = "1ky7czkbjsi8isx9cxabdryavnk1ii1aizyznfbgxkva20spiw9z";
    };
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/share/icons/Notwaita-Black
      cp -r . $out/share/icons/Notwaita-Black/
    '';
  };
in
{
  home.username = "veeti";
  home.homeDirectory = "/home/veeti";
  home.stateVersion = "25.11";

  # jellyfin-mpv-shim embeds libmpv; force Intel HW decode so 4K doesn't
  # software-decode on the i5-9500.
  home.file.".config/jellyfin-mpv-shim/mpv.conf".text = ''
    hwdec=auto-safe
    vo=gpu-next
    video-sync=display-resample
  '';

  home.pointerCursor = {
    name = "Notwaita-Black";
    size = 32;
    package = notwaita-cursor;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
    font = {
      name = "Noto Sans";
      size = 10;
    };
    iconTheme = {
      name = "breeze";
      package = pkgs.kdePackages.breeze-icons;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = false;
      gtk-button-images = true;
      gtk-cursor-blink = true;
      gtk-cursor-blink-time = 1000;
      gtk-decoration-layout = "icon:minimize,maximize,close";
      gtk-enable-animations = true;
      gtk-menu-images = true;
      gtk-primary-button-warps-slider = true;
      gtk-sound-theme-name = "ocean";
      gtk-toolbar-style = 3;
      gtk-xft-dpi = 159744;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = false;
      gtk-cursor-blink = true;
      gtk-cursor-blink-time = 1000;
      gtk-decoration-layout = "icon:minimize,maximize,close";
      gtk-enable-animations = true;
      gtk-primary-button-warps-slider = true;
      gtk-xft-dpi = 159744;
    };
  };
}
