{ config, pkgs, lib, keys, ... }:

let
  IF_LAN = "enp1s0f1";
in
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

  config.networking.hostName = "servers";
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

  config.age.secrets.password.file = ./secrets/password.age;
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
  config.boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
  };
  config.networking.firewall.enable = true;
  config.networking.nftables.enable = true;
  config.networking.firewall.allowedTCPPorts = [22 80 8080 7777 8888];
  config.networking.firewall.allowedUDPPorts = [7777];
  config.networking.nftables.flushRuleset = true;
  config.networking.nftables.tables.nat = {
    enable = true;
    family = "ip";
    content = ''
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;

        ip daddr 192.168.40.8 meta l4proto tcp th dport 80 counter dnat to :8080
      }

      chain output {
        type nat hook output priority -100; policy accept;
        ip daddr 192.168.40.8 tcp dport 80 dnat to :8080
      }
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

  config.age.secrets.alloy-env.file = ./secrets/alloy-env.age;
  config.services.alloy = {
    enable = true;
    environmentFile = config.age.secrets.alloy-env.path;
  };
  config.environment.etc."alloy/config.alloy".text = ''
    logging {
      level = "info"
    }

    //
    // LOGS
    //
    loki.source.journal "docker_logs" {
      max_age       = "24h"
      matches       = "_SYSTEMD_USER_UNIT=docker.service"
      forward_to    = [loki.write.victorialogs.receiver]
      relabel_rules = loki.relabel.docker_logs.rules
    }

    loki.relabel "docker_logs" {
      // compose directory name
      // eg: o11s
      rule {
        source_labels = ["__journal_com_docker_compose_project"]
        target_label  = "compose_project"
      }

      // compose service name
      // eg: traefik
      rule {
        source_labels = ["__journal_com_docker_compose_service"]
        target_label  = "compose_service"
      }

      // container short unique id
      // eg: 1991eab3968b
      rule {
        source_labels = ["__journal_container_id"]
        target_label  = "container_id"
      }

      // container name
      // with compose will be eg: o11s-traefik-1
      //   where "o11s" is the compose project, "traefik" is the service name
      //   and 1 is the instance count of that compose service
      rule {
        source_labels = ["__journal_container_name"]
        target_label  = "container_name"
      }

      // image name with tag
      // eg: docker.io/traefik@sha256:c8bcb479c8057a29b05b1f3a5dcfb580fa67bc6adc41e48eabb168512c6a8c8b
      rule {
        source_labels = ["__journal_image_name"]
        target_label  = "image"
      }

      // journald default _hostname field
      rule {
        source_labels = ["__journal__hostname"]
        target_label  = "host"
      }

      forward_to = []
    }

    loki.write "victorialogs" {
      endpoint {
        url = "https://o11s-logs.internal.veetik.com/insert/loki/api/v1/push"

        basic_auth {
          username = env("LOGS_USER")
          password = env("LOGS_PASS")
        }
      }
    }
    //
    // LOGS
    //


    //
    // METRICS
    //
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
    //
    // METRICS
    //
  '';

  config.virtualisation.docker = {
    enable = false;
    rootless = {
      enable = true;
      setSocketVariable = true;
      daemon.settings = {
        dns = [ "192.168.40.1" "1.1.1.1" "8.8.8.8" ];
        data-root = "/srv/docker";
        log-driver = "journald";
        log-opts = {
          labels = "com.docker.compose.service,com.docker.compose.project";
        };
      };
    };
  };

  config.system.stateVersion = "25.11";
}
