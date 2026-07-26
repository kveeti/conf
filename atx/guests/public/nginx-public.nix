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
      jellyfin-cert = {
        create = false;
        readOnly = true;
        path = "/run/jellyfin-cert";
        hostPath = "/var/lib/jellyfin-certificate/public";
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

        virtualHosts."jellyfin-cert.veetik.com" = {
          useACMEHost = "veetik.com";
          forceSSL = true;
          quic = true;
          locations."= /" = {
            root = "/run/jellyfin-cert";
            tryFiles = "/jellyfin.media.lan.mobileconfig =404";
            extraConfig = ''
              default_type application/x-apple-aspen-config;
              add_header Content-Disposition 'attachment; filename="jellyfin.media.lan.mobileconfig"' always;
            '';
          };
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
