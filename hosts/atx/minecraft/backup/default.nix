{ pkgs, ... }:

let
  command = "${pkgs.python3}/bin/python3 ${./backup.py}";
in {
  environment.systemPackages = [ pkgs.restic ];

  systemd.services.minecraft-backup = {
    description = "Back up all local Minecraft servers";
    unitConfig.RequiresMountsFor = [ "/home/veeti/servers" "/home/veeti/backups" ];
    path = [ pkgs.restic pkgs.tmux ];
    serviceConfig = {
      Type = "oneshot";
      User = "veeti";
      Group = "users";
      UMask = "0077";
      ExecStart = command;
      ExecStopPost = "${command} --resume-saving";
      # Bound the whole pass, including retries; ExecStopPost recovers saving.
      TimeoutStartSec = "30min";
      TimeoutStopSec = "60s";
      Nice = 10;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 7;
      MemoryMax = "512M";
      NoNewPrivileges = true;
      # The script needs the existing tmux socket in /tmp, so no PrivateTmp.
    };
  };

  systemd.timers.minecraft-backup = {
    description = "Minecraft backups every 12–18 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitInactiveSec = "12min";
      RandomizedDelaySec = "6min";
      AccuracySec = "1s";
      Unit = "minecraft-backup.service";
    };
  };
}
