{ config, pkgs, ... }:

let
  htpasswdFile = "/var/lib/nginx/telemetry.htpasswd";
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
      serverName = "backup.internal.veetik.com";
      onlySSL = true;
      useACMEHost = "internal.veetik.com";
      listen = [{ addr = "0.0.0.0"; port = 8428; ssl = true; }];
      locations = {
        "= /api/v1/write" = {
          proxyPass = "http://127.0.0.1:18428";
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

    "backup-logs" = {
      serverName = "backup.internal.veetik.com";
      onlySSL = true;
      useACMEHost = "internal.veetik.com";
      listen = [{ addr = "0.0.0.0"; port = 9428; ssl = true; }];
      locations = {
        "= /insert/elasticsearch/_bulk" = {
          proxyPass = "http://127.0.0.1:19428";
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

  networking = {
    firewall.allowedTCPPorts = [ 8428 9428 ];
    hosts."127.0.0.1" = [ "backup.internal.veetik.com" ];
  };
}
