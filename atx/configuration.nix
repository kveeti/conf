{ config, pkgs, lib, keys, microvm, pkgs-unstable, rss, food, weather, mac, nixvim, ... }:

let
  inventory = import ../router/inventory.nix;
  hosts = inventory.hosts;
  hostMgmtIp = hosts.atx.ipv4;
  guestIps = {
    nginx-public  = hosts.nginxPublic.ipv4;
    tasks         = hosts.tasks.ipv4;
    bm            = hosts.bm.ipv4;
    modi          = hosts.modi.ipv4;
    internal      = hosts.atxInternal.ipv4;
    printer       = hosts.printer.ipv4;
    media         = hosts.media.ipv4;
    homeassistant = hosts.homeAssistant.ipv4;
    dev           = hosts.dev.ipv4;
  };
  vlanGateway = inventory.networks.servers.router4;
  publicGateways = {
    nginx-public = inventory.networks.publicNginx.router4;
    tasks = inventory.networks.publicTasks.router4;
    bm = inventory.networks.publicBm.router4;
    modi = inventory.networks.publicModi.router4;
  };
  backupHostIp = hosts.backup.ipv4;
in
{
  imports = [
    microvm.nixosModules.host
    ../modules/nixos/dns-records.nix
    ../modules/nixos/homelab-microvm.nix
    ../modules/nixos/homelab-metrics.nix
    ../modules/nixos/homelab-logs.nix
    ./storage/media.nix
    ./guests/public/nginx-public.nix
    ./guests/public/tasks.nix
    ./guests/public/bm.nix
    ./guests/public/modi.nix
    ./guests/internal
    ./guests/media.nix
    ./guests/homeassistant.nix
    ./guests/printer.nix
    ./guests/dev
  ];

  homelab.dns.defaultTargetHost = "atxInternal";

  # MicroVMs share this package set, so unfree policy belongs on the host.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

  services.prometheus.exporters.smartctl = {
    enable = true;
    listenAddress = "127.0.0.1";
  };

  networking.hosts.${backupHostIp} = [ "backup.internal.veetik.com" ];

  homelab.metrics = {
    enable = true;
    remoteWriteUrl = "https://backup.internal.veetik.com:8428/api/v1/write";
    basicAuthUsername = "telemetry";
    basicAuthPasswordFile = config.age.secrets.telemetry-pass.path;
    nodeExporter.enabledCollectors = [ "systemd" "zfs" ];
    scrapeConfigs = [{
      job_name = "smartctl";
      static_configs = [{ targets = [ "127.0.0.1:9633" ]; }];
    }];
  };
  homelab.logs = {
    enable = true;
    url = "https://backup.internal.veetik.com:9428";
    basicAuthUsername = "telemetry";
    basicAuthPasswordFile = config.age.secrets.telemetry-pass.path;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  networking.hostId = "7161ba6b";

  # initrd needs DHCP on the untagged VLAN 40 for the SSH LUKS unlock to work
  boot.kernelParams = [
    "ip=dhcp"
    "intel_iommu=on"
    "iommu=pt"
    #"vfio-pci.ids=8086:4680"
  ];
  # usblp blacklisted so the host doesn't claim the USB printer out from under qemu (printer guest)
  boot.blacklistedKernelModules = [
    #"i915"
    "usblp"
  ];
  boot.initrd = {
    availableKernelModules = [ "igc" ];
    # load vfio in initrd so it claims the iGPU before i915
    kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = 2222;
        authorizedKeys = keys.admins;
        hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
        shell = "/bin/cryptsetup-askpass";
      };
    };
  };

  networking.hostName = "atx";
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "fi";

  # Lockout warning: eth0 enslaves into br-vlan40 — verify VLAN-40 reachability before configuring guests
  networking.useDHCP = false;
  networking.useNetworkd = true;
  systemd.network = {
    enable = true;

    netdevs = {
      "10-br-vlan40".netdevConfig  = { Name = "br-vlan40";  Kind = "bridge"; };
      "10-br-vlan70".netdevConfig  = { Name = "br-vlan70";  Kind = "bridge"; };
      "10-br-vlan71".netdevConfig  = { Name = "br-vlan71";  Kind = "bridge"; };
      "10-br-vlan72".netdevConfig  = { Name = "br-vlan72";  Kind = "bridge"; };
      "10-br-vlan73".netdevConfig  = { Name = "br-vlan73";  Kind = "bridge"; };
      "10-br-vlan20".netdevConfig  = { Name = "br-vlan20";  Kind = "bridge"; };
      "10-br-vlan111".netdevConfig = { Name = "br-vlan111"; Kind = "bridge"; };
      "10-br-vlan999".netdevConfig = { Name = "br-vlan999"; Kind = "bridge"; };

      "20-vlan70" = {
        netdevConfig = { Name = "vlan70"; Kind = "vlan"; };
        vlanConfig.Id = 70;
      };
      "20-vlan71" = {
        netdevConfig = { Name = "vlan71"; Kind = "vlan"; };
        vlanConfig.Id = 71;
      };
      "20-vlan72" = {
        netdevConfig = { Name = "vlan72"; Kind = "vlan"; };
        vlanConfig.Id = 72;
      };
      "20-vlan73" = {
        netdevConfig = { Name = "vlan73"; Kind = "vlan"; };
        vlanConfig.Id = 73;
      };
      "20-vlan20" = {
        netdevConfig = { Name = "vlan20"; Kind = "vlan"; };
        vlanConfig.Id = 20;
      };
      "20-vlan111" = {
        netdevConfig = { Name = "vlan111"; Kind = "vlan"; };
        vlanConfig.Id = 111;
      };
      "20-vlan999" = {
        netdevConfig = { Name = "vlan999"; Kind = "vlan"; };
        vlanConfig.Id = 999;
      };
    };

    networks = {
      "30-trunk" = {
        matchConfig.Name = "enxc87f5465d1b8";
        networkConfig = {
          Bridge = "br-vlan40";
          VLAN = [ "vlan70" "vlan71" "vlan72" "vlan73" "vlan20" "vlan111" "vlan999" ];
        };
      };

      "40-vlan70".matchConfig.Name = "vlan70";
      "40-vlan70".networkConfig.Bridge = "br-vlan70";
      "40-vlan71".matchConfig.Name = "vlan71";
      "40-vlan71".networkConfig.Bridge = "br-vlan71";
      "40-vlan72".matchConfig.Name = "vlan72";
      "40-vlan72".networkConfig.Bridge = "br-vlan72";
      "40-vlan73".matchConfig.Name = "vlan73";
      "40-vlan73".networkConfig.Bridge = "br-vlan73";

      "40-vlan20".matchConfig.Name  = "vlan20";
      "40-vlan20".networkConfig.Bridge  = "br-vlan20";

      "40-vlan111".matchConfig.Name = "vlan111";
      "40-vlan111".networkConfig.Bridge = "br-vlan111";

      "40-vlan999".matchConfig.Name  = "vlan999";
      "40-vlan999".networkConfig.Bridge  = "br-vlan999";

      "50-br-vlan40" = {
        matchConfig.Name = "br-vlan40";
        address = [ "${hostMgmtIp}/24" ];
        routes = [{ Gateway = vlanGateway; }];
        networkConfig.DHCP = "no";
      };

      "50-br-vlan70" = {
        matchConfig.Name = "br-vlan70";
        networkConfig = { LinkLocalAddressing = "no"; DHCP = "no"; };
      };
      "50-br-vlan71" = {
        matchConfig.Name = "br-vlan71";
        networkConfig = { LinkLocalAddressing = "no"; DHCP = "no"; };
      };
      "50-br-vlan72" = {
        matchConfig.Name = "br-vlan72";
        networkConfig = { LinkLocalAddressing = "no"; DHCP = "no"; };
      };
      "50-br-vlan73" = {
        matchConfig.Name = "br-vlan73";
        networkConfig = { LinkLocalAddressing = "no"; DHCP = "no"; };
      };
      "50-br-vlan20" = {
        matchConfig.Name = "br-vlan20";
        networkConfig = { LinkLocalAddressing = "no"; DHCP = "no"; };
      };
      "50-br-vlan111" = {
        matchConfig.Name = "br-vlan111";
        networkConfig = { LinkLocalAddressing = "no"; DHCP = "no"; };
      };
      "50-br-vlan999" = {
        matchConfig.Name = "br-vlan999";
        networkConfig = { LinkLocalAddressing = "no"; DHCP = "no"; };
      };

      "60-vm-nginx-public" = {
        matchConfig.Name = "vm-nginx-public";
        networkConfig.Bridge = "br-vlan70";
      };
      "60-vm-tasks" = {
        matchConfig.Name = "vm-tasks";
        networkConfig.Bridge = "br-vlan71";
      };
      "60-vm-bm" = {
        matchConfig.Name = "vm-bm";
        networkConfig.Bridge = "br-vlan72";
      };
      "60-vm-modi" = {
        matchConfig.Name = "vm-modi";
        networkConfig.Bridge = "br-vlan73";
      };
      "60-vm-internal" = {
        matchConfig.Name = "vm-internal";
        networkConfig.Bridge = "br-vlan40";
      };
      "60-vm-printer" = {
        matchConfig.Name = "vm-printer";
        networkConfig.Bridge = "br-vlan40";
      };
      "60-vm-media" = {
        matchConfig.Name = "vm-media";
        networkConfig.Bridge = "br-vlan111";
      };
      "60-vm-ha" = {
        matchConfig.Name = "vm-ha";
        networkConfig.Bridge = "br-vlan20";
      };
      "60-vm-dev" = {
        matchConfig.Name = "vm-dev";
        networkConfig.Bridge = "br-vlan999";
      };
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 0;
    "net.ipv4.conf.all.forwarding" = 0;
    "net.ipv6.conf.all.forwarding" = 0;
  };

  users.users = {
    root = {
      openssh.authorizedKeys.keys = keys.admins;
      hashedPasswordFile = config.age.secrets.password.path;
    };
    veeti = {
      useDefaultShell = true;
      createHome = true;
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = keys.admins;
      hashedPasswordFile = config.age.secrets.password.path;
    };
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      ChallengeResponseAuthentication = false;
      X11Forwarding = false;
    };
    hostKeys = [{ type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }];
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  environment.systemPackages = with pkgs; [ vim git btop tmux ];

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "security@veetik.com";
      server = "https://acme-v02.api.letsencrypt.org/directory";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1";
      environmentFile = config.age.secrets.cloudflare-env-file.path;
      group = "cert-readers";
    };
    certs."internal.veetik.com" = {
      domain = "internal.veetik.com";
      extraDomainNames = [ "*.internal.veetik.com" ];
    };
    certs."dev-internal.veetik.com" = {
      domain = "dev-internal.veetik.com";
      extraDomainNames = [ "*.dev-internal.veetik.com" ];
    };
  };
  # hand the HP LaserJet USB node to group kvm so the microvm qemu user can claim it (printer guest)
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="03f0", ATTR{idProduct}=="0272", GROUP="kvm"
  '';

  # gid must match across host + cert-consuming guests for virtiofs group access
  users.groups.cert-readers.gid = 6500;

  systemd.tmpfiles.rules = [
    "d /var/lib/microvms 0755 root root -"
  ];

  _module.args = {
    inherit keys guestIps hostMgmtIp publicGateways vlanGateway pkgs-unstable rss food weather mac nixvim;
  };

  system.stateVersion = "25.11";
}
