{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.backups;

  # single ordered init per repo: concurrent first-use inits on a shared append-only
  # repo corrupt it (loser's config write 403s, orphaned key then breaks repo open)
  instanceNames = lib.attrNames cfg.instances;
  repoFileOf    = n: cfg.instances.${n}.repositoryFile;
  uniqueRepos   = lib.unique (map repoFileOf instanceNames);
  namesForRepo  = repoFile: lib.filter (n: repoFileOf n == repoFile) instanceNames;
  initUnitName  = repoFile: "restic-init-" + lib.replaceStrings [ "/" "." ] [ "-" "-" ] (lib.removePrefix "/" repoFile);

  initServices = lib.listToAttrs (map (repoFile:
    let
      names      = namesForRepo repoFile;
      dependents = lib.concatMap (n: [ "restic-backups-${n}.service" "${n}-autorestore.service" ]) names;
    in lib.nameValuePair (initUnitName repoFile) {
      description = "Initialize restic repo (${repoFile}) once before any backup/restore";
      path = [ pkgs.restic ];
      environment = {
        RESTIC_REPOSITORY_FILE = repoFile;
        RESTIC_PASSWORD_FILE   = cfg.instances.${lib.head names}.passwordFile;
      };
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      before     = dependents;
      requiredBy = dependents;
      script = ''
        set -euo pipefail
        if restic cat config >/dev/null 2>&1; then
          echo "repo already initialized"
        else
          echo "initializing repo"
          restic init
        fi
      '';
    }
  ) uniqueRepos);
  textfileMetric = name: pkgs.writeShellScript "restic-${name}-metric" ''
    export PATH=${pkgs.coreutils}/bin:$PATH
    dir=/var/lib/node-exporter-textfile
    mkdir -p "$dir"
    f="$dir/restic_${name}.prom"
    printf 'restic_backup_last_success_timestamp_seconds{instance="%s"} %s\n' \
      "${name}" "$(date +%s)" > "$f.tmp"
    mv "$f.tmp" "$f"
  '';
in {
  options.homelab.backups = {
    repositoryFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default restic repo file for instances that don't set their own.";
    };
    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default restic encryption password file for instances that don't set their own.";
    };
    instances = lib.mkOption {
      default = {};
      description = "Restic-backed state, keyed by name.";
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          repositoryFile = lib.mkOption {
            type = lib.types.str;
            default = cfg.repositoryFile;
            description = "Restic repo file for this instance.";
          };
          passwordFile = lib.mkOption {
            type = lib.types.str;
            default = cfg.passwordFile;
            description = "Restic encryption password file for this instance.";
          };
          paths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Paths restic backs up.";
          };
          excludes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Restic --exclude patterns dropped from this instance's backup.";
          };
          tag = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = name;
            description = "Snapshot tag. Defaults to the instance name; null = untagged (single-service repo).";
          };
          prepare = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
            description = "backupPrepareCommand (e.g. dump a db to a file before backup).";
          };
          cleanup = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
            description = "backupCleanupCommand (e.g. remove the dump after backup).";
          };
          hasData = lib.mkOption {
            type = lib.types.str;
            description = "Shell test, true when state already exists (autorestore skips).";
          };
          restore = lib.mkOption {
            type = lib.types.lines;
            description = "Shell snippet that restores from `latest`. Owns its own --tag.";
          };
          before = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "${name}.service" ];
            description = "Units the autorestore must run before.";
          };
          after = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Units the autorestore runs after (and requires).";
          };
          requiredBy = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "${name}.service" ];
            description = "Units that pull in the autorestore.";
          };
          extraPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [];
            description = "Extra packages on the autorestore unit's PATH.";
          };
        };
      }));
    };
  };

  config = lib.mkIf (cfg.instances != {}) {
    services.restic.backups = lib.mapAttrs (name: i: {
      inherit (i) repositoryFile passwordFile paths;
      # init owned by the shared restic-init-* oneshot; per-service init would reintroduce the race
      initialize = false;
      timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "30m"; };
    } // lib.optionalAttrs (i.prepare != null) { backupPrepareCommand = i.prepare; }
      // lib.optionalAttrs (i.cleanup != null) { backupCleanupCommand = i.cleanup; }
      // (let
           extraBackupArgs = lib.optionals (i.tag != null) [ "--tag" i.tag ]
             ++ lib.concatMap (e: [ "--exclude" e ]) i.excludes;
         in lib.optionalAttrs (extraBackupArgs != []) { inherit extraBackupArgs; })
    ) cfg.instances;

    systemd.services = initServices
      // lib.mapAttrs' (name: _:
        lib.nameValuePair "restic-backups-${name}" {
          serviceConfig.ExecStartPost = [ "${textfileMetric name}" ];
        }
      ) cfg.instances
      // lib.mapAttrs' (name: i:
      let tagFlag = lib.optionalString (i.tag != null) "--tag ${i.tag}";
      in lib.nameValuePair "${name}-autorestore" {
        description = "Auto-restore ${name} from latest backup if empty";
        inherit (i) requiredBy before after;
        requires = i.after;
        path = [ pkgs.restic pkgs.jq pkgs.coreutils ] ++ i.extraPackages;
        environment = {
          RESTIC_REPOSITORY_FILE = i.repositoryFile;
          RESTIC_PASSWORD_FILE   = i.passwordFile;
        };
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
        script = ''
          if ${i.hasData}; then
            echo "${name} already populated, skipping restore"
            exit 0
          fi
          if [ "$(restic snapshots ${tagFlag} --json | jq 'length')" -eq 0 ]; then
            echo "no ${name} snapshots in repo, skipping restore"
            exit 0
          fi
          ${i.restore}
        '';
      }
    ) cfg.instances;
  };
}
