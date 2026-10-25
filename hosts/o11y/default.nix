{ config, adminKeys, inventory, pkgs, ... }:

let
  host = inventory.hosts.o11y;
  network = inventory.networks.${host.network};
  ports = config.homelab.ports;
in {
  imports = [
    ../../modules/profiles/base.nix
    ../../modules/profiles/server.nix
    ../../modules/features/disk-health.nix
    ../../modules/features/port-registry.nix
    ./disk.nix
    ./hardware.nix
    ./monitoring
    ./secure-boot.nix
  ];

  age.secrets = {
    password = {};
    cloudflare-env-file = {};
    telemetry-pass = {};
  };

  homelab.admin = {
    authorizedKeys = adminKeys;
    passwordFile = config.age.secrets.password.path;
  };

  boot = {
    supportedFilesystems = [ "zfs" ];
    zfs.forceImportRoot = false;
    kernelParams = [ "ip=dhcp" ];

    initrd = {
      availableKernelModules = [ "e1000e" ];
      systemd.users.root.shell = "/usr/bin/systemd-tty-ask-password-agent";
      network = {
        enable = true;
        flushBeforeStage2 = true;
        ssh = {
          enable = true;
          port = ports.initrdSsh;
          authorizedKeys = adminKeys;
          hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
        };
      };
    };
  };

  networking = {
    hostId = "6f1e923a";
    useDHCP = false;
    useNetworkd = true;
    nftables.enable = true;
    firewall.allowedTCPPorts = [ ports.ssh ];
  };

  systemd.network = {
    enable = true;
    networks = {
      "10-lan" = {
        matchConfig.Name = "en*";
        linkConfig.RequiredForOnline = "routable";
        address = [ "${host.ipv4}/24" ];
        routes = [{
          Gateway = network.router4;
          PreferredSource = host.ipv4;
        }];
        networkConfig = {
          DHCP = "no";
          DNS = [ network.router4 ];
        };
      };
    };
  };

  services = {
    openssh.listenAddresses = [{ addr = host.ipv4; port = ports.ssh; }];
    prometheus.exporters = {
      smartctl.port = ports.smartctlExporter;
    };
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };
  };

  systemd.services.sshd = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  homelab = {
    nginxMetrics = {
      statusPort = ports.nginxStatus;
      exporterPort = ports.nginxExporter;
    };

  };

  environment.systemPackages = [ pkgs.dnsutils ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system.stateVersion = "25.11";
}
