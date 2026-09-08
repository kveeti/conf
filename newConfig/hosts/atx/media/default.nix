{ config, adminKeys, inventory, lib, pkgs-unstable, ... }:

let
  name = "media";
  stateRoot = "/var/lib/microvms/${name}";
  secretDir = "${stateRoot}/secrets";
  media = inventory.hosts.media;
  jellyfin = inventory.hosts.jellyfin;
  network = inventory.networks.${media.network};
  bridge = "br-${network.interface}";
  mediaCertificateDirectory = "/run/media-certificate";
  privateModules = config.homelab.microvms.${name}.guestModules or [];
  mediaUser = {
    user = "media";
    uid = 1500;
    group = "media";
    gid = 7000;
  };
in {
  age.secrets.media-wg-conf = {};

  system.activationScripts.media-files = {
    deps = [ "agenix" ];
    text = ''
      install -d -m 0755 ${stateRoot}/ssh
      install -d -m 0711 ${secretDir}
      install -m 0400 ${config.age.secrets.media-wg-conf.path} ${secretDir}/wg-conf
    '';
  };

  systemd.network.networks."60-vm-media" = {
    matchConfig.Name = "vm-media";
    networkConfig.Bridge = bridge;
  };

  microvm.vms.media = {
    specialArgs = {
      inherit adminKeys inventory mediaUser pkgs-unstable;
      adminUsername = mediaUser.user;
      guestIps = {
        media = media.ipv4;
        jellyfin = jellyfin.ipv4;
      };
      mediaCertInVMDir = mediaCertificateDirectory;
    };

    config = { config, lib, pkgs, ... }: {
      imports = [
        ../../../modules/profiles/base.nix
        ../../../modules/profiles/server.nix
        ../../../modules/features/port-registry.nix
        ../../../modules/services/microvm-volumes.nix
        ./nginx.nix
      ] ++ privateModules;

      homelab = {
        hostKey = name;
        admin = {
          username = mediaUser.user;
          authorizedKeys = adminKeys;
        };
        stateRoot = stateRoot;
        volumeSize = 614400;
        volumes.jellyfin = {
          owner = "root";
          mode = "0755";
          dirs = {
            config = {};
            cache = {};
          };
        };
      };

      networking = {
        hostName = media.hostname;
        useDHCP = false;
        useNetworkd = true;
        firewall.allowedTCPPorts = [
          config.homelab.ports.ssh
          config.homelab.ports.http
          config.homelab.ports.https
        ];
        wg-quick.interfaces.wg0.configFile = "/run/secrets/wg-conf";
      };

      services.openssh = {
        ports = [ config.homelab.ports.ssh ];
        hostKeys = lib.mkForce [{
          path = "/run/ssh-host/ssh_host_ed25519_key";
          type = "ed25519";
        }];
      };
      systemd.services.sshd-keygen.unitConfig.RequiresMountsFor = "/run/ssh-host";

      microvm = {
        hypervisor = lib.mkForce "qemu";
        mem = lib.mkForce 6144;
        vcpu = lib.mkForce 4;
        interfaces = [{
          type = "tap";
          id = "vm-media";
          mac = "02:00:00:6f:00:01";
        }];
        devices = [{
          bus = "pci";
          path = "0000:00:02.0";
        }];
        shares = [
          {
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag = "ro-store";
            proto = "virtiofs";
          }
          {
            source = "${stateRoot}/ssh";
            mountPoint = "/run/ssh-host";
            tag = "ssh-host";
            proto = "virtiofs";
          }
          {
            source = secretDir;
            mountPoint = "/run/secrets";
            tag = "secrets";
            proto = "virtiofs";
            readOnly = true;
          }
          {
            source = "/var/lib/media-certificate/media";
            mountPoint = mediaCertificateDirectory;
            tag = "media-certificate";
            proto = "virtiofs";
            readOnly = true;
          }
          {
            source = "/mnt/storage";
            mountPoint = "/mnt/storage";
            tag = "media";
            proto = "virtiofs";
          }
        ];
        volumes = [{
          image = "${stateRoot}/podman.img";
          mountPoint = "/var/lib/containers";
          size = 30720;
        }];
      };

      boot = {
        kernelModules = [ "i915" ];
        loader = {
          grub.enable = false;
          systemd-boot.enable = false;
        };
      };

      hardware.graphics = {
        enable = true;
        extraPackages = [ pkgs.intel-media-driver ];
      };

      users = {
        groups.${mediaUser.group}.gid = mediaUser.gid;
        users.${mediaUser.user} = {
          uid = mediaUser.uid;
          group = mediaUser.group;
          extraGroups = [ "video" "render" ];
        };
      };

      systemd.network = {
        enable = true;
        networks."10-ethernet" = {
          matchConfig.MACAddress = "02:00:00:6f:00:01";
          address = [
            "${media.ipv4}/${lib.last (lib.splitString "/" network.cidr4)}"
            "${jellyfin.ipv4}/32"
          ];
          routes = [
            { Gateway = network.router4; }
            {
              Destination = "192.168.0.0/16";
              Gateway = network.router4;
            }
          ];
          networkConfig.DHCP = "no";
        };
      };

      services = {
        resolved.enable = false;
        unbound = {
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
                "${network.cidr4} allow"
              ];
              port = toString config.homelab.ports.dns;
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
      };
      systemd.services.unbound.after = [ "wg-quick-wg0.service" ];

      networking.nftables = {
        enable = true;
        tables.dns-leak-block = {
          family = "inet";
          content = ''
            chain output {
              type filter hook output priority 0; policy accept;
              ip daddr 127.0.0.0/8 return
              ip6 daddr ::1 return
              udp dport ${toString config.homelab.ports.dns} drop
              tcp dport ${toString config.homelab.ports.dns} drop
            }
          '';
        };
      };

      virtualisation = {
        containers.enable = true;
        oci-containers.backend = "podman";
        podman.enable = true;
        oci-containers.containers.jellyfin = {
          image = "docker.io/jellyfin/jellyfin@sha256:0b901391a662862eddb5dc55d244d7883cbb6236ef5b9a6ea82abc78a89819f0";
          extraOptions = [
            "--hostuser=${mediaUser.user}"
            "--device=/dev/dri/renderD128"
            "--device=/dev/dri/card0"
            "--group-add=26"
            "--group-add=303"
          ];
          ports = [ "127.0.0.1:${toString config.homelab.ports.jellyfin}:8096" ];
          volumes = [
            "/var/lib/jellyfin/config:/config"
            "/var/lib/jellyfin/cache:/cache"
            "/mnt/storage/media:/data/media"
          ];
        };
      };

      systemd.services.podman-jellyfin = {
        after = [ "wg-quick-wg0.service" ];
        requires = [ "wg-quick-wg0.service" ];
      };

      services.nginx.virtualHosts."jellyfin.media.lan".locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.homelab.ports.jellyfin}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };

      system.stateVersion = "25.11";
    };
  };
}
