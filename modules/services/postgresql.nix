{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.postgresql;
  databaseNames = lib.attrNames cfg.databases;
in {
  imports = [ ./restic-backups.nix ];

  options.homelab.postgresql = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.postgresql_18;
      description = "PostgreSQL package used by the server and backup jobs.";
    };

    databases = lib.mkOption {
      default = {};
      description = "Service databases keyed by database name.";
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          services = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ name ];
            description = "Systemd services which need this database.";
          };

          backup = {
            passwordFile = lib.mkOption {
              type = lib.types.str;
              description = "Password file for both REST access and repository encryption.";
            };

            repository = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Repository name on the REST server.";
            };

            tag = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional snapshot tag for a shared repository.";
            };
          };
        };
      }));
    };
  };

  config = lib.mkIf (cfg.databases != {}) {
    services.postgresql = {
      enable = true;
      enableJIT = true;
      enableTCPIP = false;
      package = cfg.package;
      settings.listen_addresses = lib.mkForce "";
      authentication = lib.mkForce ''
        local all postgres peer
        local all root peer
        local sameuser all peer
        local all all reject
      '';
      ensureDatabases = databaseNames;
      ensureUsers =
        [{
          name = "root";
          ensureClauses = {
            login = true;
            superuser = true;
          };
        }]
        ++ map (name: {
          inherit name;
          ensureDBOwnership = true;
          ensureClauses = {
            login = true;
            superuser = false;
          };
        }) databaseNames;
    };

    services.prometheus.exporters.postgres = {
      enable = true;
      listenAddress = "127.0.0.1";
      runAsLocalSuperUser = true;
    };

    homelab.metrics.scrapes.postgres.targets = [
      "127.0.0.1:${toString config.services.prometheus.exporters.postgres.port}"
    ];

    homelab.backups.instances = lib.mapAttrs (name: database:
      let
        directory = "/var/lib/postgresql-backups/${name}";
        dump = "${directory}/database.dump";
        units = lib.escapeShellArgs (map (service: "${service}.service") database.services);
      in {
        repository = database.backup.repository;
        tag = database.backup.tag;
        passwordFile = database.backup.passwordFile;
        extraPackages = [ cfg.package ];
        paths = [ directory ];
        preBackupScript = ''
          install -d -m 0700 ${directory}
          pg_dump -U root -Fc --no-owner --no-acl ${name} > ${dump}.tmp
          mv ${dump}.tmp ${dump}
        '';
        restoreDirectory = directory;
        preRestoreScript = lib.optionalString (database.services != []) ''
          systemctl stop ${units}
        '';
        postRestoreScript = ''
          pg_restore --single-transaction --no-owner --role=${name} --clean --if-exists \
            -U root -d ${name} ${dump}
          ${lib.optionalString (database.services != []) "systemctl start ${units}"}
        '';
      }
    ) cfg.databases;

    systemd.services = lib.mkMerge (lib.mapAttrsToList (_: database:
      lib.genAttrs database.services (_: {
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
      })
    ) cfg.databases);
  };
}
