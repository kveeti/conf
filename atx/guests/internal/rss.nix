{ config, lib, withSharedVhost, ... }:

let
  domain = "rss.internal.veetik.com";
in {
  config.age.secrets.oidc-rss-client-secret = {};
  config.age.secrets.oauth2-rss-cookie-secret = {};

  config.services.backedupPg.instances.rss = {};

  config.services.rss = {
    enable = true;

    environment = {
      RUST_LOG = "info";
      DATABASE_URL = "postgresql://rss@127.0.0.1/rss?host=/run/postgresql";
      HOST = "127.0.0.1:20000";
    };
  };

  config.services.oauth2-proxy = {
    enable = true;
    provider = "keycloak-oidc";
    clientID = "rss";
    clientSecretFile = config.age.secrets.oidc-rss-client-secret.path;
    oidcIssuerUrl = "https://auth.veetik.com/realms/main";
    redirectURL = "https://${domain}/oauth2/callback";
    scope = "openid profile email";
    email.domains = [ "*" ];
    upstream = "static://202";
    reverseProxy = true;
    trustedProxyIP = [ "127.0.0.1/32" ];
    setXauthrequest = true;
    passBasicAuth = false;
    cookie = {
      name = "_oauth2_proxy_rss";
      secretFile = config.age.secrets.oauth2-rss-cookie-secret.path;
      expire = "168h";
      refresh = "5m";
    };
    extraConfig = {
      code-challenge-method = "S256";
      skip-provider-button = true;
      whitelist-domain = ".internal.veetik.com";
    };
    nginx = {
      domain = domain;
      virtualHosts.${domain}.allowed_groups = [ "admins" "internal-users" "rss-users" ];
    };
  };

  config.systemd.services.oauth2-proxy = {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig.RestartSec = 5;
  };

  config.services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/oauth2/".extraConfig = lib.mkAfter ''
      proxy_buffer_size 32k;
      proxy_buffers 4 32k;
      proxy_busy_buffers_size 64k;
    '';
    locations."/".proxyPass = "http://127.0.0.1:20000";
  };
}
