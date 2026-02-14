{ config, pkgs, lib, keys, ... }:

{
  imports = [
    ./things/lldap.nix
    ./things/authelia.nix
    ./things/radicale.nix
    ./things/rss.nix
    ./things/money.nix
    ./things/shared-folder.nix
    ./things/weather.nix
  ];

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

  config.networking.hostName = "nix-services-internal";
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

  # certs
  config.security.acme = {
    acceptTerms = true;
    defaults.email = "security@veetik.com";
    certs = {
      "internal.veetik.com" = {
        domain = "*.internal.veetik.com";
        dnsProvider = "cloudflare";
        dnsResolver = "1.1.1.1";
        environmentFile = config.age.secrets.cloudflare-env-file.path;
        group = config.services.nginx.group;
      };
    };
  };
  config.security.acme.defaults.server = "https://acme-v02.api.letsencrypt.org/directory";
  # config.security.acme.defaults.server = "https://acme-staging-v02.api.letsencrypt.org/directory";


  config.services.nginx = {
    enable = true;

    statusPage = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;

    appendHttpConfig = ''
      proxy_buffer_size 16k;
      proxy_buffers 8 16k;
      proxy_busy_buffers_size 32k;
      large_client_header_buffers 4 16k;
    '';
  };

  config.boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
  };
  config.networking.firewall.enable = true;
  config.networking.firewall.allowedTCPPorts = [22 80 443 8080 8443];
  config.environment.systemPackages = with pkgs; [
    vim
    git
    btop
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
    extraFlags = ["--disable-reporting"];
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

  config.services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    enableJIT = true;
    enableTCPIP = true;
    authentication = ''
      #     DATABASE USER        AUTHENTICATION
      local all      all         peer
    '';
    ensureDatabases = [
      "postgres"
      "root"
    ];
    ensureUsers = [
      {
        name = "postgres";
        ensureDBOwnership = true;
        ensureClauses = {
          login     = true;
          superuser = true;
        };
      }
      {
        name = "root";
        ensureDBOwnership = true;
        ensureClauses = {
          login     = true;
          superuser = true;
        };
      }
    ];
  };

  config.virtualisation.containers.enable = true;
  config.virtualisation = {
    docker.enable = lib.mkForce false;
    oci-containers.backend = "podman";
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = false;
    };
  };

  config.system.stateVersion = "25.11";
}

