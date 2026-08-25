{ config, lib, secretDerive, keys, guestIps, publicGateways, ... }:

let
  vmName = "auth";
  stateRoot = "/var/lib/microvms/${vmName}";

  privateSecrets = [
    "keycloak-config-client-secret"
    "keycloak-google-client-id"
    "keycloak-google-client-secret"
    "oidc-rss-client-secret"
    "oidc-paperless-client-secret"
    "oidc-grafana-client-secret"
    "oidc-money-client-secret"
    "restic-auth-encryption-pass"
  ];
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;
    certDomains = [ "internal.veetik.com" ];

    secrets = (map (name: { inherit name; mode = "0400"; }) privateSecrets) ++ [
      { name = "telemetry-pass"; mode = "0400"; }
      {
        name = "restic-auth-repo";
        value = secretDerive ''
          printf 'rest:https://auth:%s@backup.internal.veetik.com:8000/auth' \
            "$(cat ${config.age.secrets.restic-auth-rest-pass.path})"
        '';
      }
    ];

    shares.ssh-host = {
      owner = "root"; group = "root"; mode = "0755";
      path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
    };

    vm = {
      specialArgs = { inherit keys guestIps publicGateways; };
      config = { config, pkgs, lib, keys, guestIps, publicGateways, ... }:
      let
        withInternalVhost = vhost: {
          forceSSL = true;
          sslCertificate = "/run/cert/internal.veetik.com/fullchain.pem";
          sslCertificateKey = "/run/cert/internal.veetik.com/key.pem";
        } // vhost;
      in {
        imports = [
          ../_common.nix
          ../../../modules/nixos/homelab-volumes.nix
          ../../../modules/nixos/homelab-nginx-metrics.nix
          ../../../modules/nixos/backedup-pg.nix
          ./keycloak.nix
        ];

        _module.args = { inherit withInternalVhost; };

        networking.hostName = "auth";
        networking.hosts."127.0.0.1" = [ "auth.internal.veetik.com" ];

        microvm.mem = lib.mkForce 2048;

        microvm.interfaces = [{
          type = "tap";
          id = "vm-auth";
          mac = "02:00:00:66:00:05";
        }];

        microvm.volumes = [{
          image = "${stateRoot}/state.img";
          mountPoint = "/var/lib/state";
          size = 8192;
        }];

        systemd.network.enable = true;
        systemd.network.networks."10-eth" = {
          matchConfig.Type = "ether";
          address = [ "${guestIps.auth}/30" ];
          routes = [{ Gateway = publicGateways.auth; }];
          networkConfig.DHCP = "no";
        };

        networking.firewall = {
          enable = true;
          # The router only permits nginx-public to reach 8080 from routed VLANs.
          allowedTCPPorts = [ 22 443 8080 ];
        };

        homelab.backups = {
          repositoryFile = "/run/secrets/restic-auth-repo";
          passwordFile = "/run/secrets/restic-auth-encryption-pass";
        };

        services.backedupPg = {
          postgresPackage = pkgs.postgresql_18;
          repositoryFile = "/run/secrets/restic-auth-repo";
          passwordFile = "/run/secrets/restic-auth-encryption-pass";
          instances.keycloak.units = [ "keycloak.service" ];
        };

        homelab.nginxMetrics.enable = true;

        services.nginx = {
          enable = true;
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedProxySettings = true;
          recommendedTlsSettings = true;
        };
      };
    };
  };
}
