{ config, lib, pkgs, keys, ... }:

let
  inventory = import ../router/inventory.nix;
  publicIp = inventory.hosts.public.ipv4;
  adminIp = inventory.hosts.public.adminIpv4;
  gateway = inventory.networks.dmz.router4;
  backupIp = inventory.hosts.backup.ipv4;
  derivedSecretDir = "/run/public-secrets";

  finishPublicSecureBoot = pkgs.writeShellApplication {
    name = "finish-public-secure-boot";
    runtimeInputs = [ pkgs.jq pkgs.sbctl pkgs.systemd ];
    text = ''
      if [[ "$EUID" -ne 0 ]]; then
        echo "Run this command with sudo: sudo finish-public-secure-boot" >&2
        exit 1
      fi

      if [[ ! -d /sys/firmware/efi ]]; then
        echo "This system did not boot with UEFI." >&2
        exit 1
      fi

      if [[ ! -f /var/lib/sbctl/keys/db/db.key ]]; then
        echo "Generating this machine's Secure Boot keys..."
        sbctl create-keys
      fi

      echo "Signing the current boot files..."
      /run/current-system/bin/switch-to-configuration boot

      status=$(sbctl status --json)
      setup_mode=$(jq -r .setup_mode <<<"$status")
      secure_boot=$(jq -r .secure_boot <<<"$status")

      if [[ "$secure_boot" == "true" ]]; then
        echo "Secure Boot is enabled. Nothing left to do."
        exit 0
      fi

      if [[ "$setup_mode" != "true" ]]; then
        cat <<'EOF'
      Firmware is not in Setup Mode.

      Reboot into firmware setup, set an administrator password, enable Secure
      Boot, and choose "Reset Platform to Setup Mode". Do not restore factory
      keys or clear all Secure Boot keys. Boot NixOS and run this command again.
      EOF
        exit 1
      fi

      cat <<'EOF'
      The next step replaces the firmware trust keys with this machine's key.
      It enrolls only this machine's Secure Boot key.
      EOF
      read -r -p "Type ENROLL to continue: " confirmation
      if [[ "$confirmation" != "ENROLL" ]]; then
        echo "Cancelled."
        exit 1
      fi

      sbctl enroll-keys
      echo "Keys enrolled. Rebooting to enable Secure Boot."
      systemctl reboot
    '';
  };

  secretNames = [
    "password"
    "cloudflare-env-file"
    "telemetry-pass"
    "tasks-backend-env"
    "restic-tasks-rest-pass"
    "restic-tasks-encryption-pass"
    "bm-backend-env"
    "restic-bm-rest-pass"
    "restic-bm-encryption-pass"
    "modi-env"
    "restic-modi-rest-pass"
    "restic-modi-encryption-pass"
    "money-enablebanking-app-id"
    "money-enablebanking-private-key"
    "restic-money-rest-pass"
    "restic-money-encryption-pass"
    "keycloak-config-client-secret"
    "keycloak-google-client-id"
    "keycloak-google-client-secret"
    "oidc-rss-client-secret"
    "oidc-paperless-client-secret"
    "oidc-grafana-client-secret"
    "oidc-money-client-secret"
    "restic-auth-rest-pass"
    "restic-auth-encryption-pass"
  ];
in {
  imports = [
    ../modules/nixos/backedup-pg.nix
    ../modules/nixos/homelab-logs.nix
    ../modules/nixos/homelab-metrics.nix
    ../modules/nixos/homelab-nginx-metrics.nix
    ./nginx.nix
    ./keycloak.nix
    ./services.nix
  ];

  age.secrets = builtins.listToAttrs (map (name: { inherit name; value = {}; }) secretNames) // {
    tasks-backend-env = {
      owner = "tasks";
      group = "tasks";
    };
    bm-backend-env = {
      owner = "bm";
      group = "bm";
    };
  };

  system.activationScripts.public-derived-secrets = {
    deps = [ "agenix" ];
    text = ''
      install -d -m 0700 ${derivedSecretDir}

      printf 'rest:https://tasks:%s@backup.internal.veetik.com:8000/tasks' \
        "$(cat ${config.age.secrets.restic-tasks-rest-pass.path})" \
        > ${derivedSecretDir}/restic-tasks-repo
      printf 'rest:https://bm:%s@backup.internal.veetik.com:8000/bm' \
        "$(cat ${config.age.secrets.restic-bm-rest-pass.path})" \
        > ${derivedSecretDir}/restic-bm-repo
      printf 'rest:https://modi:%s@backup.internal.veetik.com:8000/modi' \
        "$(cat ${config.age.secrets.restic-modi-rest-pass.path})" \
        > ${derivedSecretDir}/restic-modi-repo
      printf 'rest:https://money:%s@backup.internal.veetik.com:8000/money' \
        "$(cat ${config.age.secrets.restic-money-rest-pass.path})" \
        > ${derivedSecretDir}/restic-money-repo
      printf 'rest:https://auth:%s@backup.internal.veetik.com:8000/auth' \
        "$(cat ${config.age.secrets.restic-auth-rest-pass.path})" \
        > ${derivedSecretDir}/restic-auth-repo

      printf 'OIDC_CLIENT_SECRET=%s\nENABLEBANKING_APP_ID=%s\n' \
        "$(cat ${config.age.secrets.oidc-money-client-secret.path})" \
        "$(cat ${config.age.secrets.money-enablebanking-app-id.path})" \
        > ${derivedSecretDir}/money-env

      chmod 0400 ${derivedSecretDir}/*
    '';
  };

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 2;
    autoGenerateKeys.enable = true;
  };
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  networking.hostId = "6f1e923a";

  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  boot.kernelParams = [ "ip=dhcp" ];
  boot.initrd = {
    systemd.users.root.shell = "/usr/bin/systemd-tty-ask-password-agent";
    availableKernelModules = [ "e1000e" ];
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

  networking = {
    hostName = "public";
    useDHCP = false;
    useNetworkd = true;
    hosts = {
      ${backupIp} = [ "backup.internal.veetik.com" ];
      ${publicIp} = [ "auth.veetik.com" ];
      ${adminIp} = [ "authadmin.veetik.com" ];
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 ];
    };
  };

  systemd.network = {
    enable = true;
    networks."10-dmz" = {
      matchConfig.Name = "en*";
      linkConfig.RequiredForOnline = "routable";
      address = [ "${publicIp}/29" "${adminIp}/29" ];
      routes = [{
        Gateway = gateway;
        PreferredSource = publicIp;
      }];
      networkConfig = {
        DHCP = "no";
        DNS = [ "1.1.1.1" "1.0.0.1" ];
      };
    };
  };

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "fi";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
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

  systemd.services.sshd = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  services.openssh = {
    enable = true;
    openFirewall = false;
    listenAddresses = [{ addr = adminIp; port = 22; }];
    settings = {
      AllowUsers = [ "veeti" ];
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      X11Forwarding = false;
    };
    hostKeys = [{ type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }];
  };

  homelab.metrics = {
    enable = true;
    remoteWriteUrl = "https://backup.internal.veetik.com:8428/api/v1/write";
    basicAuthUsername = "telemetry";
    basicAuthPasswordFile = config.age.secrets.telemetry-pass.path;
  };
  homelab.logs = {
    enable = true;
    url = "https://backup.internal.veetik.com:9428";
    basicAuthUsername = "telemetry";
    basicAuthPasswordFile = config.age.secrets.telemetry-pass.path;
  };
  homelab.nginxMetrics.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    btop
    tmux
    restic
    dnsutils
    sbctl
    finishPublicSecureBoot
  ];

  system.stateVersion = "25.11";
}
