{ config, adminKeys, inventory, ... }:

let
  host = inventory.hosts.backup;
  network = inventory.networks.${host.network};
in {
  imports = [
    ../../modules/profiles/base.nix
    ../../modules/profiles/server.nix
    ./disk.nix
    ./hardware.nix
    ./restic.nix
  ];

  homelab.admin = {
    authorizedKeys = adminKeys;
    passwordFile = config.age.secrets.password.path;
  };

  boot = {
    supportedFilesystems = [ "zfs" ];
    zfs.forceImportRoot = false;
    kernelParams = [ "ip=dhcp" ];

    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd = {
      availableKernelModules = [ "igb" "ixgbe" "e1000e" ];
      systemd.users.root.shell = "/usr/bin/systemd-tty-ask-password-agent";
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222;
          authorizedKeys = adminKeys;
          hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
        };
      };
    };
  };

  networking = {
    hostId = "ba61c0d5";
    useDHCP = false;
    useNetworkd = true;
    firewall.allowedTCPPorts = [ 22 ];
  };

  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = "en*";
      address = [ "${host.ipv4}/24" ];
      routes = [{ Gateway = network.router4; }];
      networkConfig.DHCP = "no";
    };
  };

  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };

  system.stateVersion = "25.11";
}
