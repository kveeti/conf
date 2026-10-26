{ config, inventory, lib, pkgs, ... }:

let
  ingress = inventory.hosts.worker;
  ports = config.homelab.ports;

  publicProbes = [
    { host = "tasks.veetik.com"; path = "/api/health"; status = 200; }
    { host = "bm.veetik.com"; path = "/api/bootstrap"; status = 401; }
    { host = "money.veetik.com"; path = "/api/health"; status = 200; }
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
          valid_status_codes = [ probe.status ];
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
    static_configs = [{ targets = [ "https://${ingress.ipv4}:${toString ingress.ports.publicHttps}${probe.path}" ]; }];
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
    ((job "public" "public" []) // {
      static_configs = map (probe: {
        targets = [ "https://${probe.host}${probe.path}" ];
        labels.__param_module = moduleName probe.host;
      }) publicProbes;
    })
    (job "auth" "http" [
      "https://auth.veetik.com/realms/main/.well-known/openid-configuration"
    ])
  ] ++ map lanJob publicProbes;

}
