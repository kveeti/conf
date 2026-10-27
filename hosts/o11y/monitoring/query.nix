{ config, inventory, pkgs, mkNginxInternal, ... }:

let
  ports = config.homelab.ports;
  htpasswdFile = "/var/lib/nginx/victoria-query.htpasswd";
  queryConfig = ''
    limit_except GET POST { deny all; }
    proxy_set_header Authorization "";
  '';
in {
  age.secrets.victoria-query-env = {};

  system.activationScripts.victoria-query-htpasswd = {
    deps = [ "agenix" "users" ];
    text = ''
      install -d -m 0750 -o nginx -g nginx /var/lib/nginx
      tmp=$(mktemp /var/lib/nginx/victoria-query.htpasswd.XXXXXX)
      chmod 0600 "$tmp"
      . ${config.age.secrets.victoria-query-env.path}
      printf '%s' "$VICTORIA_QUERY_PASSWORD" \
        | ${pkgs.apacheHttpd}/bin/htpasswd -iB "$tmp" grafana
      chown nginx:nginx "$tmp"
      mv -f "$tmp" ${htpasswdFile}
    '';
  };

  services.nginx.virtualHosts."o11y-queries" = mkNginxInternal {
    serverName = "${inventory.hosts.o11y.hostname}.internal.veetik.com";
    basicAuthFile = htpasswdFile;
    locations = {
      "~ ^/metrics(/api/v1/(query|query_range|query_exemplars|series|labels|metadata|status/buildinfo|label/[^/%]+/values))$" = {
        proxyPass = "http://127.0.0.1:${toString ports.victoriametrics}";
        extraConfig = queryConfig + ''
          rewrite ^/metrics(/.*)$ $1 break;
        '';
      };
      "~ ^/sensors(/api/v1/(query|query_range|query_exemplars|series|labels|metadata|status/buildinfo|label/[^/%]+/values))$" = {
        proxyPass = "http://127.0.0.1:${toString ports.victoriametricsSensors}";
        extraConfig = queryConfig + ''
          rewrite ^/sensors(/.*)$ $1 break;
        '';
      };
      "~ ^/logs(/select/logsql/[a-z_]+|/health)$" = {
        proxyPass = "http://127.0.0.1:${toString ports.victorialogs}";
        extraConfig = queryConfig + ''
          rewrite ^/logs(/.*)$ $1 break;
        '';
      };
      "~ ^/traces(/select/jaeger/api/(services|services/[^/%]+/operations|operations|traces|traces/[0-9a-fA-F]+|dependencies))$" = {
        proxyPass = "http://127.0.0.1:${toString ports.victoriatraces}";
        extraConfig = ''
          rewrite ^/traces(/.*)$ $1 break;
          limit_except GET { deny all; }
          proxy_set_header Authorization "";
        '';
      };
      "/".return = "404";
    };
  };
}
