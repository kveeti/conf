{ lib, pkgs, ... }:

let
  inventory = import ./inventory.nix;
  unifiIp = inventory.hosts.unifiController.ipv4;
  gateway = inventory.networks.unifiNetwork.router4;
  stateRoot = "/var/lib/microvms/unifi";
in {
  microvm.vms.unifi = {
    specialArgs = { hostPkgs = pkgs; };

    config = { config, lib, pkgs, hostPkgs, ... }: {
      microvm = {
        hypervisor = "cloud-hypervisor";
        mem = 4096;
        vcpu = 2;
        vsock.cid = 100;

        interfaces = [{
          type = "tap";
          id = "vm-unifi";
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

      boot.loader.grub.enable = false;
      boot.loader.systemd-boot.enable = false;

      networking = {
        hostName = "unifi";
        useDHCP = false;
        useNetworkd = true;
        firewall = {
          enable = true;
          allowedTCPPorts = [ 8080 8443 ];
          allowedUDPPorts = [ 3478 10001 ];
        };
      };

      systemd.network = {
        enable = true;
        networks."10-eth" = {
          matchConfig.Type = "ether";
          address = [ "${unifiIp}/24" ];
          routes = [{ Gateway = gateway; }];
          networkConfig.DHCP = "no";
        };
      };

      users.users.unifi.uid = 997;
      users.groups.unifi.gid = 996;

      services.unifi = {
        enable = true;
        openFirewall = false;
        unifiPackage = hostPkgs.unifi-bleeding-edge;
        mongodbPackage = hostPkgs.mongodb-ce-7_0;
        initialJavaHeapSize = 512;
        maximumJavaHeapSize = 1024;
      };

      system.stateVersion = "25.11";
    };
  };
}
