{ config, inventory, pkgs, mkNginxInternal, ... }:

let
  domain = "grafana.internal.veetik.com";
  ports = config.homelab.ports;
  victoria = inventory.hosts.o11y;
  victoriaHost = "${victoria.hostname}.internal.veetik.com";
in {
  imports = [ ../tls.nix ];

  age.secrets.oidc-grafana-client-secret.owner = "grafana";
  age.secrets.victoria-query-env = {};

  systemd.services.grafana.serviceConfig.EnvironmentFile = config.age.secrets.victoria-query-env.path;

  services.grafana = {
    enable = true;
    declarativePlugins = [ pkgs.grafanaPlugins.victoriametrics-logs-datasource ];
    settings = {
      security.secret_key = "SW2YcwTIb9zpOOhoPsMm";

      server = {
        http_addr = "127.0.0.1";
        http_port = ports.grafana;
        inherit domain;
        root_url = "https://${domain}/";
      };

      "auth.generic_oauth" = {
        enabled = true;
        name = "Keycloak";
        icon = "signin";
        client_id = "grafana";
        client_secret = "$__file{${config.age.secrets.oidc-grafana-client-secret.path}}";
        scopes = "openid profile email";
        empty_scopes = false;
        auth_url = "https://auth.veetik.com/realms/main/protocol/openid-connect/auth";
        token_url = "https://auth.veetik.com/realms/main/protocol/openid-connect/token";
        api_url = "https://auth.veetik.com/realms/main/protocol/openid-connect/userinfo";
        login_attribute_path = "preferred_username";
        groups_attribute_path = "groups";
        name_attribute_path = "name";
        use_pkce = true;
        use_refresh_token = true;
        allowed_groups = "admins internal-users grafana-users grafana-admins";
        role_attribute_path = "(contains(groups[*], 'admins') || contains(groups[*], 'grafana-admins')) && 'Admin' || 'Viewer'";
        role_attribute_strict = true;
      };
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "VictoriaMetrics";
          type = "prometheus";
          uid = "victoriametrics";
          url = "https://${victoriaHost}/metrics";
          basicAuth = true;
          basicAuthUser = "grafana";
          secureJsonData.basicAuthPassword = "$VICTORIA_QUERY_PASSWORD";
          # Match vmagent's default scrape interval so $__rate_interval covers
          # enough samples, including when zooming in on process CPU/I/O.
          jsonData.timeInterval = "30s";
          isDefault = true;
        }
        {
          name = "VictoriaLogs";
          type = "victoriametrics-logs-datasource";
          uid = "victorialogs";
          url = "https://${victoriaHost}/logs";
          basicAuth = true;
          basicAuthUser = "grafana";
          secureJsonData.basicAuthPassword = "$VICTORIA_QUERY_PASSWORD";
        }
        {
          name = "VictoriaTraces";
          type = "jaeger";
          uid = "victoriatraces";
          url = "https://${victoriaHost}/traces/select/jaeger";
          basicAuth = true;
          basicAuthUser = "grafana";
          secureJsonData.basicAuthPassword = "$VICTORIA_QUERY_PASSWORD";
        }
      ];
      dashboards.settings.providers = [{
        name = "homelab";
        options.path = ./dashboards;
      }];
    };
  };

  services.nginx.virtualHosts.${domain} = mkNginxInternal {
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString ports.grafana}";
      proxyWebsockets = true;
    };
  };

  networking = {
    firewall.allowedTCPPorts = [ ports.https ];
    hosts."127.0.0.1" = [ domain ];
  };
}
