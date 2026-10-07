{ pkgs, ... }:

let
  ddcBrightness = pkgs.writeShellApplication {
    name = "ddc-brightness";
    runtimeInputs = with pkgs; [ coreutils ddcutil gnugrep procps ];
    text = ''
      state="$XDG_RUNTIME_DIR/hyprland-brightness"

      read_current() {
        ddcutil --bus 5 getvcp 10 2>/dev/null \
          | grep -oE '= +[0-9]+' \
          | grep -oE '[0-9]+' \
          | head -1
      }

      case "''${1:-status}" in
        init)
          read_current > "$state"
          ;;
        status)
          if [ -f "$state" ]; then
            cat "$state"
          else
            read_current
          fi
          ;;
        up|down)
          if [ -f "$state" ]; then
            value=$(cat "$state")
          else
            value=$(read_current)
          fi

          if [ "''${1:-}" = up ]; then
            value=$((value + 10))
          else
            value=$((value - 10))
          fi

          if [ "$value" -gt 100 ]; then value=100; fi
          if [ "$value" -lt 0 ]; then value=0; fi

          printf '%s\n' "$value" > "$state"
          ddcutil --bus 5 --noverify setvcp 10 "$value" >/dev/null 2>&1 || true
          pkill -RTMIN+8 waybar || true
          ;;
        *)
          exit 1
          ;;
      esac
    '';
  };
in
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  security.pam.services.hyprlock = {};

  environment.systemPackages = with pkgs; [
    dex
    fuzzel
    hyprlock
    waybar
    ddcBrightness
  ];
}
