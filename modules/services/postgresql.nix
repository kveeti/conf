{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.postgresql;
  databaseNames = lib.attrNames cfg.databases;
  dumpPath = database: "/tmp/pg-${database}.dump";
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
      type = lib.types.attrsOf (lib.types.submodule ({ name, config, ... }: {
        options = {
          services = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ name ];
            description = "Systemd services which need this database.";
          };

          backup = {
            manualRestore = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Use an explicit restore command instead of automatic startup recovery.";
            };

            passwordFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
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

            restPasswordFile = lib.mkOption {
              type = lib.types.str;
              default = if config.backup.passwordFile != null then config.backup.passwordFile
                else throw "Database ${name}: set passwordFile or restPasswordFile.";
              description = "REST password file. Defaults to passwordFile.";
            };

            encryptionPasswordFile = lib.mkOption {
              type = lib.types.str;
              default = if config.backup.passwordFile != null then config.backup.passwordFile
                else throw "Database ${name}: set passwordFile or encryptionPasswordFile.";
              description = "Repository encryption password file. Defaults to passwordFile.";
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
        restPasswordFile = database.backup.restPasswordFile;
        encryptionPasswordFile = database.backup.encryptionPasswordFile;
        extraPackages = [ cfg.package ];
      } // (if database.backup.manualRestore then {
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
      } else {
        paths = [ (dumpPath name) ];
        prepare = ''
          rm -f ${dumpPath name}
          ${cfg.package}/bin/pg_dump -Fc --no-owner --no-acl ${name} > ${dumpPath name}
        '';
        cleanup = "rm -f ${dumpPath name}";
        before = map (service: "${service}.service") database.services;
        requiredBy = map (service: "${service}.service") database.services;
        after = [ "postgresql-setup.service" ];
        hasData = ''
          [ "$(psql -U root -d ${name} -tAc "select count(*) from information_schema.tables where table_schema='public'")" -ne 0 ]
        '';
        restore = ''
          restic dump ${lib.optionalString (database.backup.tag != null) "--tag ${lib.escapeShellArg database.backup.tag}"} latest ${dumpPath name} > ${dumpPath name}
          pg_restore --single-transaction --no-owner --role=${name} --clean --if-exists \
            -U root -d ${name} ${dumpPath name}
          rm -f ${dumpPath name}
        '';
      })
    ) cfg.databases;

    systemd.services = lib.mkMerge (lib.mapAttrsToList (_: database:
      lib.genAttrs database.services (_: {
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
      })
    ) cfg.databases);
  };
}
