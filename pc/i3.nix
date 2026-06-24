{ pkgs, ... }:

let
  # Optimistic brightness: track value in a state file so the bar updates
  # instantly on keypress, while the (slow-fading) DDC write happens after.
  ddcBrightness = pkgs.writeShellApplication {
    name = "ddc-brightness";
    runtimeInputs = with pkgs; [ ddcutil procps gnugrep coreutils ];
    text = ''
      state="/run/user/$(id -u)/i3-brightness"
      bus=5
      step=10
      if [ ! -f "$state" ]; then
        cur=$(ddcutil --bus "$bus" getvcp 10 2>/dev/null | grep -oE '= +[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
        echo "''${cur:-50}" > "$state"
      fi
      val=$(cat "$state")
      if [ "''${1:-}" = up ]; then val=$((val + step)); fi
      if [ "''${1:-}" = down ]; then val=$((val - step)); fi
      if [ "$val" -gt 100 ]; then val=100; fi
      if [ "$val" -lt 0 ]; then val=0; fi
      echo "$val" > "$state"
      pkill -USR1 i3status || true
      ddcutil --bus "$bus" --noverify setvcp 10 "$val" >/dev/null 2>&1 || true
    '';
  };

  i3statusConf = pkgs.writeText "i3status.conf" ''
    general {
        colors = true
        interval = 5
    }

    order += "read_file brightness"
    order += "cpu_usage"
    order += "memory"
    order += "disk /"
    order += "ethernet _first_"
    order += "tztime local"

    read_file brightness {
        path = "/run/user/1000/i3-brightness"
        format = "BRT %content"
        format_bad = "BRT --"
    }

    cpu_usage {
        format = "CPU %usage"
    }

    memory {
        format = "RAM %percentage_used"
    }

    disk "/" {
        format = "DISK %avail"
    }

    ethernet _first_ {
        format_up = "NET %ip"
        format_down = "NET down"
    }

    tztime local {
        format = "%a %Y-%m-%d %H:%M"
    }
  '';
in
{
  services.xserver.windowManager.i3 = {
    enable = true;
    extraPackages = with pkgs; [
      dmenu
      i3status
      i3lock
      picom
      feh
      xorg.xrandr
      ddcBrightness
    ];
  };

  environment.etc."xdg/i3/config".text = ''
    set $mod Mod4

    font pango:monospace 10

    floating_modifier $mod

    exec --no-startup-id picom -b --backend glx --vsync --use-damage --unredir-if-possible
    exec --no-startup-id dex --autostart --environment i3

    # DP-1 panel has no native 48Hz; register a custom mode at exactly 47.952Hz
    # (2x 23.976fps film, clean 2:1) — idempotent on reload
    exec_always --no-startup-id sh -c 'xrandr --newmode "3840x2160_48p" 560.876 3840 4136 4552 5264 2160 2163 2168 2222 -hsync +vsync 2>/dev/null; xrandr --addmode DP-1 "3840x2160_48p" 2>/dev/null; true'

    exec_always --no-startup-id xset r rate 180 60

    # seed the optimistic brightness state file from the monitor's real value
    exec --no-startup-id ddc-brightness init

    bindsym $mod+space    exec --no-startup-id dmenu_run
    bindsym $mod+Shift+x  exec --no-startup-id i3lock -c 000000
    bindsym $mod+Return   exec ghostty
    bindsym $mod+Shift+q  kill
    bindsym $mod+Shift+e  exec "i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'"
    bindsym $mod+Shift+c  reload
    bindsym $mod+Shift+r  restart

    bindsym $mod+h focus left
    bindsym $mod+j focus down
    bindsym $mod+k focus up
    bindsym $mod+Right focus right

    bindsym $mod+Shift+h move left
    bindsym $mod+Shift+j move down
    bindsym $mod+Shift+k move up
    bindsym $mod+Shift+Right move right

    bindsym $mod+b split h
    bindsym $mod+v split v
    bindsym $mod+f fullscreen toggle

    bindsym $mod+Shift+f exec --no-startup-id xrandr --output DP-1 --mode "3840x2160_48p"
    bindsym $mod+Shift+g exec --no-startup-id xrandr --output DP-1 --mode 3840x2160 --rate 60

    bindsym $mod+s layout stacking
    bindsym $mod+w layout tabbed
    bindsym $mod+e layout toggle split

    bindsym $mod+Shift+space floating toggle
    bindsym $mod+a focus parent

    bindsym $mod+1 workspace number 1
    bindsym $mod+2 workspace number 2
    bindsym $mod+3 workspace number 3
    bindsym $mod+4 workspace number 4
    bindsym $mod+5 workspace number 5
    bindsym $mod+6 workspace number 6
    bindsym $mod+7 workspace number 7
    bindsym $mod+8 workspace number 8
    bindsym $mod+9 workspace number 9
    bindsym $mod+0 workspace number 10

    bindsym $mod+Shift+1 move container to workspace number 1
    bindsym $mod+Shift+2 move container to workspace number 2
    bindsym $mod+Shift+3 move container to workspace number 3
    bindsym $mod+Shift+4 move container to workspace number 4
    bindsym $mod+Shift+5 move container to workspace number 5
    bindsym $mod+Shift+6 move container to workspace number 6
    bindsym $mod+Shift+7 move container to workspace number 7
    bindsym $mod+Shift+8 move container to workspace number 8
    bindsym $mod+Shift+9 move container to workspace number 9
    bindsym $mod+Shift+0 move container to workspace number 10

    mode "resize" {
      bindsym h resize shrink width  10 px or 10 ppt
      bindsym j resize grow   height 10 px or 10 ppt
      bindsym k resize shrink height 10 px or 10 ppt
      bindsym l resize grow   width  10 px or 10 ppt
      bindsym Escape mode "default"
      bindsym Return mode "default"
    }
    bindsym $mod+r mode "resize"

    bindsym F1 exec --no-startup-id ddc-brightness down
    bindsym F2 exec --no-startup-id ddc-brightness up

    bindsym F12 exec --no-startup-id wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
    bindsym F11 exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    bindsym F10 exec --no-startup-id wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

    bar {
      status_command i3status -c ${i3statusConf}
    }
  '';
}
