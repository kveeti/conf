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
    if ! restic cat config >/dev/null 2>&1; then
      restic init
    fi
  '';

  credentials = instance: [
    "rest-password:${instance.restPasswordFile}"
    "encryption-password:${instance.encryptionPasswordFile}"
  ];

  backupServices = lib.mapAttrs' (name: instance:
    lib.nameValuePair "backup-${name}" {
      description = "Back up ${name}";
      path = [ pkgs.restic pkgs.coreutils ] ++ instance.extraPackages;
      serviceConfig = {
        Type = "oneshot";
        CacheDirectory = "restic-${name}";
        LoadCredential = credentials instance;
      };
      script = ''
        set -euo pipefail
        ${ensureRepository instance}
        ${lib.optionalString (instance.cleanup != null) "trap ${lib.escapeShellArg instance.cleanup} EXIT"}
        ${lib.optionalString (instance.prepare != null) instance.prepare}
        restic backup ${lib.escapeShellArgs instance.paths} ${lib.concatMapStringsSep " " (exclude: "--exclude ${lib.escapeShellArg exclude}") instance.excludes}

        metric=/var/lib/node-exporter-textfile/restic_${name}.prom
        printf 'restic_backup_last_success_timestamp_seconds{instance="%s"} %s\n' \
          ${lib.escapeShellArg name} "$(date +%s)" > "$metric.tmp"
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
      inherit (instance) before requiredBy after;
      requires = instance.after;
      path = [ pkgs.restic pkgs.jq pkgs.coreutils ] ++ instance.extraPackages;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        CacheDirectory = "restic-${name}";
        LoadCredential = credentials instance;
      };
      script = ''
        set -euo pipefail
        if ${instance.hasData}
        then
          echo "${name} already has state; skipping restore"
          exit 0
        fi

        ${ensureRepository instance}
        if [ "$(restic snapshots --json | jq 'length')" -eq 0 ]; then
          echo "No ${name} snapshots found; skipping restore"
          exit 0
        fi

        ${instance.restore}
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
