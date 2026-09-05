{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.postgresql;
  databaseNames = lib.attrNames cfg.databases;
  dumpPath = database: "/tmp/postgresql-${database}.dump";
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
            repository = lib.mkOption {
              type = lib.types.str;
              description = "Restic repository URL.";
            };

            username = lib.mkOption {
              type = lib.types.str;
              default = name;
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

    homelab.metrics.scrapes.postgresql.targets = [ "127.0.0.1:9187" ];

    homelab.backups.instances = lib.mapAttrs (name: database: {
      repository = database.backup.repository;
      username = database.backup.username;
      restPasswordFile = database.backup.restPasswordFile;
      encryptionPasswordFile = database.backup.encryptionPasswordFile;
      paths = [ (dumpPath name) ];
      prepare = ''
        rm -f ${dumpPath name}
        ${cfg.package}/bin/pg_dump -Fc --no-owner --no-acl ${name} > ${dumpPath name}
      '';
      cleanup = "rm -f ${dumpPath name}";
      before = map (service: "${service}.service") database.services;
      requiredBy = map (service: "${service}.service") database.services;
      after = [ "postgresql.service" ];
      extraPackages = [ cfg.package ];
      hasData = ''
        [ "$(psql -U root -d ${name} -tAc "select count(*) from information_schema.tables where table_schema='public'")" -ne 0 ]
      '';
      restore = ''
        restic dump latest ${dumpPath name} > ${dumpPath name}
        pg_restore --no-owner --role=${name} --clean --if-exists \
          -U root -d ${name} ${dumpPath name}
        rm -f ${dumpPath name}
      '';
    }) cfg.databases;

    systemd.services = lib.mkMerge (lib.mapAttrsToList (_: database:
      lib.genAttrs database.services (_: {
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
      })
    ) cfg.databases);
  };
}
