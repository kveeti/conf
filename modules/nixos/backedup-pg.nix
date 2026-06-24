{ config, lib, pkgs, ... }:

let
  cfg = config.services.backedupPg;
  instances = lib.attrValues cfg.instances;
  pgPkg = cfg.postgresPackage;

  dumpPath = db: "/tmp/pg-${db}.dump";
in {
  imports = [ ./homelab-backups.nix ];

  options.services.backedupPg = {
    postgresPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.postgresql_18;
      description = "Postgres package used for the server, dumps, and restores.";
    };
    repositoryFile = lib.mkOption {
      type = lib.types.str;
      description = "Restic repository file (shared by all instances in this guest).";
    };
    passwordFile = lib.mkOption {
      type = lib.types.str;
      description = "Restic encryption password file (shared by all instances).";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/state";
      description = "Persisted state root; the postgres data dir is bind-mounted off it.";
    };
    instances = lib.mkOption {
      default = {};
      description = "Postgres-backed services keyed by name.";
      type = lib.types.attrsOf (lib.types.submodule ({ name, config, ... }: {
        options = {
          database = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Database and owner-role name.";
          };
          units = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "${name}.service" ];
            description = "Units that must wait for the database to be ready.";
          };
          tag = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = config.database;
            description = ''
              Restic tag for this instance's snapshots. Defaults to the database
              name so multiple instances can share one repo. Set to null for a
              single-service repo (no tag filter on backup or autorestore).
            '';
          };
        };
      }));
    };
  };

  config = lib.mkIf (cfg.instances != {}) {
    services.postgresql = {
      enable = true;
      enableJIT = true;
      package = cfg.postgresPackage;
      ensureDatabases = map (i: i.database) instances;
      ensureUsers =
        [{ name = "root"; ensureClauses = { login = true; superuser = true; }; }]
        ++ map (i: {
          name = i.database;
          ensureDBOwnership = true;
          ensureClauses = { login = true; superuser = false; };
        }) instances;
    };

    services.prometheus.exporters.postgres = {
      enable = true;
      listenAddress = "127.0.0.1";
      runAsLocalSuperUser = true;
    };
    homelab.metrics.scrapeConfigs = [{
      job_name = "postgres";
      static_configs = [{ targets = [ "127.0.0.1:9187" ]; }];
    }];

    systemd.tmpfiles.rules = [ "d ${cfg.stateDir}/postgresql 0750 postgres postgres -" ];
    fileSystems."/var/lib/postgresql" = {
      device = "${cfg.stateDir}/postgresql";
      options = [ "bind" ];
      depends = [ cfg.stateDir ];
    };

    homelab.backups.instances = lib.mapAttrs' (_: i:
      let tagFlag = lib.optionalString (i.tag != null) "--tag ${i.tag}"; in
      lib.nameValuePair i.database {
        repositoryFile = cfg.repositoryFile;
        passwordFile   = cfg.passwordFile;
        tag = i.tag;
        paths = [ (dumpPath i.database) ];
        prepare = "${pgPkg}/bin/pg_dump -Fc --no-owner --no-acl ${i.database} > ${dumpPath i.database}";
        cleanup = "rm -f ${dumpPath i.database}";
        before     = i.units;
        requiredBy = i.units;
        after      = [ "postgresql-setup.service" ];
        extraPackages = [ pgPkg ];
        hasData = ''[ "$(psql -U root -d ${i.database} -tAc "select count(*) from information_schema.tables where table_schema='public'")" -ne 0 ]'';
        restore = ''
          restic dump ${tagFlag} latest ${dumpPath i.database} > ${dumpPath i.database}
          pg_restore --no-owner --role=${i.database} --clean --if-exists -U root -d ${i.database} ${dumpPath i.database}
          rm -f ${dumpPath i.database}
        '';
      }
    ) cfg.instances;

    systemd.services = lib.mkMerge (map (i:
      lib.genAttrs i.units (_: {
        after    = [ "postgresql-setup.service" ];
        requires = [ "postgresql-setup.service" ];
      })
    ) instances);
  };
}
