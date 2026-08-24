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
    config = { config, pkgs, lib, keys, guestIps, publicGateways, ... }:
    let
      # https://www.cloudflare.com/ips/
      cloudflareCidrs = [
        "173.245.48.0/20"
        "103.21.244.0/22"
        "103.22.200.0/22"
        "103.31.4.0/22"
        "141.101.64.0/18"
        "108.162.192.0/18"
        "190.93.240.0/20"
        "188.114.96.0/20"
        "197.234.240.0/22"
        "198.41.128.0/17"
        "162.158.0.0/15"
        "104.16.0.0/13"
        "104.24.0.0/14"
        "172.64.0.0/13"
        "131.0.72.0/22"
        "2400:cb00::/32"
        "2606:4700::/32"
        "2803:f800::/32"
        "2405:b500::/32"
        "2405:8100::/32"
        "2a06:98c0::/29"
        "2c0f:f248::/32"
      ];

      proxyHeaders = ''
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $hostname;
      '';
    in {
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
        commonHttpConfig = ''
          # Trust CF-Connecting-IP only when the peer is a Cloudflare edge.
          ${lib.concatMapStringsSep "\n" (cidr: "set_real_ip_from ${cidr};") cloudflareCidrs}
          real_ip_header CF-Connecting-IP;
          real_ip_recursive on;
        '';

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
          extraConfig = proxyHeaders;
          # Keycloak's admin API and console must never pass through the public proxy.
          locations."= /admin".extraConfig = "return 404;";
          locations."^~ /admin/".extraConfig = "return 404;";
          locations."= /realms/main" = {
            proxyPass = "http://${guestIps.auth}:8080";
            recommendedProxySettings = false;
          };
          locations."^~ /realms/main/" = {
            proxyPass = "http://${guestIps.auth}:8080";
            recommendedProxySettings = false;
          };
          locations."= /realms/master" = {
            proxyPass = "http://${guestIps.auth}:8080";
            recommendedProxySettings = false;
            extraConfig = ''
              allow 192.168.10.0/24;
              allow 10.255.255.0/24;
              deny all;
            '';
          };
          locations."^~ /realms/master/" = {
            proxyPass = "http://${guestIps.auth}:8080";
            recommendedProxySettings = false;
            extraConfig = ''
              allow 192.168.10.0/24;
              allow 10.255.255.0/24;
              deny all;
            '';
          };
          locations."^~ /resources/" = {
            proxyPass = "http://${guestIps.auth}:8080";
            recommendedProxySettings = false;
          };
          locations."/".extraConfig = "return 404;";
        };

        virtualHosts."tasks-api.veetik.com" = {
          useACMEHost = "veetik.com";
          forceSSL = true;
          quic = true;
          extraConfig = proxyHeaders;
          locations."/" = {
            proxyPass = "http://${guestIps.tasks}:8000";
            recommendedProxySettings = false;
          };
        };

        virtualHosts."bm_back.veetik.com" = {
          useACMEHost = "veetik.com";
          forceSSL = true;
          quic = true;
          extraConfig = proxyHeaders;
          locations."/" = {
            proxyPass = "http://${guestIps.bm}:8000";
            recommendedProxySettings = false;
          };
        };
      };
    };
    };
  };
}
