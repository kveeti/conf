{ pkgs, pkgs-unstable, ... }:

let
  bluetoothBattery = pkgs.writeShellApplication {
    name = "bluetooth-battery";
    runtimeInputs = [ pkgs.python3 pkgs.systemd ];
    text = ''
      exec python3 ${./bluetooth-battery.py}
    '';
  };

  bluetoothMenu = pkgs.writeShellApplication {
    name = "bluetooth-menu";
    runtimeInputs = with pkgs; [ bluez rofi gnugrep util-linux ];
    text = builtins.readFile ./bluetooth-menu.sh;
  };

  bluetoothDesktop = pkgs.makeDesktopItem {
    name = "bluetooth-menu";
    desktopName = "Bluetooth";
    exec = "${bluetoothMenu}/bin/bluetooth-menu";
    icon = "${pkgs.kdePackages.breeze-icons}/share/icons/breeze-dark/devices/24/network-bluetooth.svg";
    categories = [ "Settings" "HardwareSettings" ];
  };

  audioSelectedIcon = pkgs.writeText "audio-selected.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
      <path d="m5 12 4 4 10-10" fill="none" stroke="#dedede" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  '';

  audioAirplayIcon = pkgs.writeText "audio-airplay.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
      <path d="M3 8a14 14 0 0 1 18 0M6 12a9 9 0 0 1 12 0m-9 4a4.5 4.5 0 0 1 6 0" fill="none" stroke="#dedede" stroke-width="2" stroke-linecap="round"/>
      <circle cx="12" cy="20" r="1" fill="#dedede"/>
    </svg>
  '';

  audioSpeakerIcon = pkgs.writeText "audio-speaker.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
      <path d="M4 9h4l5-4v14l-5-4H4Z" fill="none" stroke="#dedede" stroke-width="2" stroke-linejoin="round"/>
      <path d="M17 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14" fill="none" stroke="#dedede" stroke-width="2" stroke-linecap="round"/>
    </svg>
  '';

  audioMenu = pkgs.writeShellApplication {
    name = "audio-menu";
    runtimeInputs = [ pkgs.bluez pkgs.pipewire pkgs.wireplumber pkgs.python3 pkgs.rofi ];
    text = ''
      exec python3 ${./audio-menu.py} ${audioSelectedIcon} \
        ${audioSpeakerIcon} \
        ${audioAirplayIcon} \
        ${pkgs.kdePackages.breeze-icons}/share/icons/breeze-dark/devices/24/network-bluetooth.svg
    '';
  };

  windowMenu = pkgs.writeShellApplication {
    name = "window-menu";
    runtimeInputs = with pkgs; [ niri jq rofi ];
    text = ''
      if ! selected=$(
        niri msg --json windows \
          | jq -r 'sort_by(.focus_timestamp.secs, .focus_timestamp.nanos) | reverse | .[] | ([.id, .app_id, .title] | @tsv) + "\u0000icon\u001f" + (.app_id // "application-x-executable")' \
          | rofi -dmenu -i -no-custom -matching fuzzy -p Windows \
              -display-columns 2,3 \
              -theme-str 'entry { placeholder: "Search windows…"; }'
      ); then
        exit 0
      fi

      if [ -n "$selected" ]; then
        niri msg action focus-window --id "''${selected%%$'\t'*}"
      fi
    '';
  };

  toggleHdr = pkgs.writeShellApplication {
    name = "toggle-hdr";
    runtimeInputs = [ pkgs.gnugrep pkgs.hyprland ];
    text = ''
      if hyprctl monitors | grep -q 'colorManagementPreset: hdr'; then
        hyprctl keyword monitor ', highres, auto, 1.5, cm, srgb, bitdepth, 8'
      else
        hyprctl keyword monitor ', 3840x2160@120, auto, 1.5, cm, hdr, bitdepth, 10'
      fi
    '';
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
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/nvim.nix
  ];

  home.username = "veeti";
  home.homeDirectory = "/home/veeti";
  home.stateVersion = "25.11";

  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gcr/ssh";

  programs.bash.enable = true;

  home.packages = with pkgs; [
    pkgs-unstable.satty
    prismlauncher
    rofi
    discord
    spotify
    bluetoothMenu
    bluetoothDesktop
    audioMenu
    windowMenu
    toggleHdr
    (llama-cpp.override { vulkanSupport = true; })
    (callPackage ./pi-coding-agent.nix {})
    wl-clipboard
  ];

  programs.keepassxc.enable = true;
  services.mako = {
    enable = true;
    settings.default-timeout = 5000;
  };
  services.playerctld.enable = true;

  systemd.user.services.screenshot-annotation = {
    Unit = {
      Description = "Open Niri screenshots in Satty";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service.ExecStart = pkgs.writeShellScript "screenshot-annotation" ''
      ${pkgs.niri}/bin/niri msg --json event-stream \
        | ${pkgs.jq}/bin/jq --unbuffered -r 'select(.ScreenshotCaptured.path != null) | .ScreenshotCaptured.path' \
        | while IFS= read -r path; do
            ${pkgs-unstable.satty}/bin/satty --filename "$path" --output-filename "$path" &
          done
    '';
  };

  xdg.desktopEntries.spotify = {
    name = "Spotify";
    exec = "spotify --ozone-platform=wayland --force-device-scale-factor=1.5 %U";
    icon = "spotify-client";
    type = "Application";
    categories = [ "Audio" "Music" "Player" ];
    mimeType = [ "x-scheme-handler/spotify" ];
  };

  xdg.desktopEntries.steam = {
    name = "Steam";
    exec = "steam %U";
    icon = "steam";
    type = "Application";
    categories = [ "Network" "FileTransfer" "Game" ];
  };

  xdg.desktopEntries.discord = {
    name = "Discord";
    exec = "Discord --enable-speech-dispatcher --enable-features=UseOzonePlatform --ozone-platform=wayland --force-device-scale-factor=1";
    icon = "discord";
    type = "Application";
    categories = [ "Network" "InstantMessaging" ];
  };

  home.file.".config/jellyfin-mpv-shim/mpv.conf".text = ''
    hwdec=auto-safe
    vo=gpu-next
    target-colorspace-hint=yes
  '';

  xdg.configFile."rofi/config.rasi".text = ''
    configuration {
      modi: "drun";
      show-icons: true;
      icon-theme: "breeze";
      drun-display-format: "{name}";
      drun-match-fields: "name,keywords";
      drun-exclude-categories: "Printing";
      matching: "fuzzy";
      sort: true;
      sorting-method: "fzf";
    }

    @theme "/dev/null"

    * {
      font: "Noto Sans 12";
      background-color: transparent;
      text-color: #dedede;
    }

    window {
      width: 600px;
      location: center;
      anchor: center;
      background-color: #20202099;
      border: 1px;
      border-color: #ffffff12;
      border-radius: 14px;
      padding: 12px;
      children: [ mainbox ];
    }

    mainbox {
      orientation: vertical;
      spacing: 8px;
      children: [ inputbar, listview ];
    }

    inputbar {
      padding: 4px 8px;
      children: [ entry ];
    }

    entry {
      placeholder: "Search apps…";
      placeholder-color: #888888;
      text-color: #f5f5f5;
    }

    listview {
      lines: 7;
      columns: 1;
      fixed-height: true;
      scrollbar: false;
      spacing: 2px;
    }

    element {
      padding: 8px;
      spacing: 10px;
      border-radius: 8px;
      children: [ element-icon, element-text ];
    }

    element selected.normal {
      background-color: #ffffff14;
      text-color: #ffffff;
    }

    element-icon {
      size: 20px;
      vertical-align: 0.5;
    }

    element-text {
      vertical-align: 0.5;
    }
  '';

  home.file.".config/hypr/hyprland.conf".text = ''
    monitor = , highres, auto, 1.5

    layerrule = match:namespace ^(rofi)$, blur on, ignore_alpha 0, animation popin 97%
    windowrule = match:initial_class ^(steam|org\.prismlauncher\.PrismLauncher|org\.keepassxc\.KeePassXC)$, float on
    windowrule = match:initial_class ^(steam|org\.prismlauncher\.PrismLauncher|org\.keepassxc\.KeePassXC)$, size 1280 800
    windowrule = match:initial_class ^(steam|org\.prismlauncher\.PrismLauncher|org\.keepassxc\.KeePassXC)$, center on

    $mainMod = ALT

    general {
      gaps_in = 0
      gaps_out = 0
      border_size = 1
      col.active_border = rgba(606060ff)
      col.inactive_border = rgba(303030ff)
    }

    misc {
      vrr = 2
    }

    decoration {
      blur {
        passes = 2
      }
    }

    animations {
      enabled = true
      bezier = dialog, 0.16, 1, 0.3, 1
      bezier = pop, 0.34, 1.25, 0.64, 1
      animation = windows, 0
      animation = workspaces, 0
      animation = fade, 0
      animation = layers, 1, 3, pop, popin 97%
      animation = layersIn, 1, 2.5, pop, popin 97%
      animation = fadeLayers, 1, 2, dialog
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

    bind = $mainMod, SPACE, exec, rofi -show drun
    bind = $mainMod, A, exec, audio-menu
    bind = $mainMod SHIFT, X, exec, hyprlock
    bind = $mainMod, RETURN, exec, ghostty
    bind = $mainMod SHIFT, Q, killactive
    bind = $mainMod SHIFT, E, exit
    bind = $mainMod SHIFT, C, exec, hyprctl reload

    bind = $mainMod, H, movefocus, l
    bind = $mainMod, J, movefocus, d
    bind = $mainMod, K, movefocus, u
    bind = $mainMod, L, movefocus, r

    bind = $mainMod SHIFT, H, movewindow, l
    bind = $mainMod SHIFT, J, movewindow, d
    bind = $mainMod SHIFT, K, movewindow, u
    bind = $mainMod SHIFT, L, movewindow, r

    bind = $mainMod, B, layoutmsg, togglesplit
    bind = $mainMod, V, layoutmsg, togglesplit
    bind = $mainMod, E, layoutmsg, togglesplit
    bind = $mainMod, F, fullscreen
    bind = $mainMod SHIFT, SPACE, togglefloating
    bindm = $mainMod, mouse:272, movewindow
    bindm = $mainMod, mouse:273, resizewindow
    bind = CTRL SUPER ALT, H, exec, toggle-hdr

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
    bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
    bindel = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    bindl = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    bindl = , XF86AudioPlay, exec, playerctl --player=playerctld play-pause
    bindl = , XF86AudioPause, exec, playerctl --player=playerctld pause
    bindl = , XF86AudioNext, exec, playerctl --player=playerctld next
    bindl = , XF86AudioPrev, exec, playerctl --player=playerctld previous
    bindl = , XF86AudioStop, exec, playerctl --player=playerctld stop
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

  home.file.".config/niri/config.kdl".text = ''
    input {
      mod-key "Alt"

      keyboard {
        xkb {
          layout "fi"
          variant "mac"
          options "ctrl:nocaps"
        }
        repeat-delay 180
        repeat-rate 60
      }

      mouse {
        accel-profile "flat"
        accel-speed -0.3
        natural-scroll
        scroll-factor 2.0
      }
    }

    output "Technical Concepts Ltd 27R83U X2414000835" {
      mode "3840x2160"
      scale 1.5
    }

    blur {
      passes 2
    }

    window-rule {
      draw-border-with-background false
      geometry-corner-radius 12
      clip-to-geometry true
    }

    window-rule {
      match app-id="^steam$"
      open-floating true
    }

    window-rule {
      match app-id="^com\\.gabm\\.satty$"
      open-floating true
    }

    window-rule {
      match app-id="^firefox$" title="^Picture-in-Picture$"
      open-floating true
    }

    window-rule {
      match app-id="^org\\.keepassxc\\.KeePassXC$"
      open-floating true
    }

    layer-rule {
      match namespace="^rofi$"
      geometry-corner-radius 14
      background-effect {
        xray false
        blur true
        noise 0.0
        saturation 1.0
      }
    }

    layout {
      background-color "#000000"
      gaps 2
      default-column-width { proportion 0.5; }
      preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
      }
      focus-ring {
        width 1
        active-color "#606060"
        inactive-color "#303030"
      }
    }

    binds {
      Mod+Shift+Slash { show-hotkey-overlay; }
      Mod+Shift+S { screenshot; }
      Mod+Space hotkey-overlay-title="Launch an app" { spawn "rofi" "-show" "drun"; }
      Mod+A { spawn "audio-menu"; }
      Mod+Return { spawn "ghostty"; }
      Mod+Shift+X { spawn "swaylock" "-f" "-c" "202020"; }
      Mod+Q { close-window; }
      Mod+Shift+E { quit; }

      Mod+H { focus-column-left; }
      Mod+J { focus-workspace-down; }
      Mod+K { focus-workspace-up; }
      Mod+L { focus-column-right; }
      Mod+Ctrl+H { move-column-left; }
      Mod+Ctrl+J { move-column-to-workspace-down; }
      Mod+Ctrl+K { move-column-to-workspace-up; }
      Mod+Ctrl+L { move-column-right; }

      Mod+WheelScrollDown { focus-column-right; }
      Mod+WheelScrollUp { focus-column-left; }
      Mod+Shift+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }
      Mod+Shift+WheelScrollUp cooldown-ms=150 { focus-workspace-up; }

      Mod+Minus { set-column-width "-10%"; }
      Mod+Equal { set-column-width "+10%"; }
      Mod+Shift+Minus { set-window-height "-10%"; }
      Mod+Shift+Equal { set-window-height "+10%"; }
      Mod+Ctrl+R { reset-window-height; }
      Mod+R { switch-preset-column-width; }
      Mod+F { spawn-sh "niri msg action set-column-width '100%' && niri msg action set-window-height '100%'"; }
      Mod+C { spawn-sh "niri msg action set-column-width '66.66667%' && niri msg action center-column"; }
      Mod+Shift+F { fullscreen-window; }
      Mod+V { toggle-window-floating; }
      Mod+Ctrl+V { spawn-sh "if niri msg --json outputs | ${pkgs.jq}/bin/jq -e '.[\"DP-1\"].vrr_enabled' >/dev/null; then niri msg output DP-1 vrr off && ${pkgs.libnotify}/bin/notify-send 'VRR off'; else niri msg output DP-1 vrr on && ${pkgs.libnotify}/bin/notify-send 'VRR on'; fi"; }
      Mod+W hotkey-overlay-title="Find an open window" { spawn "window-menu"; }

      F1 { spawn "ddc-brightness" "down"; }
      F2 { spawn "ddc-brightness" "up"; }
      F10 allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }
      F11 allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"; }
      F12 allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0"; }
      XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0"; }
      XF86AudioLowerVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"; }
      XF86AudioMute allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }
      XF86AudioPlay allow-when-locked=true { spawn-sh "playerctl --player=playerctld play-pause"; }
      XF86AudioPause allow-when-locked=true { spawn-sh "playerctl --player=playerctld pause"; }
      XF86AudioNext allow-when-locked=true { spawn-sh "playerctl --player=playerctld next"; }
      XF86AudioPrev allow-when-locked=true { spawn-sh "playerctl --player=playerctld previous"; }
      XF86AudioStop allow-when-locked=true { spawn-sh "playerctl --player=playerctld stop"; }
    }

    spawn-at-startup "systemctl" "--user" "start" "mako.service"
    spawn-at-startup "waybar"
    spawn-at-startup "ddc-brightness" "init"
  '';

  home.file.".config/waybar/config".text = builtins.toJSON {
    height = 24;
    "modules-right" = [ "custom/bluetooth-battery" "custom/brightness" "cpu" "memory" "disk" "clock" ];
    "custom/bluetooth-battery" = {
      exec = "${bluetoothBattery}/bin/bluetooth-battery";
      format = "<span size=\"120%\"></span> {}";
      "return-type" = "json";
      "hide-empty-text" = true;
    };
    cpu = { format = "C {usage}%"; };
    memory = { format = "R {percentage}%"; };
    disk = { path = "/"; format = "D {percentage_used}%"; };
    "custom/brightness" = {
      exec = "ddc-brightness status";
      "return-type" = "text";
      interval = 5;
      signal = 8;
      format = "<span size=\"120%\">󰖙</span> {}";
      "tooltip-format" = "Brightness: {}";
    };
    clock = { format = "{:%a %Y-%m-%d %H:%M}"; };
  };

  home.file.".config/waybar/style.css".text = ''
    * {
      font-family: "Noto Sans", "Symbols Nerd Font";
      font-size: 12px;
    }

    window#waybar {
      background: #202020;
      color: #eeeeee;
    }

    #workspaces, #cpu, #memory, #disk, #custom-bluetooth-battery, #custom-brightness, #clock {
      padding: 2px 10px;
    }
  '';

  home.pointerCursor = {
    name = "Notwaita-Black";
    size = 32;
    package = notwaita-cursor;
    gtk.enable = true;
    x11.enable = true;
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

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
      gtk-application-prefer-dark-theme = true;
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
      gtk-application-prefer-dark-theme = true;
      gtk-cursor-blink = true;
      gtk-cursor-blink-time = 1000;
      gtk-decoration-layout = "icon:minimize,maximize,close";
      gtk-enable-animations = true;
      gtk-primary-button-warps-slider = true;
      gtk-xft-dpi = 159744;
    };
  };
}
