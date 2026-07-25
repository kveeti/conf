{ config, secretDerive, ... }:

let
  vmName = "tasks";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;

    secrets = [
      { name = "tasks-backend-env"; }
      { name = "telemetry-pass"; mode = "0400"; }
      { name = "restic-tasks-encryption-pass"; }
      {
        name = "restic-tasks-repo";
        value = secretDerive ''
          printf 'rest:https://tasks:%s@backup.internal.veetik.com:8000/tasks' \
            "$(cat ${config.age.secrets.restic-tasks-rest-pass.path})"
        '';
      }
    ];

    shares.ssh-host = {
      owner = "root"; group = "root"; mode = "0755";
      path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
    };

    vm = {
    specialArgs = { inherit (config._module.args) keys guestIps publicGateways; };
    config = { config, pkgs, lib, keys, guestIps, publicGateways, ... }: {
      imports = [ ../_common.nix ../../../modules/nixos/homelab-volumes.nix ../../../modules/nixos/backedup-pg.nix ];

      networking.hostName = "tasks";

      microvm.mem = lib.mkForce 512;

      microvm.interfaces = [{
        type = "tap";
        id = "vm-tasks";
        mac = "02:00:00:66:00:02";
      }];

      homelab.volumes.containers = { owner = "root"; mode = "0755"; };

      systemd.network.enable = true;
      systemd.network.networks."10-eth" = {
        matchConfig.Type = "ether";
        address = [ "${guestIps.tasks}/30" ];
        routes = [{ Gateway = publicGateways.tasks; }];
        networkConfig.DHCP = "no";
      };

      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ 22 8000 ];
      };

      services.backedupPg = {
        postgresPackage = pkgs.postgresql_18;
        repositoryFile = "/run/secrets/restic-tasks-repo";
        passwordFile   = "/run/secrets/restic-tasks-encryption-pass";
        instances.tasks = {
          tag = null;
          units = [ "podman-tasks.service" ];
        };
      };

      users.users.tasks = {
        isSystemUser = true;
        group = "tasks";
      };
      users.groups.tasks = {};

      virtualisation = {
        containers.enable = true;
        oci-containers.backend = "podman";
        podman.enable = true;
      };

      virtualisation.oci-containers.containers.tasks = {
        image = "docker.io/veetik/tasks-backend@sha256:902c63258c27a60bd911ab4d6360bba7f96714e4076a7800bd9d92b7fbeb3d4c";
        user = "tasks";
        extraOptions = [ "--hostuser=tasks" "--network=host" ];
        volumes = [
          "/run/postgresql:/run/postgresql"
          "/run/secrets/tasks-backend-env:/.env:ro"
        ];
        environment = {
          DATABASE_URL = "postgresql://tasks@127.0.0.1/tasks?host=/run/postgresql";
        };
      };

      systemd.services.podman-tasks = {
        after    = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
        unitConfig.RequiresMountsFor = "/var/lib/containers";
      };
    };
    };
  };
}
