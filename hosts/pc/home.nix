{ pkgs, ... }:

let
  bluetoothMenu = pkgs.writeShellApplication {
    name = "bluetooth-menu";
    runtimeInputs = with pkgs; [ bluez fuzzel gnugrep util-linux ];
    text = builtins.readFile ./bluetooth-menu.sh;
  };

  bluetoothDesktop = pkgs.makeDesktopItem {
    name = "bluetooth-menu";
    desktopName = "Bluetooth";
    exec = "${bluetoothMenu}/bin/bluetooth-menu";
    icon = "bluetooth";
    categories = [ "Settings" "HardwareSettings" ];
  };

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

  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gcr/ssh";

  programs.bash.enable = true;

  home.packages = with pkgs; [
    prismlauncher
    discord
    bluetoothMenu
    bluetoothDesktop
    (llama-cpp.override { vulkanSupport = true; })
    (callPackage ./pi-coding-agent.nix {})
  ];

  programs.keepassxc.enable = true;

  # jellyfin-mpv-shim embeds libmpv; force Intel HW decode so 4K doesn't
  # software-decode on the i5-9500.
  home.file.".config/jellyfin-mpv-shim/mpv.conf".text = ''
    hwdec=auto-safe
    vo=gpu-next
    video-sync=display-resample
  '';

  home.file.".config/hypr/hyprland.conf".text = ''
    monitor = desc:Technical Concepts Ltd 27R83U X2414000835, 3840x2160@144, auto, 1.5

    $mainMod = SUPER

    general {
      gaps_in = 0
      gaps_out = 0
    }

    animations {
      enabled = false
    }

    xwayland {
      force_zero_scaling = true
    }

    input {
      kb_layout = fi
      kb_variant = mac
      kb_options = ctrl:nocaps
      repeat_rate = 60
      repeat_delay = 180
      accel_profile = flat
      sensitivity = -0.3
      natural_scroll = true
    }

    env = XCURSOR_THEME, Notwaita-Black
    env = XCURSOR_SIZE, 32

    exec-once = waybar
    exec-once = dex --autostart --environment Hyprland
    exec-once = ddc-brightness init

    bind = $mainMod, SPACE, exec, fuzzel
    bind = $mainMod SHIFT, X, exec, hyprlock
    bind = $mainMod, RETURN, exec, ghostty
    bind = $mainMod SHIFT, Q, killactive
    bind = $mainMod SHIFT, E, exit
    bind = $mainMod SHIFT, C, exec, hyprctl reload

    bind = $mainMod, H, movefocus, l
    bind = $mainMod, J, movefocus, d
    bind = $mainMod, K, movefocus, u
    bind = $mainMod, RIGHT, movefocus, r

    bind = $mainMod SHIFT, H, movewindow, l
    bind = $mainMod SHIFT, J, movewindow, d
    bind = $mainMod SHIFT, K, movewindow, u
    bind = $mainMod SHIFT, RIGHT, movewindow, r

    bind = $mainMod, B, layoutmsg, togglesplit
    bind = $mainMod, V, layoutmsg, togglesplit
    bind = $mainMod, E, layoutmsg, togglesplit
    bind = $mainMod, F, fullscreen
    bind = $mainMod SHIFT, SPACE, togglefloating

    bind = $mainMod, 1, workspace, 1
    bind = $mainMod, 2, workspace, 2
    bind = $mainMod, 3, workspace, 3
    bind = $mainMod, 4, workspace, 4
    bind = $mainMod, 5, workspace, 5
    bind = $mainMod, 6, workspace, 6
    bind = $mainMod, 7, workspace, 7
    bind = $mainMod, 8, workspace, 8
    bind = $mainMod, 9, workspace, 9
    bind = $mainMod, 0, workspace, 10

    bind = $mainMod SHIFT, 1, movetoworkspace, 1
    bind = $mainMod SHIFT, 2, movetoworkspace, 2
    bind = $mainMod SHIFT, 3, movetoworkspace, 3
    bind = $mainMod SHIFT, 4, movetoworkspace, 4
    bind = $mainMod SHIFT, 5, movetoworkspace, 5
    bind = $mainMod SHIFT, 6, movetoworkspace, 6
    bind = $mainMod SHIFT, 7, movetoworkspace, 7
    bind = $mainMod SHIFT, 8, movetoworkspace, 8
    bind = $mainMod SHIFT, 9, movetoworkspace, 9
    bind = $mainMod SHIFT, 0, movetoworkspace, 10

    bind = $mainMod, R, submap, resize
    submap = resize
    binde = , H, resizeactive, -10 0
    binde = , J, resizeactive, 0 10
    binde = , K, resizeactive, 0 -10
    binde = , L, resizeactive, 10 0
    bind = , ESCAPE, submap, reset
    bind = , RETURN, submap, reset
    submap = reset

    bind = , F1, exec, ddc-brightness down
    bind = , F2, exec, ddc-brightness up
    bind = , F12, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
    bind = , F11, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    bind = , F10, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
  '';

  home.file.".config/hypr/hyprlock.conf".text = ''
    background {
      monitor =
      color = rgba(202020ff)
    }

    input-field {
      monitor =
      size = 300, 60
      position = 0, 0
      halign = center
      valign = center
      placeholder_text = Enter password
    }
  '';

  home.file.".config/waybar/config".text = builtins.toJSON {
    "modules-left" = [ "hyprland/workspaces" ];
    "modules-right" = [ "custom/brightness" "cpu" "memory" "disk" "clock" ];
    cpu = { format = "C {usage}%"; };
    memory = { format = "R {percentage}%"; };
    disk = { path = "/"; format = "D {percentage_used}%"; };
    "custom/brightness" = {
      exec = "ddc-brightness status";
      "return-type" = "text";
      interval = 5;
      signal = 8;
      format = "BRT {}";
    };
    clock = { format = "{:%a %Y-%m-%d %H:%M}"; };
  };

  home.file.".config/waybar/style.css".text = ''
    * {
      font-family: "JetBrainsMono Nerd Font";
      font-size: 12px;
    }

    window#waybar {
      background: #202020;
      color: #eeeeee;
    }

    #workspaces, #cpu, #memory, #disk, #custom-brightness, #clock {
      padding: 0 10px;
    }
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
