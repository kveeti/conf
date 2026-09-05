{ config, pkgs, money, ... }:

let
  derivedSecretDir = "/run/public-secrets";
  modiWaitUntilReady = pkgs.writeShellScript "modi-wait-until-ready" ''
    ready=false
    for _ in $(seq 1 60); do
      if ${pkgs.podman}/bin/podman exec modi-mongo sh -c \
        '[ "$(cat /proc/1/comm)" = mongod ]'; then
        ready=true
        break
      fi
      sleep 1
    done
    if [ "$ready" != true ]; then
      echo "MongoDB did not finish initialization within 60 seconds" >&2
      exit 1
    fi
    ${pkgs.podman}/bin/podman exec modi-mongo mongosh \
      "mongodb://mongo:mongo@127.0.0.1:27017/admin?authSource=admin&serverSelectionTimeoutMS=60000" \
      --quiet --eval 'db.adminCommand("ping").ok' >/dev/null
  '';
  modiHasData = pkgs.writeShellScript "modi-has-data" ''
    ${modiWaitUntilReady}
    count=$(${pkgs.podman}/bin/podman exec modi-mongo mongosh \
      "mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin" \
      --quiet --eval 'db.getCollectionNames().length')
    [ "$count" != "0" ]
  '';
in {
  imports = [ money.nixosModules.default ];

  users.users = {
    tasks = {
      isSystemUser = true;
      group = "tasks";
    };
    bm = {
      isSystemUser = true;
      group = "bm";
    };
  };
  users.groups = {
    tasks = {};
    bm = {};
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/public-state 0750 root root -"
    "d /var/lib/mongo 0755 root root -"
  ];

  services.backedupPg = {
    postgresPackage = pkgs.postgresql_18;
    stateDir = "/var/lib/public-state";
    repositoryFile = "${derivedSecretDir}/restic-auth-repo";
    passwordFile = config.age.secrets.restic-auth-encryption-pass.path;
    instances = {
      keycloak.units = [ "keycloak.service" ];
      tasks = {
        repositoryFile = "${derivedSecretDir}/restic-tasks-repo";
        passwordFile = config.age.secrets.restic-tasks-encryption-pass.path;
        tag = null;
        units = [ "podman-tasks.service" ];
      };
      bm = {
        repositoryFile = "${derivedSecretDir}/restic-bm-repo";
        passwordFile = config.age.secrets.restic-bm-encryption-pass.path;
        tag = null;
        units = [ "podman-bm.service" ];
      };
      money = {
        repositoryFile = "${derivedSecretDir}/restic-money-repo";
        passwordFile = config.age.secrets.restic-money-encryption-pass.path;
        tag = null;
        units = [ "money.service" ];
      };
    };
  };

  virtualisation = {
    containers.enable = true;
    oci-containers.backend = "podman";
    podman.enable = true;
  };

  virtualisation.oci-containers.containers = {
    tasks = {
      image = "docker.io/veetik/tasks-backend@sha256:902c63258c27a60bd911ab4d6360bba7f96714e4076a7800bd9d92b7fbeb3d4c";
      user = "tasks";
      extraOptions = [ "--hostuser=tasks" ];
      ports = [ "127.0.0.1:8001:8000" ];
      volumes = [
        "/run/postgresql:/run/postgresql"
        "${config.age.secrets.tasks-backend-env.path}:/.env:ro"
      ];
      environment.DATABASE_URL = "postgresql://tasks@127.0.0.1/tasks?host=/run/postgresql";
    };

    bm = {
      image = "docker.io/veetik/bm_backend@sha256:769200adbb782292f44f9490040a59688bb2e28e06cd739871dd7c1d5565d42a";
      user = "bm";
      extraOptions = [ "--hostuser=bm" ];
      ports = [ "127.0.0.1:8002:8000" ];
      volumes = [
        "/run/postgresql:/run/postgresql"
        "${config.age.secrets.bm-backend-env.path}:/.env:ro"
      ];
      environment.DATABASE_URL = "postgresql://bm@127.0.0.1/bm?host=/run/postgresql";
    };

    modi-mongo = {
      image = "docker.io/library/mongo@sha256:a2e96682a6d92742341db59a1956569bfd2b30704acef5da034cc17e18bb7ed4";
      extraOptions = [ "--network=host" ];
      volumes = [ "/var/lib/mongo:/data/db" ];
      environment = {
        MONGO_INITDB_ROOT_USERNAME = "mongo";
        MONGO_INITDB_ROOT_PASSWORD = "mongo";
      };
    };

    modi = {
      image = "docker.io/veetik/modi@sha256:acf05d673e92101c2df2fcf549e03eb6f9a39fb204e8620a72a00d8ea0ddd633";
      dependsOn = [ "modi-mongo" ];
      extraOptions = [ "--network=host" ];
      volumes = [ "${config.age.secrets.modi-env.path}:/app/.env:ro" ];
      environment.MONGO_URI = "mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin";
    };
  };

  systemd.services = {
    podman-tasks.after = [ "postgresql.service" ];
    podman-tasks.requires = [ "postgresql.service" ];
    podman-bm.after = [ "postgresql.service" ];
    podman-bm.requires = [ "postgresql.service" ];
    podman-modi-mongo.unitConfig.RequiresMountsFor = [ "/var/lib/mongo" "/var/lib/containers" ];
    podman-modi.unitConfig.RequiresMountsFor = "/var/lib/containers";
  };

  services.money = {
    enable = true;
    environmentFile = "${derivedSecretDir}/money-env";
    environment = {
      IS_PROD = "1";
      DEMO_MODE = "1";
      PORT = "8003";
      BACKEND_URL = "https://money.veetik.com";
      DB_URL = "postgresql://money@127.0.0.1/money?host=/run/postgresql";
      OIDC_ISSUER = "https://auth.veetik.com/realms/main";
      OIDC_CLIENT_ID = "money";
      CLIENT_IP_HEADER = "X-Forwarded-For";
      ENABLEBANKING_PRIVATE_KEY = "/run/credentials/money.service/enablebanking-private-key";
      ENABLEBANKING_ALLOWED_OIDC_SUBJECTS = "5abe0016-8773-4617-ba7e-3fe6ce892219";
    };
  };

  systemd.services.money = {
    serviceConfig.LoadCredential = [
      "enablebanking-private-key:${config.age.secrets.money-enablebanking-private-key.path}"
    ];
  };

  homelab.backups.instances.modi = {
    repositoryFile = "${derivedSecretDir}/restic-modi-repo";
    passwordFile = config.age.secrets.restic-modi-encryption-pass.path;
    tag = null;
    paths = [ "/tmp/modi.archive" ];
    before = [ "podman-modi.service" ];
    after = [ "podman-modi-mongo.service" ];
    requiredBy = [ "podman-modi.service" ];
    prepare = ''
      ${modiWaitUntilReady}
      ${pkgs.mongodb-tools}/bin/mongodump \
        --uri="mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin" \
        --archive=/tmp/modi.archive
    '';
    cleanup = "rm -f /tmp/modi.archive";
    hasData = "${modiHasData}";
    extraPackages = [ pkgs.mongodb-tools ];
    restore = ''
      restic dump latest /tmp/modi.archive > /tmp/modi.archive.restore
      mongorestore --uri="mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin" \
        --archive=/tmp/modi.archive.restore
      rm -f /tmp/modi.archive.restore
    '';
  };

  systemd.services.restic-backups-modi = {
    after = [ "podman-modi-mongo.service" ];
    requires = [ "podman-modi-mongo.service" ];
  };
}
