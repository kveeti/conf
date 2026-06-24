{ config, pkgs, lib, ... }:

let
  srcDir = "/var/lib/restic";
  dstDir = "/var/lib/restic-archive";
  repos = [ "internal" "tasks" "bm" "modi" "ha" ];
  encPassSecret = name: config.age.secrets."restic-${name}-encryption-pass".path;
in {
  # nofail: a missing USB must not drop the host to emergency at boot
  fileSystems.${dstDir}.options = [ "nofail" "x-systemd.device-timeout=15s" ];

  systemd.services = lib.listToAttrs (map (name: lib.nameValuePair "restic-${name}-archive" {
    description = "Archive ${name} restic repo SSD -> USB (copy + prune)";
    path = [ pkgs.restic ];
    serviceConfig.Type = "oneshot";
    # only if USB mounted, else restic writes into the mountpoint on rpool and fills the SSD
    unitConfig.ConditionPathIsMountPoint = dstDir;
    environment = {
      RESTIC_REPOSITORY = "${dstDir}/${name}";
      RESTIC_PASSWORD_FILE = encPassSecret name;
    };
    script = ''
      set -euo pipefail

      if ! restic -r ${srcDir}/${name} --password-file ${encPassSecret name} cat config >/dev/null 2>&1; then
        echo "source repo ${name} not initialized yet, skipping"
        exit 0
      fi

      if ! restic cat config >/dev/null 2>&1; then
        restic init
      fi

      restic copy --from-repo ${srcDir}/${name} --from-password-file ${encPassSecret name}
      restic forget --prune --keep-daily 30 --keep-weekly 12 --keep-monthly 24
    '';
  }) repos);

  systemd.timers = lib.listToAttrs (map (name: lib.nameValuePair "restic-${name}-archive" {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "2h"; };
  }) repos);
}
