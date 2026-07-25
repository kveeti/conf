{ config, pkgs, lib, ... }:

let
  domain = "grafana.internal.veetik.com";
  inventory = import ../router/inventory.nix;
  ssoHost = inventory.hosts.atxInternal.ipv4;
  internalIp = inventory.hosts.atxInternal.ipv4;
  nginxPublicIp = inventory.hosts.nginxPublic.ipv4;
  telemetryHtpasswd = "/var/lib/nginx/telemetry.htpasswd";

  publicProbes = [
    { host = "tasks-api.veetik.com"; path = "/api/v1/auth/me"; }
    { host = "bm_back.veetik.com"; path = "/api/bootstrap"; }
  ];
  lanModuleName = host: "lan-" + builtins.replaceStrings [ "." ] [ "-" ] host;

  baseHttp = {
    prober = "http";
    timeout = "5s";
    http = {
      preferred_ip_protocol = "ip4";
      fail_if_not_ssl = true;
      valid_status_codes = [ 200 204 301 302 401 403 ];
    };
  };

  publicHttp = baseHttp // {
    http = baseHttp.http // { valid_status_codes = [ 401 ]; };
  };

  blackboxConfig = pkgs.writeText "blackbox.yml" (builtins.toJSON {
    modules = {
      http_2xx = baseHttp;
      http_2xx_public = publicHttp;
    } // builtins.listToAttrs (map (p: {
      name = lanModuleName p.host;
      value = publicHttp // {
        http = publicHttp.http // {
          headers.Host = p.host;
          tls_config.server_name = p.host;
        };
      };
    }) publicProbes);
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

  blackboxLanJob = p: {
    job_name = "blackbox-lan-${builtins.replaceStrings [ "." ] [ "-" ] p.host}";
    metrics_path = "/probe";
    params.module = [ (lanModuleName p.host) ];
    static_configs = [{ targets = [ "https://${nginxPublicIp}${p.path}" ]; }];
    relabel_configs = [
      { source_labels = [ "__address__" ]; target_label = "__param_target"; }
      { target_label = "instance"; replacement = "https://${p.host}${p.path}"; }
      { target_label = "__address__"; replacement = "127.0.0.1:9115"; }
    ];
  };
in {
  imports = [
    ../modules/nixos/homelab-metrics.nix
    ../modules/nixos/homelab-logs.nix
  ];

  services.victoriametrics = {
    enable = true;
    listenAddress = "127.0.0.1:18428";
    stateDir = "victoriametrics";
    retentionPeriod = "12";
  };

  services.victorialogs = {
    enable = true;
    listenAddress = "127.0.0.1:19428";
    stateDir = "victorialogs";
    extraOptions = [ "-retentionPeriod=90d" ];
  };

  services.grafana = {
    enable = true;
    declarativePlugins = [ pkgs.grafanaPlugins.victoriametrics-logs-datasource ];
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        inherit domain;
        root_url = "https://${domain}/";
      };

      "auth.generic_oauth" = {
        enabled = true;
        name = "Authelia";
        icon = "signin";
        client_id = "grafana";
        client_secret = "$__file{${config.age.secrets.oidc-grafana-client-secret.path}}";
        scopes = "openid profile email groups";
        empty_scopes = false;
        auth_url = "https://sso.internal.veetik.com/api/oidc/authorization";
        token_url = "https://sso.internal.veetik.com/api/oidc/token";
        api_url = "https://sso.internal.veetik.com/api/oidc/userinfo";
        login_attribute_path = "preferred_username";
        groups_attribute_path = "groups";
        name_attribute_path = "name";
        use_pkce = true;
        role_attribute_path = "(contains(groups[*], 'admins') || contains(groups[*], 'grafana-admin')) && 'Admin' || 'Viewer'";
        role_attribute_strict = false;
      };
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "VictoriaMetrics";
          type = "prometheus";
          uid = "victoriametrics";
          url = "http://127.0.0.1:18428";
          isDefault = true;
        }
        {
          name = "VictoriaLogs";
          type = "victoriametrics-logs-datasource";
          uid = "victorialogs";
          url = "http://127.0.0.1:19428";
        }
      ];

      dashboards.settings.providers = [{
        name = "homelab";
        options.path = ./dashboards;
      }];
    };
  };

  security.acme.certs."internal.veetik.com" = {
    domain = "internal.veetik.com";
    extraDomainNames = [ "*.internal.veetik.com" ];
    group = config.services.nginx.group;
  };

  services.nginx.virtualHosts.${domain} = {
    onlySSL = true;
    useACMEHost = "internal.veetik.com";
    listen = [{ addr = "0.0.0.0"; port = 443; ssl = true; }];
    locations."/" = {
      proxyPass = "http://127.0.0.1:3000";
      proxyWebsockets = true;
    };
  };

  # TLS write-only fronts for VictoriaMetrics/Logs. Grafana talks directly to
  # the loopback listeners, so remote clients never need query/admin API access.
  system.activationScripts.telemetry-htpasswd = {
    deps = [ "agenix" "users" ];
    text = ''
      install -d -m 0750 -o nginx -g nginx /var/lib/nginx
      install -m 0600 -o nginx -g nginx /dev/null ${telemetryHtpasswd}
      printf '%s' "$(cat ${config.age.secrets.telemetry-pass.path})" \
        | ${pkgs.apacheHttpd}/bin/htpasswd -iB ${telemetryHtpasswd} telemetry
    '';
  };

  services.nginx.virtualHosts."backup-metrics" = {
    serverName = "backup.internal.veetik.com";
    onlySSL = true;
    useACMEHost = "internal.veetik.com";
    listen = [{ addr = "0.0.0.0"; port = 8428; ssl = true; }];
    locations = {
      "= /api/v1/write" = {
        proxyPass = "http://127.0.0.1:18428";
        basicAuthFile = telemetryHtpasswd;
        extraConfig = ''
          limit_except POST { deny all; }
          client_max_body_size 16m;
          proxy_request_buffering off;
          proxy_set_header Authorization "";
        '';
      };
      "/".return = "404";
    };
  };
  services.nginx.virtualHosts."backup-logs" = {
    serverName = "backup.internal.veetik.com";
    onlySSL = true;
    useACMEHost = "internal.veetik.com";
    listen = [{ addr = "0.0.0.0"; port = 9428; ssl = true; }];
    locations = {
      "= /insert/elasticsearch/_bulk" = {
        proxyPass = "http://127.0.0.1:19428";
        basicAuthFile = telemetryHtpasswd;
        extraConfig = ''
          limit_except POST { deny all; }
          client_max_body_size 16m;
          proxy_request_buffering off;
          proxy_set_header Authorization "";
        '';
      };
      "/".return = "404";
    };
  };

  networking.firewall.allowedTCPPorts = [ 443 8428 9428 ];

  networking.hosts.${internalIp} = [
    "sso.internal.veetik.com"
    "dav.internal.veetik.com"
    "food.internal.veetik.com"
    "weather.internal.veetik.com"
    "p.internal.veetik.com"
    "rss.internal.veetik.com"
  ];
  networking.hosts."127.0.0.1" = [ "grafana.internal.veetik.com" "backup.internal.veetik.com" ];

  # Must be owned by grafana or it can't read the secret at startup and won't come up.
  age.secrets.oidc-grafana-client-secret.owner = "grafana";

  services.prometheus.exporters.smartctl = {
    enable = true;
    listenAddress = "127.0.0.1";
  };
  services.prometheus.exporters.blackbox = {
    enable = true;
    listenAddress = "127.0.0.1";
    configFile = blackboxConfig;
  };

  homelab.metrics = {
    enable = true;
    remoteWriteUrl = "http://127.0.0.1:18428/api/v1/write";
    scrapeConfigs = [
      { job_name = "smartctl"; static_configs = [{ targets = [ "127.0.0.1:9633" ]; }]; }
      { job_name = "victoriametrics"; static_configs = [{ targets = [ "127.0.0.1:18428" ]; }]; }
      { job_name = "vmagent"; static_configs = [{ targets = [ "127.0.0.1:8429" ]; }]; }
      (blackboxJob "public" "http_2xx_public" (map (p: "https://${p.host}${p.path}") publicProbes))
      (blackboxJob "internal" "http_2xx" [
        "https://sso.internal.veetik.com"
        "https://dav.internal.veetik.com"
        "https://food.internal.veetik.com"
        "https://weather.internal.veetik.com"
        "https://p.internal.veetik.com"
        "https://rss.internal.veetik.com"
        "https://grafana.internal.veetik.com"
        "https://backup.internal.veetik.com:8000"
      ])
    ]
    ++ map blackboxLanJob publicProbes;
  };
  homelab.logs = {
    enable = true;
    url = "http://127.0.0.1:19428";
  };
}
