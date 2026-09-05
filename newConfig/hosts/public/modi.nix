{ config, pkgs, ... }:

let
  waitForMongo = pkgs.writeShellScript "wait-for-modi-mongo" ''
    ready=false
    for _ in $(seq 1 60); do
      if ${pkgs.podman}/bin/podman exec modi-mongo mongosh \
        "mongodb://mongo:mongo@127.0.0.1:27017/admin?authSource=admin&serverSelectionTimeoutMS=1000" \
        --quiet --eval 'db.adminCommand("ping").ok' >/dev/null 2>&1; then
        ready=true
        break
      fi
      sleep 1
    done

    if [ "$ready" != true ]; then
      echo "MongoDB did not become ready within 60 seconds" >&2
      exit 1
    fi
  '';

  mongoHasData = pkgs.writeShellScript "modi-mongo-has-data" ''
    ${waitForMongo}
    count=$(${pkgs.podman}/bin/podman exec modi-mongo mongosh \
      "mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin" \
      --quiet --eval 'db.getCollectionNames().length')
    [ "$count" != "0" ]
  '';
in {
  age.secrets.modi-env = {};
  age.secrets.restic-modi-rest-pass = {};
  age.secrets.restic-modi-encryption-pass = {};

  systemd.tmpfiles.rules = [ "d /var/lib/mongo 0755 root root -" ];

  virtualisation.oci-containers.containers = {
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
    podman-modi-mongo.unitConfig.RequiresMountsFor = [
      "/var/lib/mongo"
      "/var/lib/containers"
    ];
    podman-modi.unitConfig.RequiresMountsFor = [ "/var/lib/containers" ];

    backup-modi = {
      after = [ "podman-modi-mongo.service" ];
      requires = [ "podman-modi-mongo.service" ];
    };
  };

  homelab.backups.instances.modi = {
    repository = "rest:https://backup.internal.veetik.com:8000/modi";
    restPasswordFile = config.age.secrets.restic-modi-rest-pass.path;
    encryptionPasswordFile = config.age.secrets.restic-modi-encryption-pass.path;
    paths = [ "/tmp/modi.archive" ];
    before = [ "podman-modi.service" ];
    requiredBy = [ "podman-modi.service" ];
    after = [ "podman-modi-mongo.service" ];
    extraPackages = [ pkgs.mongodb-tools ];
    prepare = ''
      ${waitForMongo}
      mongodump \
        --uri="mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin" \
        --archive=/tmp/modi.archive
    '';
    cleanup = "rm -f /tmp/modi.archive";
    hasData = "${mongoHasData}";
    restore = ''
      restic dump latest /tmp/modi.archive > /tmp/modi.archive.restore
      mongorestore \
        --uri="mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin" \
        --archive=/tmp/modi.archive.restore
      rm -f /tmp/modi.archive.restore
    '';
  };

  homelab.logs.units = {
    "podman-modi.service" = {
      format = "auto";
      serviceName = "modi";
    };
    "podman-modi-mongo.service" = {
      format = "auto";
      serviceName = "modi-mongo";
    };
  };
}
