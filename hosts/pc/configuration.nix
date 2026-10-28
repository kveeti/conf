{ config, lib, pkgs, inputs, keys, ... }:

{
  imports =
    [
      ./hardware-config.nix
      ./hardening.nix
      ./secureboot.nix
      ./single-signon.nix
      ./agent-vm.nix
      ./helium.nix
      ../../modules/telemetry/metrics.nix
      inputs.lanzaboote.nixosModules.lanzaboote
    ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "discord"
    "steam"
    "steam-unwrapped"
    "steam-run"
    "spotify"
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
  hardware.amdgpu.overdrive.enable = true;

  systemd.services.amdgpu-tuning = {
    description = "Apply GPU power limit and undervolt";
    wantedBy = [ "multi-user.target" ];
    wants = [ "systemd-udev-settle.service" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      gpu=/sys/bus/pci/devices/0000:03:00.0
      if [[ $(< "$gpu/vendor") != 0x1002 ||
            $(< "$gpu/device") != 0x7550 ||
            $(< "$gpu/subsystem_vendor") != 0x1da2 ||
            $(< "$gpu/subsystem_device") != 0x3490 ]]; then
        printf 'GPU identity mismatch at %s; refusing to apply tuning\n' "$gpu" >&2
        exit 1
      fi

      printf '270000000\n' > "$gpu"/hwmon/hwmon*/power1_cap
      printf 'vo -60\n' > "$gpu/pp_od_clk_voltage"
      printf 'c\n' > "$gpu/pp_od_clk_voltage"
    '';
  };

  services.udev.extraRules = ''
    KERNEL=="hidraw*", ATTRS{idVendor}=="19f5", MODE="0666"
  '';

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
  services.xserver.videoDrivers = [ "amdgpu" ];
  services.desktopManager.plasma6.enable = true;

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
  services.avahi.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    raopOpenFirewall = true;
    extraConfig.pipewire.raop = {
      "context.modules" = [
        {
          name = "libpipewire-module-raop-discover";
          args."stream.rules" = [
            {
              matches = [ { "raop.ip" = "~.*"; } ];
              actions."create-stream"."stream.props"."priority.session" = 1;
            }
          ];
        }
      ];
    };
    wireplumber.extraConfig."disable-bluetooth-mics" = {
      "monitor.bluez.properties" = {
        "bluez5.roles" = [ "a2dp_sink" "a2dp_source" "bap_sink" ];
      };
    };
    #jack.enable = true;
    #media-session.enable = true;
  };

  # services.xserver.libinput.enable = true;

  programs.zsh.enable = true;

  users.users."veeti" = {
    shell = pkgs.zsh;
    isNormalUser = true;
    description = "veeti";
    extraGroups = [ "networkmanager" "wheel" "video" "render" ];
    openssh.authorizedKeys.keys = keys.admins;
    hashedPasswordFile = config.age.secrets.password.path;
  };

  programs.firefox.enable = true;
  programs.steam.enable = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  environment.systemPackages = with pkgs; [
    vim
    neovim
    git
    sbctl
    ghostty
    jellyfin-mpv-shim
    (mpv-unwrapped.override { waylandSupport = true; })
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
