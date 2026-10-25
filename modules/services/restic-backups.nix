{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.backups;

  resticEnvironment = instance: ''
    export RESTIC_REPOSITORY=${lib.escapeShellArg "rest:${cfg.serverUrl}/${instance.repository}"}
    export RESTIC_REST_USERNAME=${lib.escapeShellArg instance.username}
    export RESTIC_REST_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/password")"
    export RESTIC_PASSWORD_FILE="$CREDENTIALS_DIRECTORY/password"
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

  tagArgs = instance:
    lib.optionalString (instance.tag != null) "--tag ${lib.escapeShellArg instance.tag}";

  restoreCommands = lib.mapAttrsToList (name: instance:
    pkgs.writeShellApplication {
      name = "restore-${name}";
      runtimeInputs = [ pkgs.restic pkgs.coreutils pkgs.util-linux pkgs.systemd ] ++ instance.extraPackages;
      text = ''
        restoreName=${lib.escapeShellArg name}
        restoreDirectory=${lib.escapeShellArg instance.restoreDirectory}
        restoreTagArgs=(${tagArgs instance})
        restoreLock=/run/backup-${name}.lock
        restoreRepository=${lib.escapeShellArg "rest:${cfg.serverUrl}/${instance.repository}"}
        restoreUsername=${lib.escapeShellArg instance.username}
        restorePasswordFile=${lib.escapeShellArg instance.passwordFile}
        preRestore() {
          ${instance.preRestoreScript}
          :
        }
        postRestore() {
          ${instance.postRestoreScript}
          :
        }
        ${builtins.readFile ./restore-directory.sh}
      '';
    }
  ) cfg.instances;

  backupServices = lib.mapAttrs' (name: instance:
    lib.nameValuePair "backup-${name}" {
      description = "Back up ${name}";
      path = [ pkgs.restic pkgs.coreutils pkgs.util-linux ] ++ instance.extraPackages;
      serviceConfig = {
        Type = "oneshot";
        CacheDirectory = "restic-${name}";
        LoadCredential = [ "password:${instance.passwordFile}" ];
        PrivateTmp = true;
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        exec 8>/run/backup-${name}.lock
        flock -n 8
        ${ensureRepository instance}
        ${lib.optionalString (instance.cleanup != null) "trap ${lib.escapeShellArg instance.cleanup} EXIT"}
        ${lib.optionalString (instance.prepare != null) instance.prepare}
        ${instance.preBackupScript}
        restic backup ${tagArgs instance} ${lib.escapeShellArgs instance.paths} ${lib.concatMapStringsSep " " (exclude: "--exclude ${lib.escapeShellArg exclude}") instance.excludes}
        ${instance.postBackupScript}

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

          passwordFile = lib.mkOption {
            type = lib.types.str;
            description = "Password file used for both REST access and repository encryption.";
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

          preBackupScript = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Commands run before backup. Failure stops the backup.";
          };

          postBackupScript = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Commands run after a successful backup.";
          };

          restoreDirectory = lib.mkOption {
            type = lib.types.str;
            description = "Directory restored in place by restore-<name>. Files absent from the snapshot are not deleted.";
          };

          preRestoreScript = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Commands run before restore. Failure stops the restore.";
          };

          postRestoreScript = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Commands run after a successful restore.";
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
    assertions = lib.mapAttrsToList (name: instance: {
      assertion = lib.hasPrefix "/" instance.restoreDirectory
        && instance.restoreDirectory != "/"
        && lib.elem instance.restoreDirectory instance.paths;
      message = "Backup ${name} needs an absolute restore directory included in its backup paths.";
    }) cfg.instances;

    environment.systemPackages = restoreCommands;
    systemd.services = backupServices;
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
