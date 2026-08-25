{ config, pkgs, guestIps, withInternalVhost, ... }:

let
  publicDomain = "auth.veetik.com";
  adminDomain = "auth.internal.veetik.com";

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
  config.age.secrets.keycloak-config-client-secret = {};
  config.age.secrets.keycloak-google-client-id = {};
  config.age.secrets.keycloak-google-client-secret = {};
  config.age.secrets.oidc-rss-client-secret = {};
  config.age.secrets.oidc-paperless-client-secret = {};
  config.age.secrets.oidc-grafana-client-secret = {};
  config.age.secrets.oidc-money-client-secret = {};

  config.services.keycloak = {
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
      http-host = "0.0.0.0";
      http-port = 8080;
      http-management-host = "127.0.0.1";
      hostname = "https://${publicDomain}";
      hostname-admin = "https://${adminDomain}";
      hostname-strict = true;
      hostname-backchannel-dynamic = true;
      proxy-headers = "xforwarded";
      proxy-trusted-addresses = "127.0.0.1,${guestIps.nginx-public}";
      health-enabled = true;
      metrics-enabled = true;
    };
  };

  config.systemd.services.keycloak-config = {
    description = "Configure Keycloak realm";
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
    script = ''
      export KEYCLOAK_CLIENTSECRET="$(cat ${config.age.secrets.keycloak-config-client-secret.path})"
      export GOOGLE_CLIENT_ID="$(cat ${config.age.secrets.keycloak-google-client-id.path})"
      export GOOGLE_CLIENT_SECRET="$(cat ${config.age.secrets.keycloak-google-client-secret.path})"
      export OIDC_RSS_CLIENT_SECRET="$(cat ${config.age.secrets.oidc-rss-client-secret.path})"
      export OIDC_PAPERLESS_CLIENT_SECRET="$(cat ${config.age.secrets.oidc-paperless-client-secret.path})"
      export OIDC_GRAFANA_CLIENT_SECRET="$(cat ${config.age.secrets.oidc-grafana-client-secret.path})"
      export OIDC_MONEY_CLIENT_SECRET="$(cat ${config.age.secrets.oidc-money-client-secret.path})"
      exec keycloak-config-cli
    '';
    serviceConfig.Type = "oneshot";
  };

  config.services.nginx.virtualHosts.${adminDomain} = withInternalVhost {
    locations."/".proxyPass = "http://127.0.0.1:8080";
  };

  config.homelab.metrics.scrapeConfigs = [{
    job_name = "keycloak";
    metrics_path = "/metrics";
    static_configs = [{ targets = [ "127.0.0.1:9000" ]; }];
  }];
}
