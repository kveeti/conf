{ config, withSharedVhost, ... }:

let
  domain = "sso.internal.veetik.com";
in {
  config.services.backedupPg.instances.authelia.units = [ "authelia-authelia.service" ];

  config.systemd.tmpfiles.rules = [
    "d /var/lib/authelia-notifs 0750 authelia authelia -"
    "f /var/lib/authelia-notifs/notifs.txt 0640 authelia authelia -"
  ];

  config.systemd.services.authelia-authelia = {
    after    = [ "lldap.service" ];
    requires = [ "lldap.service" ];
    serviceConfig = {
      ReadWritePaths = [ "/var/lib/authelia-notifs" ];
    };
  };
  config.users.users.authelia = {
    isSystemUser = true;
    group = "authelia";
  };
  config.users.groups.authelia = {};
  config.age.secrets.authelia-jwt-secret.mode = "0400";
  config.age.secrets.authelia-jwt-secret.owner = "authelia";
  config.age.secrets.authelia-hmac-secret.mode = "0400";
  config.age.secrets.authelia-hmac-secret.owner = "authelia";
  config.age.secrets.authelia-issuer-priv-key.mode = "0400";
  config.age.secrets.authelia-issuer-priv-key.owner = "authelia";
  config.age.secrets.authelia-session-secret.mode = "0400";
  config.age.secrets.authelia-session-secret.owner = "authelia";
  config.age.secrets.authelia-storage-encryption-key.mode = "0400";
  config.age.secrets.authelia-storage-encryption-key.owner = "authelia";
  config.age.secrets.authelia-ldap-bind-password.mode = "0400";
  config.age.secrets.authelia-ldap-bind-password.owner = "authelia";
  config.services.authelia.instances.homelab = {
    enable = true;
    secrets = {
      jwtSecretFile = config.age.secrets.authelia-jwt-secret.path;
      oidcHmacSecretFile = config.age.secrets.authelia-hmac-secret.path;
      oidcIssuerPrivateKeyFile = config.age.secrets.authelia-issuer-priv-key.path;
      sessionSecretFile = config.age.secrets.authelia-session-secret.path;
      storageEncryptionKeyFile = config.age.secrets.authelia-storage-encryption-key.path;
    };
    environmentVariables = {
      AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = config.age.secrets.authelia-ldap-bind-password.path;
    };
    name = "authelia";
    user = "authelia";
    group = "authelia";
    settings = {
      theme = "dark";
      telemetry.metrics = {
        enabled = true;
        address = "tcp://127.0.0.1:9959";
      };
      server.address = "127.0.0.1:20004";
      server.endpoints.rate_limits.session_elevation_start.enable = false;
      server.endpoints.rate_limits.session_elevation_finish.enable = false;
      server.endpoints.rate_limits.second_factor_totp.enable = false;
      log.level = "debug";
      session = {
        cookies = [{
          domain = "internal.veetik.com";
          authelia_url = "https://${domain}";
          inactivity = "1M";
          expiration = "3M";
          remember_me = "1y";
        }];
      };
      regulation = {
        max_retries = 3;
        find_time = 120;
        ban_time = 300;
      };
      authentication_backend = {
        password_reset.disable = false;
        refresh_interval = "1m";
        ldap = {
          implementation = "custom";
          address = "ldap://127.0.0.1:20002";
          timeout = "5m";
          start_tls = false;
          base_dn = "dc=internal,dc=veetik,dc=com";
          additional_users_dn = "ou=people";
          users_filter = "(&({username_attribute}={input})(objectClass=person))";
          additional_groups_dn = "ou=groups";
          groups_filter = "(member={dn})";
          user = "uid=authelia,ou=people,dc=internal,dc=veetik,dc=com";
          attributes = {
            display_name = "displayName";
            group_name = "cn";
            mail = "mail";
            username = "uid";
          };
        };
      };
      access_control = {
        default_policy = "deny";
        networks = [
          {
            name = "localhost";
            networks = [ "127.0.0.1/32" ];
          }
          {
            name = "internal";
            networks = [
              "192.168.10.0/24"
            ];
          }
          {
            name = "all";
            networks = [
              "0.0.0.0/0"
            ];
          }
        ];
        # first-match-wins: per-app rules must stay above the catch-all
        rules =
          let
            adminScoped = group: dom: {
              domain = dom;
              policy = "two_factor";
              networks = "all";
              subject = [ [ "group:admins" ] [ "group:${group}" ] ];
            };
          in [
            {
              domain = "ldap.internal.veetik.com";
              policy = "two_factor";
              networks = "all";
              subject = [ "group:admins" ];
            }
            (adminScoped "grafana-admin" "grafana.internal.veetik.com")
            (adminScoped "rss-admin"     "rss.internal.veetik.com")
            (adminScoped "food-admin"    "food.internal.veetik.com")
            (adminScoped "weather-admin" "weather.internal.veetik.com")
            (adminScoped "dav-user"      "dav.internal.veetik.com")
            {
              domain = "*.internal.veetik.com";
              policy = "two_factor";
              networks = "all";
              subject = [ [ "group:admins" ] [ "group:users" ] ];
            }
          ];
      };
      storage = {
        postgres = {
          address = "/run/postgresql/.s.PGSQL.5432";
          database = "authelia";
          username = "authelia";
        };
      };
      notifier = {
        disable_startup_check = false;
        filesystem.filename = "/var/lib/authelia-notifs/notifs.txt";
      };
      identity_providers.oidc.claims_policies.grafana.id_token = [ "email" "name" "groups" "preferred_username" ];
      identity_providers.oidc.clients = [
        {
          authorization_policy = "two_factor";
          client_id = "paperless";
          client_secret = "$pbkdf2-sha512$310000$8HhNJS3iM0I6n4BVbVZjog$izOL0ziuzVhb5WgUv6CqXL.BcpGBAcwVf5o.gE7M73ggZPODftF71VGPamnnMIuv2AFw6il.CvaolAnkGxYiug";
          redirect_uris = [ "https://p.internal.veetik.com/accounts/oidc/authelia/login/callback/" ];
          public = false;
          require_pkce = true;
          pkce_challenge_method = "S256";
          scopes = [ "openid" "profile" "email" ];
          response_types = [ "code" ];
          grant_types = [ "authorization_code" ];
          access_token_signed_response_alg = "none";
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
        }
        {
          authorization_policy = "two_factor";
          client_id = "grafana";
          client_secret = "$pbkdf2-sha512$310000$MB94tPuAWCf1sozy8EJ60w$spQyLlLiHucPE1buYFEpEGqj.Yk28V9LdUaiyCXADy7clI3VG3JiPv1M5i/GE0lNc9B.nOFYa8xFLv.hI3QO9Q";
          redirect_uris = [ "https://grafana.internal.veetik.com/login/generic_oauth" ];
          claims_policy = "grafana";
          public = false;
          require_pkce = true;
          pkce_challenge_method = "S256";
          scopes = [ "openid" "profile" "email" "groups" ];
          response_types = [ "code" ];
          grant_types = [ "authorization_code" ];
          access_token_signed_response_alg = "none";
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
        }
      ];
    };
  };

  config.services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:20004";
  };

  config.homelab.metrics.scrapeConfigs = [{
    job_name = "authelia";
    static_configs = [{ targets = [ "127.0.0.1:9959" ]; }];
  }];

}
