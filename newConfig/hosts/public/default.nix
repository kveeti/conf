{ config, adminKeys, inventory, pkgs, ... }:

let
  host = inventory.hosts.public;
  network = inventory.networks.${host.network};
  backup = inventory.hosts.backup;
in {
  imports = [
    ../../modules/profiles/base.nix
    ../../modules/profiles/server.nix
    ../../modules/features/disk-health.nix
    ../../modules/services/postgresql.nix
    ../../modules/telemetry/logs.nix
    ./bm.nix
    ./containers.nix
    ./disk.nix
    ./hardware.nix
    ./keycloak.nix
    ./modi.nix
    ./money.nix
    ./nginx.nix
    ./secure-boot.nix
    ./tasks.nix
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
          port = 2222;
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
    hosts.${backup.ipv4} = [ "backup.internal.veetik.com" ];
    firewall.allowedTCPPorts = [ 22 ];
  };

  systemd.network = {
    enable = true;
    networks."10-dmz" = {
      matchConfig.Name = "en*";
      linkConfig.RequiredForOnline = "routable";
      address = [ "${host.ipv4}/29" "${host.adminIpv4}/29" ];
      routes = [{
        Gateway = network.router4;
        PreferredSource = host.ipv4;
      }];
      networkConfig = {
        DHCP = "no";
        DNS = [ "1.1.1.1" "1.0.0.1" ];
      };
    };
  };

  services = {
    openssh.listenAddresses = [{ addr = host.adminIpv4; port = 22; }];
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
    metrics = {
      enable = true;
      remoteWriteUrl = "https://backup.internal.veetik.com:8428/api/v1/write";
      username = "telemetry";
      passwordFile = config.age.secrets.telemetry-pass.path;
    };

    logs = {
      enable = true;
      url = "https://backup.internal.veetik.com:9428";
      username = "telemetry";
      passwordFile = config.age.secrets.telemetry-pass.path;
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
