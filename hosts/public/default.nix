{ config, adminKeys, inventory, pkgs, ... }:

let
  host = inventory.hosts.public;
  network = inventory.networks.${host.network};
  kubeNetwork = inventory.networks.kube;
  kubeInterface = "vlan${toString kubeNetwork.vlan}";
  backup = inventory.hosts.backup;
  ports = config.homelab.ports;
in {
  imports = [
    ../../modules/profiles/base.nix
    ../../modules/profiles/server.nix
    ../../modules/features/disk-health.nix
    ../../modules/features/port-registry.nix
    ../../modules/services/postgresql.nix
    ../../modules/services/k3s-server.nix
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
    netdevs."20-kube" = {
      netdevConfig = {
        Kind = "vlan";
        Name = kubeInterface;
      };
      vlanConfig.Id = kubeNetwork.vlan;
    };
    networks = {
      "10-dmz" = {
        matchConfig.Name = "en*";
        linkConfig.RequiredForOnline = "routable";
        address = [ "${host.ipv4}/29" ];
        vlan = [ kubeInterface ];
        routes = [{
          Gateway = network.router4;
          PreferredSource = host.ipv4;
        }];
        networkConfig = {
          DHCP = "no";
          DNS = [ network.router4 ];
        };
      };
      "20-kube" = {
        matchConfig.Name = kubeInterface;
        address = [ "${host.kubeIpv4}/24" ];
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
      };
    };
  };

  networking.firewall.extraCommands = ''
    iptables -w -A nixos-fw -s ${inventory.networks.trusted.cidr4} -p tcp --dport ${toString ports.keycloakAdminHttps} -j nixos-fw-accept
    iptables -w -A nixos-fw -s ${inventory.networks.wireguard.cidr4} -p tcp --dport ${toString ports.keycloakAdminHttps} -j nixos-fw-accept
  '';

  services = {
    k3s = {
      clusterInit = true;
      nodeName = "control1";
    };
    openiscsi = {
      enable = true;
      name = "iqn.2026-09.com.veetik:control1";
    };
    openssh.listenAddresses = [{ addr = host.ipv4; port = ports.ssh; }];
    prometheus.exporters = {
      postgres.port = ports.postgresqlExporter;
      smartctl.port = ports.smartctlExporter;
    };
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /lib 0755 root root -"
    "L /lib/modules - - - - /run/current-system/kernel-modules/lib/modules"
    "d /var/lib/iscsi 0755 root root -"
  ];

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
