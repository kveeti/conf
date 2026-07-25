{ config, secretDerive, ... }:

let
  vmName = "modi";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;

    secrets = [
      { name = "modi-env"; }
      { name = "telemetry-pass"; mode = "0400"; }
      { name = "restic-modi-encryption-pass"; }
      {
        name = "restic-modi-repo";
        value = secretDerive ''
          printf 'rest:https://modi:%s@backup.internal.veetik.com:8000/modi' \
            "$(cat ${config.age.secrets.restic-modi-rest-pass.path})"
        '';
      }
    ];

    shares.ssh-host = {
      owner = "root"; group = "root"; mode = "0755";
      path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
    };

    vm = {
    specialArgs = { inherit (config._module.args) keys guestIps publicGateways; };
    config = { config, pkgs, lib, keys, guestIps, publicGateways, ... }:
    let
      modiHasData = pkgs.writeShellScript "modi-has-data" ''
        for _ in $(seq 1 60); do
          ${pkgs.podman}/bin/podman exec modi-mongo mongosh --quiet \
            --eval 'db.adminCommand("ping").ok' >/dev/null 2>&1 && break
          sleep 1
        done
        count=$(${pkgs.podman}/bin/podman exec modi-mongo mongosh \
          "mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin" \
          --quiet --eval 'db.getCollectionNames().length' 2>/dev/null || echo 0)
        [ "$count" != "0" ]
      '';
    in {
      imports = [ ../_common.nix ../../../modules/nixos/homelab-volumes.nix ../../../modules/nixos/homelab-backups.nix ];

      networking.hostName = "modi";

      microvm.mem = lib.mkForce 512;

      microvm.interfaces = [{
        type = "tap";
        id = "vm-modi";
        mac = "02:00:00:66:00:04";
      }];

      homelab.volumes.mongo      = { owner = "root"; mode = "0755"; };
      homelab.volumes.containers = { owner = "root"; mode = "0755"; };

      systemd.network.enable = true;
      systemd.network.networks."10-eth" = {
        matchConfig.Type = "ether";
        address = [ "${guestIps.modi}/30" ];
        routes = [{ Gateway = publicGateways.modi; }];
        networkConfig.DHCP = "no";
      };

      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ 22 ];
      };

      virtualisation = {
        containers.enable = true;
        oci-containers.backend = "podman";
        podman.enable = true;
      };

      virtualisation.oci-containers.containers.modi-mongo = {
        image = "docker.io/library/mongo@sha256:a2e96682a6d92742341db59a1956569bfd2b30704acef5da034cc17e18bb7ed4";
        extraOptions = [ "--network=host" ];
        volumes = [ "/var/lib/mongo:/data/db" ];
        environment = {
          MONGO_INITDB_ROOT_USERNAME = "mongo";
          MONGO_INITDB_ROOT_PASSWORD = "mongo";
        };
      };

      virtualisation.oci-containers.containers.modi = {
        image = "docker.io/veetik/modi@sha256:acf05d673e92101c2df2fcf549e03eb6f9a39fb204e8620a72a00d8ea0ddd633";
        dependsOn = [ "modi-mongo" ];
        extraOptions = [ "--network=host" ];
        volumes = [
          # dotenv reads /app/.env
          "/run/secrets/modi-env:/app/.env:ro"
        ];
        environment = {
          MONGO_URI = "mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin";
        };
      };

      # mount before start, else podman populates the bind target on tmpfs
      systemd.services.podman-modi-mongo.unitConfig.RequiresMountsFor = [ "/var/lib/mongo" "/var/lib/containers" ];
      systemd.services.podman-modi.unitConfig.RequiresMountsFor = "/var/lib/containers";

      homelab.backups = {
        repositoryFile = "/run/secrets/restic-modi-repo";
        passwordFile   = "/run/secrets/restic-modi-encryption-pass";
        instances.modi = {
          tag = null;
          paths = [ "/tmp/modi.archive" ];
          before     = [ "podman-modi.service" ];
          after      = [ "podman-modi-mongo.service" ];
          requiredBy = [ "podman-modi.service" ];
          extraPackages = [ pkgs.mongodb-tools ];
          prepare = ''
            for _ in $(seq 1 60); do
              if ${pkgs.podman}/bin/podman exec modi-mongo mongosh --quiet \
                --eval 'db.adminCommand("ping").ok' >/dev/null 2>&1; then
                break
              fi
              sleep 1
            done
            ${pkgs.mongodb-tools}/bin/mongodump \
              --uri="mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin" \
              --archive=/tmp/modi.archive
          '';
          cleanup = "rm -f /tmp/modi.archive";
          hasData = "${modiHasData}";
          restore = ''
            restic dump latest /tmp/modi.archive > /tmp/modi.archive.restore
            mongorestore --uri="mongodb://mongo:mongo@127.0.0.1:27017/modi?authSource=admin" \
              --archive=/tmp/modi.archive.restore
            rm -f /tmp/modi.archive.restore
          '';
        };
      };
      # backup needs mongo up first
      systemd.services.restic-backups-modi = {
        after    = [ "podman-modi-mongo.service" ];
        requires = [ "podman-modi-mongo.service" ];
      };
    };
    };
  };
}
