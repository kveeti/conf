{ config, lib, pkgs, inputs, keys, ... }:

{
  imports =
    [
      ./hardware-config.nix
      ./hardening.nix
      ./secureboot.nix
      # enable only after cryptenroll writes a TPM token — switches to systemd-initrd, breaking the SSH unlock below
#      ./tpm-luks.nix
      ./single-signon.nix
      ./helium.nix
      ./hyprland.nix
      ../../modules/telemetry/metrics.nix
      inputs.lanzaboote.nixosModules.lanzaboote
    ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "discord"
    "steam"
    "steam-unwrapped"
    "steam-run"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.supportedFilesystems = [ "btrfs" ];

  boot.initrd = {
    systemd.users.root.shell = "/usr/bin/systemd-tty-ask-password-agent";
    availableKernelModules = [ "r8169" ];
    network = {
      enable = true;
      flushBeforeStage2 = true;
      ssh = {
        enable = true;
        port = 2222;
        authorizedKeys = keys.admins;
        hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
      };
    };
  };

  boot.initrd.systemd.network.networks."10-ethernet" = {
    matchConfig.Name = "enp10s0";
    networkConfig.DHCP = "ipv4";
  };

  networking.hostName = "pc";
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  networking.networkmanager.enable = true;
  hardware.enableRedistributableFirmware = true;

  homelab.metrics = {
    enable = true;
    remoteWriteUrl = "https://metrics.internal.veetik.com/api/v1/write";
    username = "telemetry";
    passwordFile = config.age.secrets.telemetry-pass.path;
  };

  time.timeZone = "Europe/Helsinki";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
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

  services.xserver.enable = true;

  services.displayManager.sddm.enable = true;

  services.xserver.xkb = {
    layout = "fi";
    variant = "mac";
    options = "ctrl:nocaps";
  };

  services.libinput = {
    enable = true;
    mouse = {
      accelProfile = "flat";
      accelSpeed = "-0.3";
      naturalScrolling = true;
    };
  };

  console.keyMap = "fi";

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    #jack.enable = true;
    #media-session.enable = true;
  };

  # services.xserver.libinput.enable = true;

  users.users."veeti" = {
    isNormalUser = true;
    description = "veeti";
    extraGroups = [ "networkmanager" "wheel" "video" "render" "i2c" ];
    openssh.authorizedKeys.keys = keys.admins;
    hashedPasswordFile = config.age.secrets.password.path;
  };

  programs.firefox.enable = true;
  programs.steam.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    sbctl
    ghostty
    jellyfin-mpv-shim
    (mpv-unwrapped.override { waylandSupport = true; })
    bluetuith
    ddcutil
    btop
  ];

  services.colord.enable = true;
  programs.dconf.enable = true;

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      liberation_ttf
      jetbrains-mono
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
    ];
    fontconfig.defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" ];
      sansSerif = [ "Noto Sans" ];
      serif = [ "Noto Serif" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  boot.kernelParams = [
    "i915.enable_guc=3"
    "amdgpu.ppfeaturemask=0xfff7ffff"
  ];
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    intel-compute-runtime
    libvdpau-va-gl
    vpl-gpu-rt
  ];
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  # DDC/CI brightness control for the external monitor (ddcutil over i2c)
  hardware.i2c.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

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

  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # networking.firewall.enable = false;

  system.stateVersion = "26.05";

}
