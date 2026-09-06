{ inventory, lib, pkgs, ... }:

let
  network = inventory.networks.unifi;
  stateRoot = "/var/lib/microvms/unifi";
  mongodb = pkgs.mongodb-ce.overrideAttrs (old: {
    version = "7.0.30";
    src = pkgs.fetchurl {
      url = "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-7.0.30.tgz";
      hash = "sha256-Km64VqSBqLykdgGhrWLSalit8ZmfGgI1ld5C+U+QDSo=";
    };
    meta = old.meta // {
      changelog = "https://www.mongodb.com/docs/manual/release-notes/7.0/";
    };
  });
in {
  nixpkgs.config.allowUnfreePredicate = package:
    builtins.elem (lib.getName package) [ "mongodb-ce" "unifi-controller" ];

  systemd.network.networks."50-unifi" = {
    matchConfig.Name = network.interface;
    address = [ "${network.router4}/24" ];
    networkConfig = {
      DHCP = "no";
      IPv4Forwarding = true;
      LinkLocalAddressing = false;
    };
  };

  microvm.vms.unifi = {
    specialArgs = {
      inherit inventory;
      hostPkgs = pkgs;
      mongodbPackage = mongodb;
    };

    config = { config, hostPkgs, inventory, mongodbPackage, ... }:
      let
        guest = inventory.hosts.unifi;
        guestNetwork = inventory.networks.${guest.network};
        ports = config.homelab.ports;
      in {
        imports = [ ../../modules/features/port-registry.nix ];

        microvm = {
          hypervisor = "cloud-hypervisor";
          mem = 4096;
          vcpu = 2;
          vsock.cid = 100;

          interfaces = [{
            type = "tap";
            id = guestNetwork.interface;
            mac = "02:00:00:64:00:02";
          }];

          shares = [{
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag = "ro-store";
            proto = "virtiofs";
          }];

          volumes = [{
            image = "${stateRoot}/state.img";
            mountPoint = "/var/lib/unifi";
            size = 16384;
          }];
        };

        boot.loader = {
          grub.enable = false;
          systemd-boot.enable = false;
        };

        networking = {
          hostName = guest.hostname;
          useDHCP = false;
          useNetworkd = true;
          firewall = {
            enable = true;
            allowedTCPPorts = [ ports.inform ports.web ];
            allowedUDPPorts = [ ports.ssdp ports.stun ports.discovery ];
          };
        };

        systemd.network = {
          enable = true;
          networks."10-ethernet" = {
            matchConfig.Type = "ether";
            address = [ "${guest.ipv4}/24" ];
            routes = [{ Gateway = guestNetwork.router4; }];
            networkConfig = {
              DHCP = "no";
              DNS = [ guestNetwork.router4 ];
            };
          };
        };

        users.users.unifi.uid = 997;
        users.groups.unifi.gid = 996;

        services.unifi = {
          enable = true;
          openFirewall = false;
          unifiPackage = hostPkgs.unifi;
          inherit mongodbPackage;
          initialJavaHeapSize = 512;
          maximumJavaHeapSize = 1024;
        };

        system.stateVersion = "25.11";
      };
  };
}
