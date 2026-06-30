{ config, secretPath, mediaUser, ... }:

let
  vmName = "media";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;

    secrets = [
      { name = "wg-conf"; value = secretPath config.age.secrets.media-wg-conf.path; mode = "0400"; }
    ];

    shares = {
      ssh-host = {
        owner = "root"; group = "root"; mode = "0755";
        path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
      };
      media = { create = false; path = "/mnt/storage"; hostPath = "/mnt/storage"; };
    };

    vm = {
      specialArgs = {
        inherit (config._module.args) keys guestIps pkgs-unstable;
        inherit mediaUser;
        adminUsername = mediaUser.user;
      };
      config = { config, pkgs, lib, keys, guestIps, adminUsername, mediaUser, ... }: {
        imports = [ ./_common.nix ./media-helpers.nix ../../modules/nixos/homelab-volumes.nix ];

        homelab.volumeSize = 614400; # MiB = 600 GiB
        homelab.volumes.jellyfin = {
          owner = "root"; mode = "0755";
          dirs = { config = {}; cache = {}; };
        };

        microvm.hypervisor = lib.mkForce "qemu";
        microvm.mem  = lib.mkForce 4096;
        microvm.vcpu = lib.mkForce 4;

        networking.hostName = "media";

        microvm.interfaces = [{
          type = "tap";
          id = "vm-media";
          mac = "02:00:00:6f:00:01";
        }];

        microvm.devices = [
          { bus = "pci"; path = "0000:00:02.0"; }
        ];

        # block volume for podman graphroot: overlay won't run on virtiofs, tmpfs root OOMs on pulls
        microvm.volumes = [{
          image = "${stateRoot}/podman.img";
          mountPoint = "/var/lib/containers";
          size = 30720;
        }];

        boot.kernelModules = [ "i915" ];
        hardware.graphics = {
          enable = true;
          extraPackages = with pkgs; [ intel-media-driver ];
        };

        # pin uid/gid to the host's media owner so virtiofs writes land stable on mergerfs
        users.groups.${mediaUser.group}.gid = mediaUser.gid;

        users.users.${mediaUser.user} = {
          uid = mediaUser.uid;
          group = mediaUser.group;
          extraGroups = [ "video" "render" ];
        };

        # /16 route pins LAN destinations to eth0 so off-subnet SSH/HTTP isn't swallowed by the wg tunnel
        systemd.network.enable = true;
        systemd.network.networks."10-eth" = {
          matchConfig.Type = "ether";
          address = [ "${guestIps.media}/24" ];
          routes = [
            { Gateway = "192.168.111.1"; }
            { Destination = "192.168.0.0/16"; Gateway = "192.168.111.1"; }
          ];
          networkConfig.DHCP = "no";
        };

        # wg endpoint must be an IP literal — no DNS pre-tunnel
        networking.wg-quick.interfaces.wg0.configFile = "/run/secrets/wg-conf";

        services.resolved.enable = false;
        services.unbound = {
          enable = true;
          checkconf = true;
          resolveLocalQueries = true;
          enableRootTrustAnchor = true;
          settings = {
            forward-zone = [{
              name = ".";
              forward-tls-upstream = "yes";
              forward-addr = [
                "1.1.1.1@853#cloudflare-dns.com"
                "1.0.0.1@853#cloudflare-dns.com"
                "9.9.9.9@853#dns.quad9.net"
                "149.112.112.112@853#dns.quad9.net"
              ];
            }];
            server = {
              verbosity = "0";
              log-queries = "no";
              log-replies = "no";
              log-servfail = "no";
              log-local-actions = "no";

              module-config = ''"respip validator iterator"'';
              interface = [ "127.0.0.1" ];
              access-control = [
                "127.0.0.0/8 allow"
                "192.168.111.0/24 allow"
              ];
              port = "53";
              do-ip4 = "yes";
              do-ip6 = "no";
              do-udp = "yes";
              do-tcp = "yes";

              tls-cert-bundle = "/etc/ssl/certs/ca-certificates.crt";

              hide-identity = "yes";
              hide-version = "yes";
              harden-glue = "yes";
              harden-dnssec-stripped = "yes";
              use-caps-for-id = "yes";
              harden-below-nxdomain = "yes";
              harden-referral-path = "yes";
              qname-minimisation = "yes";
              num-threads = "1";

              prefetch = "yes";
              prefetch-key = "yes";
              neg-cache-size = "1m";
              cache-max-negative-ttl = "300";
              msg-cache-size = "8m";
              rrset-cache-size = "16m";
              key-cache-size = "1m";
              cache-min-ttl = 300;
              cache-max-ttl = 86400;
              aggressive-nsec = "yes";

              serve-expired = "yes";
              serve-expired-ttl = "120";
              serve-expired-client-timeout = "1800";
              serve-expired-reply-ttl = "30";

              so-reuseport = "yes";
              minimal-responses = "yes";
              rrset-roundrobin = "yes";
            };
          };
        };
        systemd.services.unbound.after = [ "wg-quick-wg0.service" ];

        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 80 443 8096 ];
        };

        services.mediaHelpers.enable = true;

        networking.nftables.enable = true;
        networking.nftables.tables.dns-leak-block = {
          family = "inet";
          content = ''
            chain output {
              type filter hook output priority 0; policy accept;
              ip daddr 127.0.0.0/8 return
              ip6 daddr ::1 return
              udp dport 53 drop
              tcp dport 53 drop
            }
          '';
        };

        virtualisation = {
          containers.enable = true;
          oci-containers.backend = "podman";
          podman.enable = true;
        };

        virtualisation.oci-containers.containers.jellyfin = {
          image = "docker.io/jellyfin/jellyfin@sha256:0b901391a662862eddb5dc55d244d7883cbb6236ef5b9a6ea82abc78a89819f0";
          extraOptions = [
            "--hostuser=${mediaUser.user}"
            "--network=host"
            "--device=/dev/dri/renderD128"
            "--device=/dev/dri/card0"
            # Numeric gids (video=26, render=303): names don't resolve in the image.
            "--group-add=26"
            "--group-add=303"
          ];
          volumes = [
            "/var/lib/jellyfin/config:/config"
            "/var/lib/jellyfin/cache:/cache"
            "/mnt/storage/media:/data/media"
          ];
        };
        systemd.services.podman-jellyfin = {
          after    = [ "wg-quick-wg0.service" ];
          requires = [ "wg-quick-wg0.service" ];
        };
        services.nginx.virtualHosts."jellyfin.media.lan".locations."/" = {
          proxyPass = "http://127.0.0.1:8096";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
          '';
        };
      };
    };
  };
}
