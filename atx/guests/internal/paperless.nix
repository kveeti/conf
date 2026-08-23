{ config, pkgs, withSharedVhost, ... }:

let
  domain = "p.internal.veetik.com";
  paperlessUnits = [
    "paperless-web.service"
    "paperless-scheduler.service"
    "paperless-task-queue.service"
    "paperless-consumer.service"
  ];
in {
  config.age.secrets.paperless-security-password = {};
  config.age.secrets.paperless-oidc-env = {};
  config.age.secrets.oidc-paperless-client-secret = {};
  config.age.secrets.oauth2-paperless-cookie-secret = {};

  config.homelab.volumes.paperless.owner = "paperless";

  config.services.backedupPg.instances.paperless.units = paperlessUnits;

  config.homelab.backups.instances.paperless-data = {
    paths = [ "/var/lib/paperless" ];
    after = [ "var-lib-paperless.mount" ];
    before = paperlessUnits;
    requiredBy = paperlessUnits;
    hasData = ''[ -n "$(find /var/lib/paperless/media/documents -type f -print -quit 2>/dev/null)" ]'';
    restore = ''
      restic restore --tag paperless-data latest --target / --include /var/lib/paperless
      chown -R paperless:paperless /var/lib/paperless
    '';
  };

  config.services.paperless = {
    enable = true;
    inherit domain;
    port = 20007;
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

  config.users.users.oauth2-proxy-paperless = {
    isSystemUser = true;
    group = "oauth2-proxy-paperless";
  };
  config.users.groups.oauth2-proxy-paperless = {};

  config.systemd.services.oauth2-proxy-paperless = {
    description = "OAuth2 Proxy for Paperless";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.oauth2-proxy ];
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
        --http-address=http://127.0.0.1:4181 \
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

  config.services.nginx.virtualHosts.${domain} = withSharedVhost {
    extraConfig = ''
      client_max_body_size 100M;
      auth_request /oauth2/auth;
      error_page 401 = @paperless_oauth2_start;
    '';
    locations."/oauth2/" = {
      proxyPass = "http://127.0.0.1:4181";
      extraConfig = ''
        auth_request off;
        proxy_buffer_size 32k;
        proxy_buffers 4 32k;
        proxy_busy_buffers_size 64k;
        proxy_set_header X-Scheme $scheme;
        proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
      '';
    };
    locations."= /oauth2/auth" = {
      proxyPass = "http://127.0.0.1:4181";
      extraConfig = ''
        auth_request off;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Scheme $scheme;
      '';
    };
    locations."@paperless_oauth2_start" = {
      return = "307 https://${domain}/oauth2/start?rd=$scheme://$host$request_uri";
      extraConfig = ''
        auth_request off;
      '';
    };
    locations."/".proxyPass = "http://127.0.0.1:20007";
  };
}
