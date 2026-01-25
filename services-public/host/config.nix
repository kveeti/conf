{ config, pkgs, lib, keys, ... }:

{
  config.boot.loader.systemd-boot.enable = true;
  config.boot.loader.efi.canTouchEfiVariables = true;

  config.boot.kernelParams = [ "ip=dhcp" ];
  config.boot.initrd = {
    availableKernelModules = [ "e1000e" "igb" ];
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

  config.networking.hostName = "services-public";
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

    runner = {
      useDefaultShell = true;
      isNormalUser = true;
      openssh.authorizedKeys.keys = keys.admins;
      hashedPasswordFile = config.age.secrets.password.path;
      linger = true;
    };
  };

  config.security.sudo.wheelNeedsPassword = false;

  config.systemd.tmpfiles.rules = [
    "d /srv/docker 0755 runner users -"
  ];

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

  # docker is rootless, it can only listen on ports >1024
  # forward 80 -> 8080 and 443 -> 8443
  config.boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
  };
  config.networking.firewall.enable = true;
  config.networking.firewall.allowedTCPPorts = [
    22

    80 443 8080 8443

    # satisfactory server
    7777 8888
  ];
  config.networking.firewall.allowedUDPPorts = [
    # satisfactory
    7777

    # teamspeak
    9987
  ];
  config.networking = {
    firewall.extraCommands = ''
      iptables -A PREROUTING -t nat -p TCP --dport 80 -j REDIRECT --to-port 8080
      iptables -A PREROUTING -t nat -p TCP --dport 443 -j REDIRECT --to-port 8443

      iptables -t nat -A OUTPUT -p tcp --dport 80 -m addrtype --dst-type LOCAL -j REDIRECT --to-port 8080
      iptables -t nat -A OUTPUT -p tcp --dport 443 -m addrtype --dst-type LOCAL -j REDIRECT --to-port 8443
    '';
  };
  config.environment.systemPackages = with pkgs; [
    vim
    git
    btop
    docker
    docker-compose
  ];

  config.services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "logind"
      "systemd"
    ];
    openFirewall = true;
  };

  config.services.alloy = {
    enable = true;
    environmentFile = config.age.secrets.alloy-env.path;
  };
  config.environment.etc."alloy/config.alloy".text = ''
    logging {
      level = "info"
    }

    discovery.relabel "node_exporter" {
      targets = [{
        __address__ = "127.0.0.1:9100",
      }]

      rule {
        replacement  = constants.hostname
        target_label = "instance"
      }
    }

    prometheus.scrape "node_exporter" {
      targets    = discovery.relabel.node_exporter.output
      forward_to = [prometheus.remote_write.victoriametrics.receiver]
      
      scrape_interval = "15s"
      scrape_timeout  = "10s"
    }

    prometheus.remote_write "victoriametrics" {
      endpoint {
        url = "https://o11s-metrics.internal.veetik.com/api/v1/write"

        basic_auth {
          username = env("METRICS_USER")
          password = env("METRICS_PASS")
        }
      }
    }
  '';

  config.virtualisation.docker = {
    enable = false;
    rootless = {
      enable = true;
      setSocketVariable = true;
      daemon.settings = {
        data-root = "/srv/docker";
        log-driver = "local";
        log-opts = {
          max-size = "10m";
          max-file = "5";
          compress = "true";
        };
      };
    };
  };

  config.system.stateVersion = "25.11";
}
