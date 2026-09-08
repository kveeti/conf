{ config, adminKeys, inventory, ... }:

let
  ports = config.homelab.ports;
in {
  imports = [
    ../../modules/profiles/base.nix
    ../../modules/profiles/server.nix
    ../../modules/features/disk-health.nix
    ../../modules/features/port-registry.nix
    ../../modules/services/microvms.nix
    ../../modules/telemetry/logs.nix
    ../../modules/telemetry/metrics.nix
    ./certificates.nix
    ./disk.nix
    ./hardware.nix
    ./internal.nix
    ./media-certificate.nix
    ./media/default.nix
    ./minecraft/default.nix
    ./network.nix
    ./storage.nix
  ];

  age.secrets = {
    password = {};
    telemetry-pass = {};
  };

  homelab.admin = {
    authorizedKeys = adminKeys;
    passwordFile = config.age.secrets.password.path;
  };

  boot = {
    supportedFilesystems = [ "zfs" ];
    zfs.forceImportRoot = false;
    kernelParams = [
      "ip=dhcp"
      "intel_iommu=on"
      "iommu=pt"
    ];
    blacklistedKernelModules = [ "usblp" ];

    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd = {
      availableKernelModules = [ "igc" ];
      kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
      systemd.users.root.shell = "/usr/bin/systemd-tty-ask-password-agent";
      network = {
        enable = true;
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
    hostId = "7161ba6b";
    useDHCP = false;
    useNetworkd = true;
    hosts.${inventory.hosts.backup.ipv4} = [ "backup.internal.veetik.com" ];
    firewall.allowedTCPPorts = [ ports.ssh ];
  };

  services = {
    openssh.ports = [ ports.ssh ];
    prometheus.exporters.smartctl.port = ports.smartctlExporter;
  };

  homelab = {
    metrics = {
      enable = true;
      listenAddress = "127.0.0.1:${toString ports.vmagent}";
      nodeExporter = {
        port = ports.nodeExporter;
        collectors = [ "systemd" "zfs" ];
      };
      remoteWriteUrl = "https://backup.internal.veetik.com:${toString inventory.hosts.backup.ports.metricsIngress}/api/v1/write";
      username = "telemetry";
      passwordFile = config.age.secrets.telemetry-pass.path;
    };

    logs = {
      enable = true;
      url = "https://backup.internal.veetik.com:${toString inventory.hosts.backup.ports.logsIngress}";
      username = "telemetry";
      passwordFile = config.age.secrets.telemetry-pass.path;
    };
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="03f0", ATTR{idProduct}=="0272", GROUP="kvm"
  '';

  users.groups.cert-readers.gid = 6500;
  systemd.tmpfiles.rules = [ "d /var/lib/microvms 0755 root root -" ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 0;
    "net.ipv4.conf.all.forwarding" = 0;
    "net.ipv6.conf.all.forwarding" = 0;
  };

  system.stateVersion = "25.11";
}
