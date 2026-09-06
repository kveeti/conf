{ config, inventory, pkgs, ... }:

let
  publicHost = inventory.hosts.public;
  publicIp = publicHost.ipv4;
  adminIp = publicHost.adminIpv4;
  ports = config.homelab.ports;
  publicDomain = "auth.veetik.com";
  adminDomain = "authadmin.veetik.com";

  groupsMapper = {
    name = "groups";
    protocol = "openid-connect";
    protocolMapper = "oidc-group-membership-mapper";
    consentRequired = false;
    config = {
      "claim.name" = "groups";
      "full.path" = "false";
      "id.token.claim" = "true";
      "access.token.claim" = "true";
      "userinfo.token.claim" = "true";
    };
  };

  mkClient = { id, secretEnv, redirects, origins }: {
    clientId = id;
    name = id;
    enabled = true;
    protocol = "openid-connect";
    publicClient = false;
    bearerOnly = false;
    standardFlowEnabled = true;
    implicitFlowEnabled = false;
    directAccessGrantsEnabled = false;
    serviceAccountsEnabled = false;
    secret = "$(env:${secretEnv})";
    redirectUris = redirects;
    webOrigins = origins;
    attributes = {
      "pkce.code.challenge.method" = "S256";
      "post.logout.redirect.uris" = builtins.concatStringsSep "##" origins;
    };
    protocolMappers = [ groupsMapper ];
  };

  realmConfig = pkgs.writeText "main-keycloak.json" (builtins.toJSON {
    realm = "main";
    displayName = "veetik.com";
    enabled = true;
    sslRequired = "external";
    registrationAllowed = true;
    registrationEmailAsUsername = true;
    rememberMe = true;
    verifyEmail = false;
    loginWithEmailAllowed = true;
    duplicateEmailsAllowed = false;
    resetPasswordAllowed = false;
    editUsernameAllowed = false;
    bruteForceProtected = true;

    accessTokenLifespan = 300;
    revokeRefreshToken = true;
    refreshTokenMaxReuse = 0;
    ssoSessionIdleTimeout = 604800;
    ssoSessionMaxLifespan = 315360000;
    ssoSessionIdleTimeoutRememberMe = 604800;
    ssoSessionMaxLifespanRememberMe = 315360000;
    clientSessionIdleTimeout = 604800;
    clientSessionMaxLifespan = 315360000;

    groups = map (name: { inherit name; }) [
      "admins"
      "internal-users"
      "rss-users"
      "paperless-users"
      "grafana-users"
      "grafana-admins"
    ];

    identityProviders = [{
      alias = "google";
      displayName = "Google";
      providerId = "google";
      enabled = true;
      trustEmail = true;
      storeToken = false;
      addReadTokenRoleOnCreate = false;
      authenticateByDefault = false;
      linkOnly = false;
      firstBrokerLoginFlowAlias = "first broker login";
      config = {
        clientId = "$(env:GOOGLE_CLIENT_ID)";
        clientSecret = "$(env:GOOGLE_CLIENT_SECRET)";
        defaultScope = "openid profile email";
        syncMode = "IMPORT";
        useJwksUrl = "true";
      };
    }];

    clients = [
      (mkClient {
        id = "rss";
        secretEnv = "OIDC_RSS_CLIENT_SECRET";
        redirects = [ "https://rss.internal.veetik.com/oauth2/callback" ];
        origins = [ "https://rss.internal.veetik.com" ];
      })
      (mkClient {
        id = "paperless";
        secretEnv = "OIDC_PAPERLESS_CLIENT_SECRET";
        redirects = [
          "https://p.internal.veetik.com/accounts/oidc/keycloak/login/callback/"
          "https://p.internal.veetik.com/oauth2/callback"
        ];
        origins = [ "https://p.internal.veetik.com" ];
      })
      (mkClient {
        id = "grafana";
        secretEnv = "OIDC_GRAFANA_CLIENT_SECRET";
        redirects = [ "https://grafana.internal.veetik.com/login/generic_oauth" ];
        origins = [ "https://grafana.internal.veetik.com" ];
      })
      (mkClient {
        id = "money";
        secretEnv = "OIDC_MONEY_CLIENT_SECRET";
        redirects = [ "https://money.veetik.com/api/v1/auth/callback" ];
        origins = [ "https://money.veetik.com" ];
      })
    ];
  });
in {
  age.secrets = {
    keycloak-config-client-secret = {};
    keycloak-google-client-id = {};
    keycloak-google-client-secret = {};
    oidc-rss-client-secret = {};
    oidc-paperless-client-secret = {};
    oidc-grafana-client-secret = {};
    oidc-money-client-secret = {};
    restic-auth-rest-pass = {};
    restic-auth-encryption-pass = {};
  };

  services.keycloak = {
    enable = true;
    plugins = with pkgs.keycloak.plugins; [
      junixsocket-common
      junixsocket-native-common
    ];
    database = {
      type = "postgresql";
      createLocally = false;
      host = "/run/postgresql";
      name = "keycloak";
      username = "keycloak";
    };
    settings = {
      http-enabled = true;
      http-host = "127.0.0.1";
      http-port = ports.keycloak;
      http-management-host = "127.0.0.1";
      http-management-port = ports.keycloakManagement;
      hostname = "https://${publicDomain}";
      hostname-admin = "https://${adminDomain}";
      hostname-strict = true;
      hostname-backchannel-dynamic = true;
      proxy-headers = "xforwarded";
      proxy-trusted-addresses = "127.0.0.1";
      health-enabled = true;
      metrics-enabled = true;
    };
  };

  homelab.postgresql.databases.keycloak = {
    services = [ "keycloak" ];
    backup = {
      restPasswordFile = config.age.secrets.restic-auth-rest-pass.path;
      encryptionPasswordFile = config.age.secrets.restic-auth-encryption-pass.path;
    };
  };

  systemd.services.keycloak-config = {
    description = "Configure the Keycloak realm";
    wantedBy = [ "multi-user.target" ];
    after = [ "keycloak.service" "nginx.service" ];
    requires = [ "keycloak.service" "nginx.service" ];
    path = [ pkgs.keycloak-config-cli ];
    environment = {
      KEYCLOAK_URL = "https://${adminDomain}/";
      KEYCLOAK_CLIENTID = "keycloak-config";
      KEYCLOAK_GRANTTYPE = "client_credentials";
      KEYCLOAK_AVAILABILITYCHECK_ENABLED = "true";
      KEYCLOAK_AVAILABILITYCHECK_TIMEOUT = "120s";
      IMPORT_FILES_LOCATIONS = toString realmConfig;
      IMPORT_VARSUBSTITUTION_ENABLED = "true";
    };
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = [
        "client-secret:${config.age.secrets.keycloak-config-client-secret.path}"
        "google-client-id:${config.age.secrets.keycloak-google-client-id.path}"
        "google-client-secret:${config.age.secrets.keycloak-google-client-secret.path}"
        "oidc-rss-secret:${config.age.secrets.oidc-rss-client-secret.path}"
        "oidc-paperless-secret:${config.age.secrets.oidc-paperless-client-secret.path}"
        "oidc-grafana-secret:${config.age.secrets.oidc-grafana-client-secret.path}"
        "oidc-money-secret:${config.age.secrets.oidc-money-client-secret.path}"
      ];
    };
    script = ''
      export KEYCLOAK_CLIENTSECRET="$(cat "$CREDENTIALS_DIRECTORY/client-secret")"
      export GOOGLE_CLIENT_ID="$(cat "$CREDENTIALS_DIRECTORY/google-client-id")"
      export GOOGLE_CLIENT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/google-client-secret")"
      export OIDC_RSS_CLIENT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/oidc-rss-secret")"
      export OIDC_PAPERLESS_CLIENT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/oidc-paperless-secret")"
      export OIDC_GRAFANA_CLIENT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/oidc-grafana-secret")"
      export OIDC_MONEY_CLIENT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/oidc-money-secret")"
      exec keycloak-config-cli
    '';
  };

  services.nginx.virtualHosts = {
    ${publicDomain} = {
      useACMEHost = "veetik.com";
      forceSSL = true;
      listen = [
        { addr = publicIp; port = ports.http; }
        { addr = publicIp; port = ports.https; ssl = true; }
      ];
      locations = {
        "= /admin".return = "404";
        "^~ /admin/".return = "404";
        "= /realms/main".proxyPass = "http://127.0.0.1:${toString ports.keycloak}";
        "^~ /realms/main/".proxyPass = "http://127.0.0.1:${toString ports.keycloak}";
        "= /realms/master" = {
          proxyPass = "http://127.0.0.1:${toString ports.keycloak}";
          extraConfig = ''
            allow 192.168.10.0/24;
            allow 10.255.255.0/24;
            deny all;
          '';
        };
        "^~ /realms/master/" = {
          proxyPass = "http://127.0.0.1:${toString ports.keycloak}";
          extraConfig = ''
            allow 192.168.10.0/24;
            allow 10.255.255.0/24;
            deny all;
          '';
        };
        "^~ /resources/".proxyPass = "http://127.0.0.1:${toString ports.keycloak}";
        "/".return = "404";
      };
    };

    ${adminDomain} = {
      useACMEHost = "veetik.com";
      onlySSL = true;
      listen = [{ addr = adminIp; port = ports.https; ssl = true; }];
      extraConfig = ''
        allow 127.0.0.1;
        allow 192.168.10.0/24;
        allow ${publicIp};
        allow ${adminIp};
        allow 10.255.255.0/24;
        deny all;
      '';
      locations."/".proxyPass = "http://127.0.0.1:${toString ports.keycloak}";
    };
  };

  networking.hosts = {
    ${publicIp} = [ publicDomain ];
    ${adminIp} = [ adminDomain ];
  };

  homelab.metrics.scrapes.keycloak = {
    path = "/metrics";
    targets = [ "127.0.0.1:${toString ports.keycloakManagement}" ];
  };

  homelab.logs.units = {
    "keycloak.service" = {
      format = "auto";
      serviceName = "keycloak";
    };
    "keycloak-config.service" = {
      format = "auto";
      serviceName = "keycloak-config";
    };
  };
}
