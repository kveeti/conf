{ config, pkgs, ... }:

let
  htpasswdFile = "/var/lib/nginx/telemetry.htpasswd";
  traceHtpasswdFile = pkgs.writeText "otel-traces.htpasswd" ''
    food:$2y$12$qNF47IlE0zgk/St601xSe.PFXZE6LI4EyslpBEnaGVIkyS32bS2V.
  '';
  ports = config.homelab.ports;
in {
  imports = [ ../tls.nix ];

  system.activationScripts.telemetry-htpasswd = {
    deps = [ "agenix" "users" ];
    text = ''
      install -d -m 0750 -o nginx -g nginx /var/lib/nginx
      tmp=$(mktemp /var/lib/nginx/telemetry.htpasswd.XXXXXX)
      chmod 0600 "$tmp"
      printf '%s' "$(cat ${config.age.secrets.telemetry-pass.path})" \
        | ${pkgs.apacheHttpd}/bin/htpasswd -iB "$tmp" telemetry
      chown nginx:nginx "$tmp"
      mv -f "$tmp" ${htpasswdFile}
    '';
  };

  services.nginx.virtualHosts = {
    "backup-metrics" = {
      serverName = "metrics.internal.veetik.com";
      onlySSL = true;
      useACMEHost = "internal.veetik.com";
      listen = [{ addr = "0.0.0.0"; port = ports.https; ssl = true; }];
      locations = {
        "= /api/v1/write" = {
          proxyPass = "http://127.0.0.1:${toString ports.victoriametrics}";
          basicAuthFile = htpasswdFile;
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

    "backup-traces" = {
      serverName = "traces.internal.veetik.com";
      onlySSL = true;
      useACMEHost = "internal.veetik.com";
      listen = [{ addr = "0.0.0.0"; port = ports.https; ssl = true; }];
      locations."/" = {
        basicAuthFile = traceHtpasswdFile;
        extraConfig = ''
          grpc_set_header Authorization "";
          grpc_set_header X-Telemetry-Client $remote_user;
          grpc_read_timeout 60s;
          grpc_send_timeout 60s;
          grpc_pass grpc://127.0.0.1:${toString ports.otelCollector};
        '';
      };
    };

    "backup-logs" = {
      serverName = "logs.internal.veetik.com";
      onlySSL = true;
      useACMEHost = "internal.veetik.com";
      listen = [{ addr = "0.0.0.0"; port = ports.https; ssl = true; }];
      locations = {
        "= /insert/elasticsearch/_bulk" = {
          proxyPass = "http://127.0.0.1:${toString ports.victorialogs}";
          basicAuthFile = htpasswdFile;
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
  };

  networking.firewall.allowedTCPPorts = [ ports.https ];
}
