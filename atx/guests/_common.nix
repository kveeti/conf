{ pkgs, keys, ... }@args:

let
  adminUsername = args.adminUsername or "veeti";
  backupIp = (import ../../router/inventory.nix).hosts.backup.ipv4;
in {
  imports = [
    ../../modules/nixos/homelab-metrics.nix
    ../../modules/nixos/homelab-logs.nix
  ];

  networking.hosts.${backupIp} = [ "backup.internal.veetik.com" ];

  homelab.metrics = {
    enable = true;
    remoteWriteUrl = "https://backup.internal.veetik.com:8428/api/v1/write";
  };
  homelab.logs = {
    enable = true;
    url = "https://backup.internal.veetik.com:9428";
  };

  microvm = {
    hypervisor = "cloud-hypervisor";
    mem = 1024;
    vcpu = 2;

    shares = [{
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag = "ro-store";
      proto = "virtiofs";
    }];
  };

  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users = {
    root.openssh.authorizedKeys.keys = keys.admins;
    ${adminUsername} = {
      useDefaultShell = true;
      createHome = true;
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = keys.admins;
    };
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    # host key on a virtiofs share so identity survives reboots; RequiresMountsFor (below) makes keygen wait or the key lands on the tmpfs underneath
    hostKeys = [{
      path = "/run/ssh-host/ssh_host_ed25519_key";
      type = "ed25519";
    }];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
  };
  systemd.services.sshd-keygen.unitConfig.RequiresMountsFor = "/run/ssh-host";

  environment.systemPackages = with pkgs; [ vim btop dnsutils ];

  system.stateVersion = "25.11";
}
