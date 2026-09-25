{ config, adminKeys, inventory, pkgs, ... }:

let
  host = inventory.hosts.public;
  network = inventory.networks.${host.network};
  backup = inventory.hosts.backup;
  ports = config.homelab.ports;
in {
  imports = [
    ../../modules/profiles/base.nix
    ../../modules/profiles/server.nix
    ../../modules/features/disk-health.nix
    ../../modules/features/port-registry.nix
    ../../modules/services/postgresql.nix
    ../../modules/telemetry/logs.nix
    ./authentik.nix
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
    firewall.allowedTCPPorts = [ ports.ssh ];
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
        DNS = [ network.router4 ];
      };
    };
  };

  services = {
    openssh.listenAddresses = [{ addr = host.adminIpv4; port = ports.ssh; }];
    prometheus.exporters = {
      postgres.port = ports.postgresqlExporter;
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
    backups.serverUrl = "https://backup.internal.veetik.com:8000";

    nginxMetrics = {
      statusPort = ports.nginxStatus;
      exporterPort = ports.nginxExporter;
    };

    metrics = {
      enable = true;
      listenAddress = "127.0.0.1:${toString ports.vmagent}";
      nodeExporter.port = ports.nodeExporter;
      remoteWriteUrl = "https://metrics.internal.veetik.com/api/v1/write";
      username = "telemetry";
      passwordFile = config.age.secrets.telemetry-pass.path;
    };

    logs = {
      enable = true;
      url = "https://logs.internal.veetik.com";
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
