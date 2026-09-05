{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.resticServer;
  repositoryNames = lib.attrNames cfg.repositories;

  htpasswd = lib.concatMapStringsSep "\n" (name: ''
    printf '%s' "$(cat ${cfg.repositories.${name}.clientPasswordFile})" \
      | ${pkgs.apacheHttpd}/bin/htpasswd -iB "$tmp" ${lib.escapeShellArg name}
  '') repositoryNames;

  pruneServices = lib.genAttrs repositoryNames (name: {
    description = "Prune the ${name} restic repository";
    path = [ pkgs.restic ];
    serviceConfig = {
      Type = "oneshot";
      User = "restic";
      Group = "restic";
      CacheDirectory = "restic";
      LoadCredential = [ "password:${cfg.repositories.${name}.encryptionPasswordFile}" ];
    };
    environment = {
      RESTIC_REPOSITORY = "${cfg.dataDir}/${name}";
      RESTIC_CACHE_DIR = "/var/cache/restic";
    };
    script = ''
      export RESTIC_PASSWORD_FILE="$CREDENTIALS_DIRECTORY/password"

      if ! restic cat config >/dev/null 2>&1; then
        echo "repository is not initialized, skipping"
        exit 0
      fi

      restic forget --prune --keep-daily ${toString cfg.prune.keepDaily}
    '';
  });

  pruneTimers = lib.genAttrs repositoryNames (_: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = cfg.prune.schedule;
      Persistent = true;
      RandomizedDelaySec = cfg.prune.randomDelay;
    };
  });

  archiveServices = lib.genAttrs repositoryNames (name: {
    description = "Archive the ${name} restic repository";
    path = [ pkgs.restic ];
    unitConfig.ConditionPathIsMountPoint = cfg.archive.dataDir;
    serviceConfig = {
      Type = "oneshot";
      CacheDirectory = "restic-archive";
      LoadCredential = [ "password:${cfg.repositories.${name}.encryptionPasswordFile}" ];
    };
    environment.RESTIC_CACHE_DIR = "/var/cache/restic-archive";
    script = ''
      export RESTIC_PASSWORD_FILE="$CREDENTIALS_DIRECTORY/password"
      source=${lib.escapeShellArg "${cfg.dataDir}/${name}"}
      target=${lib.escapeShellArg "${cfg.archive.dataDir}/${name}"}

      if ! restic --repo "$source" cat config >/dev/null 2>&1; then
        echo "source repository is not initialized, skipping"
        exit 0
      fi

      if ! restic --repo "$target" cat config >/dev/null 2>&1; then
        restic --repo "$target" init
      fi

      restic --repo "$target" copy \
        --from-repo "$source" \
        --from-password-file "$RESTIC_PASSWORD_FILE"
      restic --repo "$target" forget --prune \
        --keep-daily ${toString cfg.archive.keepDaily} \
        --keep-weekly ${toString cfg.archive.keepWeekly} \
        --keep-monthly ${toString cfg.archive.keepMonthly}
    '';
  });

  archiveTimers = lib.genAttrs repositoryNames (_: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = cfg.archive.schedule;
      Persistent = true;
      RandomizedDelaySec = cfg.archive.randomDelay;
    };
  });
in {
  options.homelab.resticServer = {
    enable = lib.mkEnableOption "the homelab restic server";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/restic";
      description = "Directory containing the primary repositories.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8001";
      description = "Private rest-server listen address.";
    };

    repositories = lib.mkOption {
      default = {};
      description = "Repositories served by this host.";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          clientPasswordFile = lib.mkOption {
            type = lib.types.str;
            description = "File containing the REST API password.";
          };

          encryptionPasswordFile = lib.mkOption {
            type = lib.types.str;
            description = "File containing the repository encryption password.";
          };
        };
      });
    };

    prune = {
      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Primary repository prune schedule.";
      };

      randomDelay = lib.mkOption {
        type = lib.types.str;
        default = "1h";
        description = "Maximum random delay before pruning.";
      };

      keepDaily = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = "Daily snapshots kept in primary repositories.";
      };
    };

    archive = {
      enable = lib.mkEnableOption "a second copy on archive storage";

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/restic-archive";
        description = "Directory containing archive repositories.";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Archive copy schedule.";
      };

      randomDelay = lib.mkOption {
        type = lib.types.str;
        default = "2h";
        description = "Maximum random delay before archive copies.";
      };

      keepDaily = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = "Daily snapshots kept in archive repositories.";
      };

      keepWeekly = lib.mkOption {
        type = lib.types.ints.positive;
        default = 12;
        description = "Weekly snapshots kept in archive repositories.";
      };

      keepMonthly = lib.mkOption {
        type = lib.types.ints.positive;
        default = 24;
        description = "Monthly snapshots kept in archive repositories.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.repositories != {};
      message = "homelab.resticServer.repositories must not be empty";
    }];

    services.restic.server = {
      enable = true;
      inherit (cfg) dataDir listenAddress;
      appendOnly = true;
      privateRepos = true;
      htpasswd-file = "${cfg.dataDir}/.htpasswd";
    };

    system.activationScripts.restic-htpasswd = {
      deps = [ "agenix" "users" ];
      text = ''
        install -d -m 0750 -o restic -g restic ${cfg.dataDir}
        tmp=$(mktemp ${cfg.dataDir}/.htpasswd.XXXXXX)
        chmod 0600 "$tmp"
        ${htpasswd}
        chown restic:restic "$tmp"
        mv -f "$tmp" ${cfg.dataDir}/.htpasswd
      '';
    };

    systemd.services =
      lib.mapAttrs' (name: value: lib.nameValuePair "restic-${name}-prune" value) pruneServices
      // lib.optionalAttrs cfg.archive.enable
        (lib.mapAttrs' (name: value: lib.nameValuePair "restic-${name}-archive" value) archiveServices);

    systemd.timers =
      lib.mapAttrs' (name: value: lib.nameValuePair "restic-${name}-prune" value) pruneTimers
      // lib.optionalAttrs cfg.archive.enable
        (lib.mapAttrs' (name: value: lib.nameValuePair "restic-${name}-archive" value) archiveTimers);

    fileSystems.${cfg.archive.dataDir}.options = lib.mkIf cfg.archive.enable [
      "nofail"
      "x-systemd.device-timeout=15s"
    ];
  };
}
