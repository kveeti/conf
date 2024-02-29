{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  nixpkgs = {
    overlays = [
      outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
    };
  };

  # This will add each flake input as a registry
  # To make nix3 commands consistent with your flake
  nix.registry = (lib.mapAttrs (_: flake: {inherit flake;})) ((lib.filterAttrs (_: lib.isType "flake")) inputs);

  # This will additionally add your inputs to the system's legacy channels
  # Making legacy nix commands consistent as well, awesome!
  nix.nixPath = ["/etc/nix/path"];
  environment.etc =
    lib.mapAttrs'
    (name: value: {
      name = "nix/path/${name}";
      value.source = value.flake;
    })
    config.nix.registry;

  nix.settings = {
    experimental-features = "nix-command flakes";
    auto-optimise-store = true;
  };

  boot.initrd.luks.devices."luks-183c14a9-b3a9-4530-a74e-28f64cbf22c0".device = "/dev/disk/by-uuid/183c14a9-b3a9-4530-a74e-28f64cbf22c0";
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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
  console.keyMap = "fi";
  services.xserver = {
    layout = "fi";
    xkbVariant = "";
  };

  networking = {
    networkmanager.enable = true;
    hostName = "pc";
  };

  services.xserver = {
    enable = true;
    displayManager = {
      sddm.enable = true;
    };
    desktopManager = {
      plasma5.enable = true;
    };
  };

  sound.enable = true;
  hardware.pulseaudio.enable = false;
  programs.dconf.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    xclip
    git
  ];

  virtualisation.docker.enable = true;

  users = {
    users."kveeti" = {
      isNormalUser = true;
      extraGroups = ["networkmanager" "wheel" "docker"];
      packages = with pkgs; [
        htop
        firefox
        neovim
        discord
        easyeffects
        ripgrep
        gnupg
        tmux
        inputs.home-manager.packages.${pkgs.system}.default
      ];
    };
  };

  programs = {
    steam = {
      enable = true;
      #remotePlay.openFirewall = true;
      #dedicatedServer.openFirewall = true;
    };
    _1password.enable = true;
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = ["kveeti"];
    };
  };

  system.stateVersion = "23.11";
}
