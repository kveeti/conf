{ config, pkgs, lib, ... }:

let
  inventory = import ./inventory.nix;
  backupIp = inventory.hosts.backup.ipv4;
  unifiIp = inventory.hosts.unifiController.ipv4;

  blackboxConfig = pkgs.writeText "blackbox.yml" (builtins.toJSON {
    modules = {
      icmp = { prober = "icmp"; timeout = "5s"; };
      dns_soa = {
        prober = "dns";
        timeout = "5s";
        dns = { query_name = "veetik.com"; query_type = "SOA"; };
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
      { source_labels = [ "__address__" ]; target_label = "__param_target"; }
      { source_labels = [ "__param_target" ]; target_label = "instance"; }
      { target_label = "__address__"; replacement = "127.0.0.1:9115"; }
    ];
  };
in {
  imports = [
    ../modules/nixos/homelab-metrics.nix
    ../modules/nixos/homelab-logs.nix
  ];

  services.prometheus.exporters = {
    wireguard = {
      enable = true;
      listenAddress = "127.0.0.1";
      interfaces = [ "wg0" ];
    };
    unbound = {
      enable = true;
      listenAddress = "127.0.0.1";
      # plaintext unix socket (config.nix remote-control); null cert paths so no TLS handshake
      unbound.host = "unix:///run/unbound/unbound.ctl";
      unbound.ca = null;
      unbound.certificate = null;
      unbound.key = null;
    };
    blackbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      configFile = blackboxConfig;
    };
    # with a controller defined, unpoller ignores UP_UNIFI_DEFAULT_* — overrides must use indexed UP_UNIFI_CONTROLLER_0_*
    unpoller = {
      enable = true;
      listenAddress = "127.0.0.1";
      controllers = [{
        url = "https://${unifiIp}:8443";
        user = "metrics";
        verify_ssl = false;
      }];
    };
  };

  systemd.services.prometheus-unpoller-exporter.serviceConfig.EnvironmentFile =
    config.age.secrets.unpoller-env.path;

  networking.hosts.${backupIp} = [ "backup.internal.veetik.com" ];

  homelab.metrics = {
    enable = true;
    instance = "router";
    remoteWriteUrl = "https://backup.internal.veetik.com:8428/api/v1/write";
    basicAuthUsername = "telemetry";
    basicAuthPasswordFile = config.age.secrets.telemetry-pass.path;
    nodeExporter.enabledCollectors = [ "systemd" "ethtool" ];
    scrapeConfigs = [
      { job_name = "wireguard"; static_configs = [{ targets = [ "127.0.0.1:9586" ]; }]; }
      { job_name = "unbound";   static_configs = [{ targets = [ "127.0.0.1:9167" ]; }]; }
      { job_name = "unifi";     static_configs = [{ targets = [ "127.0.0.1:9130" ]; }]; }
      (blackboxJob "icmp" "icmp"     [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ])
      (blackboxJob "dns"  "dns_soa"  [ "1.1.1.1" "8.8.8.8" ])
      (blackboxJob "http" "http_2xx" [ "https://www.google.com" "https://cloudflare.com" ])
    ];
  };

  homelab.logs = {
    enable = true;
    url = "https://backup.internal.veetik.com:9428";
    basicAuthUsername = "telemetry";
    basicAuthPasswordFile = config.age.secrets.telemetry-pass.path;
  };
}
