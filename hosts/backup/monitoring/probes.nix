{ config, inventory, lib, pkgs, ... }:

let
  publicIp = inventory.hosts.public.ipv4;
  ports = config.homelab.ports;

  publicProbes = [
    { host = "tasks-api.veetik.com"; path = "/api/v1/auth/me"; }
    { host = "bm_back.veetik.com"; path = "/api/bootstrap"; }
    { host = "money.veetik.com"; path = "/api/v1/currencies"; }
  ];

  moduleName = host: "lan-" + builtins.replaceStrings [ "." ] [ "-" ] host;

  baseHttp = {
    prober = "http";
    timeout = "5s";
    http = {
      preferred_ip_protocol = "ip4";
      fail_if_not_ssl = true;
      no_follow_redirects = true;
      valid_status_codes = [ 200 204 301 302 401 403 ];
    };
  };

  publicHttp = baseHttp // {
    http = baseHttp.http // { valid_status_codes = [ 401 ]; };
  };

  blackboxConfig = pkgs.writeText "blackbox.yml" (builtins.toJSON {
    modules = {
      http = baseHttp;
      public = publicHttp;
    } // builtins.listToAttrs (map (probe: {
      name = moduleName probe.host;
      value = publicHttp // {
        http = publicHttp.http // {
          headers.Host = probe.host;
          tls_config.server_name = probe.host;
        };
      };
    }) publicProbes);
  });

  job = name: module: targets: {
    job_name = "blackbox-${name}";
    metrics_path = "/probe";
    params.module = [ module ];
    static_configs = [{ inherit targets; }];
    relabel_configs = [
      { source_labels = [ "__address__" ]; target_label = "__param_target"; }
      { source_labels = [ "__param_target" ]; target_label = "instance"; }
      { target_label = "__address__"; replacement = "127.0.0.1:${toString ports.blackboxExporter}"; }
    ];
  };

  lanJob = probe: {
    job_name = "blackbox-lan-${builtins.replaceStrings [ "." ] [ "-" ] probe.host}";
    metrics_path = "/probe";
    params.module = [ (moduleName probe.host) ];
    static_configs = [{ targets = [ "https://${publicIp}${probe.path}" ]; }];
    relabel_configs = [
      { source_labels = [ "__address__" ]; target_label = "__param_target"; }
      { target_label = "instance"; replacement = "https://${probe.host}${probe.path}"; }
      { target_label = "__address__"; replacement = "127.0.0.1:${toString ports.blackboxExporter}"; }
    ];
  };
in {
  services.prometheus.exporters.blackbox = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = ports.blackboxExporter;
    configFile = blackboxConfig;
  };

  homelab.logs.units."prometheus-blackbox-exporter.service".format = "logfmt";

  homelab.metrics.extraScrapeConfigs = [
    (job "public" "public" (map (probe: "https://${probe.host}${probe.path}") publicProbes))
    (job "auth" "http" [
      "https://auth.veetik.com/realms/main/.well-known/openid-configuration"
    ])
  ] ++ map lanJob publicProbes;

  networking.hosts.${publicIp} = [ "auth.veetik.com" ];
}
