{ config, lib, microvm, secretDerive, keys, guestIps, hostMgmtIp, vlanGateway, rss, food, weather, ... }:

let
  vmName = "internal";
  stateRoot = "/var/lib/microvms/${vmName}";

  guestSecrets = [
    "lldap-env"
    "lldap-user-pass"
    "lldap-user-authelia-pass"
    "lldap-user-veeti-pass"
    "lldap-user-security-pass"
    "authelia-jwt-secret"
    "authelia-hmac-secret"
    "authelia-issuer-priv-key"
    "authelia-session-secret"
    "authelia-storage-encryption-key"
    "authelia-ldap-bind-password"
    "radicale-users"
    "food-secrets"
    "weather-secrets"
    "samba-syncer-pass"
    "paperless-security-password"
    "paperless-oidc-client-secret"
    "restic-internal-encryption-pass"
  ];

in {
  homelab.dns.records = [
    "ldap.internal.veetik.com"
    "sso.internal.veetik.com"
    "dav.internal.veetik.com"
    "food.internal.veetik.com"
    "weather.internal.veetik.com"
    "p.internal.veetik.com"
    "rss.internal.veetik.com"
  ];

  homelab.microvms.${vmName} = {
    inherit stateRoot;
    certDomains = [ "internal.veetik.com" ];
    secrets = (map (name: { inherit name; }) guestSecrets) ++ [{
      name = "restic-internal-repo";
      value = secretDerive ''
        printf 'rest:https://internal:%s@backup.internal.veetik.com:8000/internal' \
          "$(cat ${config.age.secrets.restic-internal-rest-pass.path})"
      '';
    }];

    shares.ssh-host = {
      owner = "root"; group = "root"; mode = "0755";
      path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
    };

    vm = {
      specialArgs = { inherit keys guestIps hostMgmtIp vlanGateway rss food weather; };
      config = { config, pkgs, lib, keys, guestIps, hostMgmtIp, vlanGateway, rss, food, weather, ... }:
      let
        withSharedVhost = vhost: {
          forceSSL = true;
          quic = true;
          sslCertificate    = "/run/cert/internal.veetik.com/fullchain.pem";
          sslCertificateKey = "/run/cert/internal.veetik.com/key.pem";
        } // vhost;

        # Pin service ids: tmpfs root regenerates the uid/gid-map each build, so
        # auto-allocated ids drift when the user set changes and orphan persistent
        # /dev/vda data. uid=gid. Do NOT add upstream-pinned services (paperless=315,
        # syncthing=237, postgres=71) — they'd conflict. Changing an id means chown-ing
        # the on-disk data to match.
        serviceIds = {
          radicale = 700;
          food     = 701;
          weather  = 702;
          syncer   = 703;
        };
      in {
        users.users  = lib.mapAttrs (_: id: { uid = id; }) serviceIds;
        users.groups = lib.mapAttrs (_: id: { gid = id; }) serviceIds;

        imports = [
          ../_common.nix
          ../../../modules/nixos/dns-records.nix
          ../../../modules/nixos/homelab-volumes.nix
          ../../../modules/nixos/homelab-nginx-metrics.nix
          ../../../modules/nixos/backedup-pg.nix
          rss.nixosModules.default
          food.nixosModules.default
          weather.nixosModules.default
          ./lldap.nix
          ./authelia.nix
          ./radicale.nix
          ./rss.nix
          ./food.nix
          ./weather.nix
          ./shared-folder.nix
          ./paperless.nix
        ];

        _module.args = {
          inherit withSharedVhost;
        };

        microvm.mem = lib.mkForce 3072;

        networking.hostName = "internal";

        networking.hosts."127.0.0.1" = [ "sso.internal.veetik.com" ];

        microvm.interfaces = [{
          type = "tap";
          id = "vm-internal";
          mac = "02:00:00:40:00:01";
        }];

        homelab.volumeSize = 8192;

        systemd.network.enable = true;
        systemd.network.networks."10-eth" = {
          matchConfig.Type = "ether";
          address = [ "${guestIps.internal}/24" ];
          routes = [{ Gateway = vlanGateway; }];
          networkConfig.DHCP = "no";
        };

        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 80 443 ];
        };

        homelab.backups = {
          repositoryFile = "/run/secrets/restic-internal-repo";
          passwordFile   = "/run/secrets/restic-internal-encryption-pass";
        };

        services.backedupPg = {
          postgresPackage = pkgs.postgresql_18;
          repositoryFile = "/run/secrets/restic-internal-repo";
          passwordFile   = "/run/secrets/restic-internal-encryption-pass";
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
