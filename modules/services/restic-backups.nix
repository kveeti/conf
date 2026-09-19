{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.backups;

  resticEnvironment = instance: ''
    export RESTIC_REPOSITORY=${lib.escapeShellArg "rest:${cfg.serverUrl}/${instance.repository}"}
    export RESTIC_REST_USERNAME=${lib.escapeShellArg instance.username}
    export RESTIC_REST_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/rest-password")"
    export RESTIC_PASSWORD_FILE="$CREDENTIALS_DIRECTORY/encryption-password"
    export RESTIC_CACHE_DIR="$CACHE_DIRECTORY"
  '';

  ensureRepository = instance: ''
    ${resticEnvironment instance}
    (
      flock 9
      for attempt in $(seq 1 12); do
        if restic cat config >/dev/null 2>&1 || restic init; then
          exit 0
        fi
        if [ "$attempt" -lt 12 ]; then
          echo "Repository ${instance.repository} unavailable; retrying in 10 seconds" >&2
          sleep 10
        fi
      done
      echo "Could not open repository ${instance.repository} after 12 attempts" >&2
      exit 1
    ) 9>/run/restic-init-${instance.repository}.lock
  '';

  credentials = instance: [
    "rest-password:${instance.restPasswordFile}"
    "encryption-password:${instance.encryptionPasswordFile}"
  ];

  tagArgs = instance:
    lib.optionalString (instance.tag != null) "--tag ${lib.escapeShellArg instance.tag}";

  excludes = instance:
    instance.excludes ++ lib.optional (instance.restoreMarker != null) instance.restoreMarker;

  hasCompleteState = instance:
    lib.optionalString
      (instance.restoreMarker != null)
      "[ ! -e ${lib.escapeShellArg instance.restoreMarker} ] && "
    + instance.hasData;

  backupServices = lib.mapAttrs' (name: instance:
    lib.nameValuePair "backup-${name}" {
      description = "Back up ${name}";
      after = [ "restore-${name}.service" ];
      requires = [ "restore-${name}.service" ];
      path = [ pkgs.restic pkgs.coreutils pkgs.util-linux ] ++ instance.extraPackages;
      serviceConfig = {
        Type = "oneshot";
        CacheDirectory = "restic-${name}";
        LoadCredential = credentials instance;
        PrivateTmp = true;
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        ${ensureRepository instance}
        ${lib.optionalString (instance.cleanup != null) "trap ${lib.escapeShellArg instance.cleanup} EXIT"}
        ${lib.optionalString (instance.prepare != null) instance.prepare}
        restic backup ${tagArgs instance} ${lib.escapeShellArgs instance.paths} ${lib.concatMapStringsSep " " (exclude: "--exclude ${lib.escapeShellArg exclude}") (excludes instance)}

        metric=/var/lib/node-exporter-textfile/restic_${name}.prom
        printf 'restic_backup_last_success_timestamp_seconds{instance="%s"} %s\n' \
          ${lib.escapeShellArg name} "$(date +%s)" > "$metric.tmp"
        chmod 0644 "$metric.tmp"
        mv "$metric.tmp" "$metric"
      '';
    }
  ) cfg.instances;

  backupTimers = lib.mapAttrs' (name: instance:
    lib.nameValuePair "backup-${name}" {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = instance.schedule;
        Persistent = true;
        RandomizedDelaySec = instance.randomDelay;
      };
    }
  ) cfg.instances;

  restoreServices = lib.mapAttrs' (name: instance:
    lib.nameValuePair "restore-${name}" {
      description = "Restore ${name} when its state is empty";
      inherit (instance) before requiredBy;
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ] ++ instance.after;
      requires = instance.after;
      unitConfig.RequiresMountsFor = lib.optional
        (instance.restoreMarker != null)
        instance.restoreMarker;
      path = [ pkgs.restic pkgs.jq pkgs.coreutils pkgs.util-linux ] ++ instance.extraPackages;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        CacheDirectory = "restic-${name}";
        LoadCredential = credentials instance;
        PrivateTmp = true;
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        if ${hasCompleteState instance}
        then
          echo "${name} already has state; skipping restore"
          exit 0
        fi

        ${ensureRepository instance}
        if [ "$(restic snapshots ${tagArgs instance} --json | jq 'length')" -eq 0 ]; then
          echo "No ${name} snapshots found; skipping restore"
          exit 0
        fi

        ${lib.optionalString (instance.restoreMarker != null) "touch ${lib.escapeShellArg instance.restoreMarker}"}
        ${instance.restore}
        ${lib.optionalString (instance.restoreMarker != null) "rm -f ${lib.escapeShellArg instance.restoreMarker}"}
      '';
    }
  ) cfg.instances;
in {
  options.homelab.backups = {
    serverUrl = lib.mkOption {
      type = lib.types.str;
      description = "Base URL of the homelab REST server.";
    };

    instances = lib.mkOption {
      default = {};
      description = "Restic backups keyed by service name.";
      type = lib.types.attrsOf (lib.types.submodule ({ name, config, ... }: {
        options = {
          repository = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Repository name on the REST server.";
          };

          username = lib.mkOption {
            type = lib.types.str;
            default = config.repository;
            description = "REST server user.";
          };

          restPasswordFile = lib.mkOption {
            type = lib.types.str;
            description = "File containing the REST server password.";
          };

          encryptionPasswordFile = lib.mkOption {
            type = lib.types.str;
            description = "File containing the repository encryption password.";
          };

          paths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Paths included in each snapshot.";
          };

          excludes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Paths excluded from snapshots.";
          };

          tag = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional snapshot tag for a shared repository.";
          };

          prepare = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
            description = "Commands run before a snapshot.";
          };

          cleanup = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
            description = "Commands run after a snapshot attempt.";
          };

          hasData = lib.mkOption {
            type = lib.types.lines;
            description = "Shell test which succeeds when state already exists.";
          };

          restore = lib.mkOption {
            type = lib.types.lines;
            description = "Commands which restore the latest snapshot.";
          };

          restoreMarker = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Persistent marker left behind when a restore fails.";
          };

          before = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "${name}.service" ];
            description = "Units which start after restore.";
          };

          requiredBy = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "${name}.service" ];
            description = "Units which require restore.";
          };

          after = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Units which must start before restore.";
          };

          extraPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [];
            description = "Extra commands available during backup and restore.";
          };

          schedule = lib.mkOption {
            type = lib.types.str;
            default = "daily";
            description = "Backup schedule.";
          };

          randomDelay = lib.mkOption {
            type = lib.types.str;
            default = "30m";
            description = "Maximum random delay before backup.";
          };
        };
      }));
    };
  };

  config = lib.mkIf (cfg.instances != {}) {
    systemd.services = backupServices // restoreServices;
    systemd.timers = backupTimers;

    services.prometheus.exporters.node = {
      enabledCollectors = [ "textfile" ];
      extraFlags = [ "--collector.textfile.directory=/var/lib/node-exporter-textfile" ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/node-exporter-textfile 0755 root root -"
    ];
  };
}
