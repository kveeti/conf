{ config, pkgs, ... }:

let
  domain = "grafana.internal.veetik.com";
  ports = config.homelab.ports;
in {
  imports = [ ../tls.nix ];

  age.secrets.oidc-grafana-client-secret.owner = "grafana";

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
          url = "http://127.0.0.1:${toString ports.victoriametrics}";
          isDefault = true;
        }
        {
          name = "VictoriaLogs";
          type = "victoriametrics-logs-datasource";
          uid = "victorialogs";
          url = "http://127.0.0.1:${toString ports.victorialogs}";
        }
        {
          name = "VictoriaTraces";
          type = "jaeger";
          uid = "victoriatraces";
          url = "http://127.0.0.1:${toString ports.victoriatraces}/select/jaeger";
        }
      ];
      dashboards.settings.providers = [{
        name = "homelab";
        options.path = ./dashboards;
      }];
    };
  };

  services.nginx.virtualHosts.${domain} = {
    onlySSL = true;
    useACMEHost = "internal.veetik.com";
    listen = [{ addr = "0.0.0.0"; port = ports.https; ssl = true; }];
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
