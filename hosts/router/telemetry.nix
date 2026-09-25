{ config, inventory, pkgs, ... }:

let
  unifi = inventory.hosts.unifi;
  ports = config.homelab.ports;

  blackboxConfig = pkgs.writeText "router-blackbox.yml" (builtins.toJSON {
    modules = {
      icmp = {
        prober = "icmp";
        timeout = "5s";
      };
      dns_soa = {
        prober = "dns";
        timeout = "5s";
        dns = {
          query_name = "veetik.com";
          query_type = "SOA";
        };
      };
      http_2xx = {
        prober = "http";
        timeout = "5s";
        http.preferred_ip_protocol = "ip4";
      };
    };
  });

  blackboxJob = name: module: targets: {
    job_name = "blackbox-${name}";
    metrics_path = "/probe";
    params.module = [ module ];
    static_configs = [{ inherit targets; }];
    relabel_configs = [
      {
        source_labels = [ "__address__" ];
        target_label = "__param_target";
      }
      {
        source_labels = [ "__param_target" ];
        target_label = "instance";
      }
      {
        target_label = "__address__";
        replacement = "127.0.0.1:${toString ports.blackboxExporter}";
      }
    ];
  };
in {
  imports = [
    ../../modules/telemetry/logs.nix
    ../../modules/telemetry/metrics.nix
  ];

  age.secrets = {
    telemetry-pass = {};
    unpoller-env = {};
  };

  services.prometheus.exporters = {
    wireguard = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = ports.wireguardExporter;
      interfaces = [ inventory.networks.wireguard.interface ];
    };

    unbound = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = ports.unboundExporter;
      unbound.host = "unix:///run/unbound/unbound.ctl";
      unbound.ca = null;
      unbound.certificate = null;
      unbound.key = null;
    };

    blackbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = ports.blackboxExporter;
      configFile = blackboxConfig;
    };

    unpoller = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = ports.unifiExporter;
      controllers = [{
        url = "https://${unifi.ipv4}:${toString unifi.ports.web}";
        user = "metrics";
        verify_ssl = false;
      }];
    };
  };

  services.prometheus.exporters.node.extraFlags = [
    "--collector.textfile.directory=/var/lib/node-exporter-textfile"
  ];
  systemd.tmpfiles.rules = [
    "d /var/lib/node-exporter-textfile 0755 root root -"
  ];

  systemd.services.prometheus-unpoller-exporter.serviceConfig.EnvironmentFile =
    config.age.secrets.unpoller-env.path;

  homelab = {
    metrics = {
      enable = true;
      listenAddress = "127.0.0.1:${toString ports.vmagent}";
      nodeExporter = {
        port = ports.nodeExporter;
        collectors = [ "systemd" "ethtool" ];
      };
      remoteWriteUrl = "https://metrics.internal.veetik.com/api/v1/write";
      username = "telemetry";
      passwordFile = config.age.secrets.telemetry-pass.path;
      scrapes = {
        wireguard.targets = [ "127.0.0.1:${toString ports.wireguardExporter}" ];
        unbound.targets = [ "127.0.0.1:${toString ports.unboundExporter}" ];
        unifi.targets = [ "127.0.0.1:${toString ports.unifiExporter}" ];
      };
      extraScrapeConfigs = [
        (blackboxJob "icmp" "icmp" [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ])
        (blackboxJob "dns" "dns_soa" [ "1.1.1.1" "8.8.8.8" ])
        (blackboxJob "http" "http_2xx" [ "https://www.google.com" "https://cloudflare.com" ])
      ];
    };

    logs = {
      enable = true;
      url = "https://logs.internal.veetik.com";
      username = "telemetry";
      passwordFile = config.age.secrets.telemetry-pass.path;
    };
  };
}
