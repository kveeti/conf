{ config, pkgs, withSharedVhost, ... }:

let
  domain = "p.internal.veetik.com";
  state = "/var/lib/paperless";
  ports = config.homelab.ports;
  units = [
    "paperless-web"
    "paperless-scheduler"
    "paperless-task-queue"
    "paperless-consumer"
  ];
  systemdUnits = map (unit: "${unit}.service") units;
in {
  age.secrets = {
    paperless-security-password = {};
    paperless-oidc-env = {};
    oidc-paperless-client-secret = {};
    oauth2-paperless-cookie-secret = {};
  };

  homelab.volumes.paperless = {
    path = state;
    owner = "paperless";
  };

  homelab.postgresql.databases.paperless = {
    services = units;
    backup = {
      repository = "internal";
      tag = "paperless";
      restPasswordFile = "/run/secrets/restic-internal-rest-pass";
      encryptionPasswordFile = "/run/secrets/restic-internal-encryption-pass";
    };
  };

  homelab.backups.instances.paperless-data = {
    repository = "internal";
    username = "internal";
    tag = "paperless-data";
    restPasswordFile = "/run/secrets/restic-internal-rest-pass";
    encryptionPasswordFile = "/run/secrets/restic-internal-encryption-pass";
    paths = [ state ];
    after = [ "var-lib-paperless.mount" ];
    before = systemdUnits;
    requiredBy = systemdUnits;
    restoreMarker = "${state}/.restore-in-progress";
    hasData = ''[ -n "$(find ${state}/media/documents -type f -print -quit 2>/dev/null)" ]'';
    restore = ''
      restic restore --tag paperless-data latest --target / --include ${state}
      chown -R paperless:paperless ${state}
    '';
  };

  services.paperless = {
    enable = true;
    inherit domain;
    port = ports.paperless;
    address = "127.0.0.1";
    passwordFile = config.age.secrets.paperless-security-password.path;
    environmentFile = config.age.secrets.paperless-oidc-env.path;
    settings = {
      PAPERLESS_ADMIN_USER = "security";
      PAPERLESS_DBHOST = "/var/run/postgresql";
      PAPERLESS_URL = "https://${domain}";
      PAPERLESS_ACCOUNT_DEFAULT_HTTP_PROTOCOL = "https";
      PAPERLESS_DISABLE_REGULAR_LOGIN = false;
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
    };
  };

  users.groups.oauth2-proxy-paperless = {};
  users.users.oauth2-proxy-paperless = {
    isSystemUser = true;
    group = "oauth2-proxy-paperless";
  };

  systemd.services.oauth2-proxy-paperless = {
    description = "OAuth2 Proxy for Paperless";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.coreutils pkgs.oauth2-proxy ];
    script = ''
      base64 --decode "$CREDENTIALS_DIRECTORY/cookie-secret" > "$RUNTIME_DIRECTORY/cookie-secret"
      chmod 0400 "$RUNTIME_DIRECTORY/cookie-secret"

      exec oauth2-proxy \
        --provider=keycloak-oidc \
        --client-id=paperless \
        --client-secret-file="$CREDENTIALS_DIRECTORY/client-secret" \
        --oidc-issuer-url=https://auth.veetik.com/realms/main \
        --redirect-url=https://${domain}/oauth2/callback \
        --scope="openid profile email" \
        --email-domain='*' \
        --upstream=static://202 \
        --http-address=http://127.0.0.1:${toString ports.oauth2Paperless} \
        --reverse-proxy=true \
        --trusted-proxy-ip=127.0.0.1/32 \
        --set-xauthrequest=true \
        --pass-basic-auth=false \
        --cookie-name=_oauth2_proxy_paperless \
        --cookie-secret-file="$RUNTIME_DIRECTORY/cookie-secret" \
        --cookie-expire=168h \
        --cookie-refresh=5m \
        --code-challenge-method=S256 \
        --allowed-group=admins \
        --allowed-group=internal-users \
        --allowed-group=paperless-users \
        --whitelist-domain=.internal.veetik.com \
        --skip-provider-button=true
    '';
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      User = "oauth2-proxy-paperless";
      Group = "oauth2-proxy-paperless";
      Restart = "always";
      RestartSec = 5;
      RuntimeDirectory = "oauth2-proxy-paperless";
      RuntimeDirectoryMode = "0700";
      LoadCredential = [
        "client-secret:${config.age.secrets.oidc-paperless-client-secret.path}"
        "cookie-secret:${config.age.secrets.oauth2-paperless-cookie-secret.path}"
      ];
    };
  };

  services.nginx.virtualHosts.${domain} = withSharedVhost {
    extraConfig = ''
      client_max_body_size 100M;
      auth_request /oauth2/auth;
      error_page 401 = @paperless_oauth2_start;
    '';
    locations = {
      "/oauth2/" = {
        proxyPass = "http://127.0.0.1:${toString ports.oauth2Paperless}";
        extraConfig = ''
          auth_request off;
          proxy_buffer_size 32k;
          proxy_buffers 4 32k;
          proxy_busy_buffers_size 64k;
          proxy_set_header X-Scheme $scheme;
          proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
        '';
      };
      "= /oauth2/auth" = {
        proxyPass = "http://127.0.0.1:${toString ports.oauth2Paperless}";
        extraConfig = ''
          auth_request off;
          proxy_pass_request_body off;
          proxy_set_header Content-Length "";
          proxy_set_header X-Scheme $scheme;
        '';
      };
      "@paperless_oauth2_start" = {
        return = "307 https://${domain}/oauth2/start?rd=$scheme://$host$request_uri";
        extraConfig = "auth_request off;";
      };
      "/".proxyPass = "http://127.0.0.1:${toString ports.paperless}";
    };
  };
}
