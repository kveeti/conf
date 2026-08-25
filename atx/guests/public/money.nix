{ config, secretDerive, money, ... }:

let
  vmName = "money";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;

    secrets = [
      {
        name = "money-env";
        mode = "0400";
        value = secretDerive ''
          printf 'OIDC_CLIENT_SECRET=%s\nENABLEBANKING_APP_ID=%s\n' \
            "$(cat ${config.age.secrets.oidc-money-client-secret.path})" \
            "$(cat ${config.age.secrets.money-enablebanking-app-id.path})"
        '';
      }
      { name = "money-enablebanking-private-key"; mode = "0400"; }
      { name = "telemetry-pass"; mode = "0400"; }
      { name = "restic-money-encryption-pass"; }
      {
        name = "restic-money-repo";
        value = secretDerive ''
          printf 'rest:https://money:%s@backup.internal.veetik.com:8000/money' \
            "$(cat ${config.age.secrets.restic-money-rest-pass.path})"
        '';
      }
    ];

    shares.ssh-host = {
      owner = "root"; group = "root"; mode = "0755";
      path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
    };

    vm = {
      specialArgs = { inherit (config._module.args) keys guestIps publicGateways money; };
      config = { config, pkgs, lib, keys, guestIps, publicGateways, money, ... }: {
        imports = [
          ../_common.nix
          ../../../modules/nixos/homelab-volumes.nix
          ../../../modules/nixos/backedup-pg.nix
          money.nixosModules.default
        ];

        networking.hostName = "money";
        networking.hosts.${guestIps.nginx-public} = [ "auth.veetik.com" ];

        microvm.mem = lib.mkForce 512;

        microvm.interfaces = [{
          type = "tap";
          id = "vm-money";
          mac = "02:00:00:66:00:06";
        }];

        homelab.volumes.money = { owner = "money"; mode = "0750"; };

        systemd.network.enable = true;
        systemd.network.networks."10-eth" = {
          matchConfig.Type = "ether";
          address = [ "${guestIps.money}/30" ];
          routes = [{ Gateway = publicGateways.money; }];
          networkConfig.DHCP = "no";
        };

        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 8000 ];
        };

        services.backedupPg = {
          postgresPackage = pkgs.postgresql_18;
          repositoryFile = "/run/secrets/restic-money-repo";
          passwordFile = "/run/secrets/restic-money-encryption-pass";
          instances.money = {
            tag = null;
            units = [ "money.service" ];
          };
        };

        services.money = {
          enable = true;
          environmentFile = "/run/secrets/money-env";
          environment = {
            IS_PROD = "1";
            DEMO_MODE = "1";
            PORT = "8000";
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
          unitConfig.RequiresMountsFor = "/var/lib/money";
          serviceConfig.LoadCredential = [
            "enablebanking-private-key:/run/secrets/money-enablebanking-private-key"
          ];
        };
      };
    };
  };
}
