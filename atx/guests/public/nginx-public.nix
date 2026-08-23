{ config, ... }:

let
  vmName = "nginx-public";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;

    secrets = [
      { name = "cloudflare-env-file"; mode = "0400"; }
      { name = "telemetry-pass"; mode = "0400"; }
    ];

    shares = {
      ssh-host = {
        owner = "root"; group = "root"; mode = "0755";
        path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
      };
      media-cert = {
        create = false;
        readOnly = true;
        path = "/run/media-cert";
        hostPath = "/run/media-certificate-profile";
      };
    };

    vm = {
    specialArgs = { inherit (config._module.args) keys guestIps publicGateways; };
    config = { config, pkgs, lib, keys, guestIps, publicGateways, ... }: {
      imports = [
        ../_common.nix
        ../../../modules/nixos/homelab-nginx-metrics.nix
        ../../../modules/nixos/homelab-volumes.nix
      ];

      networking.hostName = "nginx-public";

      microvm.mem = lib.mkForce 512;

      homelab.nginxMetrics.enable = true;

      microvm.interfaces = [{
        type = "tap";
        id = "vm-nginx-public";
        mac = "02:00:00:66:00:01";
      }];

      # persist /var/lib/acme: tmpfs root would re-issue the LE cert every reboot and blow the weekly rate limit (Cloudflare 526)
      homelab.volumeSize = 256;
      homelab.volumes.acme = { owner = "acme"; mode = "0755"; };

      # mount before ACME writes, else state lands on the tmpfs underneath (like sshd-keygen in _common)
      systemd.services.acme-setup.unitConfig.RequiresMountsFor = "/var/lib/acme";

      systemd.network.enable = true;
      systemd.network.networks."10-eth" = {
        matchConfig.Type = "ether";
        address = [ "${guestIps.nginx-public}/30" ];
        routes = [{ Gateway = publicGateways.nginx-public; }];
        networkConfig.DHCP = "no";
      };

      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ 22 80 443 ];
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = "security@veetik.com";
        defaults.server = "https://acme-v02.api.letsencrypt.org/directory";
        certs."veetik.com" = {
          domain = "veetik.com";
          extraDomainNames = [ "*.veetik.com" ];
          dnsProvider = "cloudflare";
          dnsResolver = "1.1.1.1";
          environmentFile = "/run/secrets/cloudflare-env-file";
          group = config.services.nginx.group;
        };
      };

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;

        virtualHosts."media-cert.veetik.com" = {
          useACMEHost = "veetik.com";
          forceSSL = true;
          quic = true;
          locations."= /" = {
            root = "/run/media-cert";
            tryFiles = "/media.lan.mobileconfig =404";
            extraConfig = ''
              default_type application/x-apple-aspen-config;
              add_header Content-Disposition 'attachment; filename="media.lan.mobileconfig"' always;
            '';
          };
        };

        virtualHosts."auth.veetik.com" = {
          useACMEHost = "veetik.com";
          forceSSL = true;
          quic = true;
          # Keycloak's admin API and console must never pass through the public proxy.
          locations."= /admin".extraConfig = "return 404;";
          locations."^~ /admin/".extraConfig = "return 404;";
          locations."= /realms/main".proxyPass = "http://${guestIps.auth}:8080";
          locations."^~ /realms/main/".proxyPass = "http://${guestIps.auth}:8080";
          locations."= /realms/master" = {
            proxyPass = "http://${guestIps.auth}:8080";
            extraConfig = ''
              allow 192.168.10.0/24;
              allow 10.255.255.0/24;
              deny all;
            '';
          };
          locations."^~ /realms/master/" = {
            proxyPass = "http://${guestIps.auth}:8080";
            extraConfig = ''
              allow 192.168.10.0/24;
              allow 10.255.255.0/24;
              deny all;
            '';
          };
          locations."^~ /resources/".proxyPass = "http://${guestIps.auth}:8080";
          locations."/".extraConfig = "return 404;";
        };

        virtualHosts."tasks-api.veetik.com" = {
          useACMEHost = "veetik.com";
          forceSSL = true;
          quic = true;
          locations."/".proxyPass = "http://${guestIps.tasks}:8000";
        };

        virtualHosts."bm_back.veetik.com" = {
          useACMEHost = "veetik.com";
          forceSSL = true;
          quic = true;
          locations."/".proxyPass = "http://${guestIps.bm}:8000";
        };
      };
    };
    };
  };
}
