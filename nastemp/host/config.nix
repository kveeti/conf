{ config, pkgs, lib, keys, ... }:

{
  config.boot.loader.systemd-boot.enable = true;
  config.boot.loader.efi.canTouchEfiVariables = true;

  config.boot.kernelParams = [ "ip=dhcp" ];
  config.boot.initrd = {
    availableKernelModules = [ "igc" ];
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

  config.networking.hostName = "nastemp";
  config.time.timeZone = "UTC";
  config.i18n.defaultLocale = "en_US.UTF-8";
  config.i18n.extraLocaleSettings = {
    LC_ADDRESS = "fi_FI.UTF-8";
    LC_IDENTIFICATION = "fi_FI.UTF-8";
    LC_MEASUREMENT = "fi_FI.UTF-8";
    LC_MONETARY = "fi_FI.UTF-8";
    LC_NAME = "fi_FI.UTF-8";
    LC_NUMERIC = "fi_FI.UTF-8";
    LC_PAPER = "fi_FI.UTF-8";
    LC_TELEPHONE = "fi_FI.UTF-8";
    LC_TIME = "fi_FI.UTF-8";
  };
  config.console.keyMap = "fi";
  config.services.xserver.xkb = {
    layout = "fi";
    variant = "";
  };

  config.users.users = {
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

  config.security.sudo.wheelNeedsPassword = false;

  config.services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      ChallengeResponseAuthentication = false;
      X11Forwarding = false;
    };
    hostKeys = [{
      type = "ed25519";
      path = "/etc/ssh/ssh_host_ed25519_key";
    }];
  };

  config.networking.firewall.enable = true;
  config.networking.firewall.allowedTCPPorts = [22 80 443 8080 8443];
  config.environment.systemPackages = with pkgs; [
    vim
    git
    btop
    tmux
    smartmontools
  ];

  config.system.stateVersion = "25.11";
}

