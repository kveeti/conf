{ config, secretDerive, ... }:

let
  vmName = "bm";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;

    secrets = [
      { name = "bm-backend-env"; }
      { name = "telemetry-pass"; mode = "0400"; }
      { name = "restic-bm-encryption-pass"; }
      {
        name = "restic-bm-repo";
        value = secretDerive ''
          printf 'rest:https://bm:%s@backup.internal.veetik.com:8000/bm' \
            "$(cat ${config.age.secrets.restic-bm-rest-pass.path})"
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

        networking.hostName = "bm";

        microvm.mem = lib.mkForce 512;

        microvm.interfaces = [{
          type = "tap";
          id = "vm-bm";
          mac = "02:00:00:66:00:03";
        }];

        homelab.volumes.containers = { owner = "root"; mode = "0755"; };

        systemd.network.enable = true;
        systemd.network.networks."10-eth" = {
          matchConfig.Type = "ether";
          address = [ "${guestIps.bm}/30" ];
          routes = [{ Gateway = publicGateways.bm; }];
          networkConfig.DHCP = "no";
        };

        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 8000 ];
        };

        services.backedupPg = {
          postgresPackage = pkgs.postgresql_18;
          repositoryFile = "/run/secrets/restic-bm-repo";
          passwordFile   = "/run/secrets/restic-bm-encryption-pass";
          instances.bm = {
            tag = null;
            units = [ "podman-bm.service" ];
          };
        };

        users.users.bm = {
          isSystemUser = true;
          group = "bm";
        };
        users.groups.bm = {};

        virtualisation = {
          containers.enable = true;
          oci-containers.backend = "podman";
          podman.enable = true;
        };

        virtualisation.oci-containers.containers.bm = {
          image = "docker.io/veetik/bm_backend@sha256:769200adbb782292f44f9490040a59688bb2e28e06cd739871dd7c1d5565d42a";
          user = "bm";
          extraOptions = [ "--hostuser=bm" "--network=host" ];
          volumes = [
            "/run/postgresql:/run/postgresql"
            # dotenv reads /.env
            "/run/secrets/bm-backend-env:/.env:ro"
          ];
          environment = {
            DATABASE_URL = "postgresql://bm@127.0.0.1/bm?host=/run/postgresql";
          };
        };

        systemd.services.podman-bm = {
          after    = [ "postgresql.service" ];
          requires = [ "postgresql.service" ];
          unitConfig.RequiresMountsFor = "/var/lib/containers";
        };
      };
    };
  };
}
