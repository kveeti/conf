{ config, pkgs, mkNginxPublic, mkNginxInternal, ... }:

let
  ports = config.homelab.ports;
  backend = "http://127.0.0.1:${toString ports.keycloak}";
in {
  imports = [ ../../modules/services/postgresql.nix ];

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
      hostname = "https://auth.veetik.com";
      hostname-admin = "https://authadmin.internal.veetik.com";
      hostname-strict = true;
      hostname-backchannel-dynamic = true;
      proxy-headers = "xforwarded";
      proxy-trusted-addresses = "127.0.0.1";
      cache = "local";
      health-enabled = true;
      metrics-enabled = true;
    };
  };

  homelab.postgresql.databases.keycloak.backup = {
    passwordFile = config.age.secrets.restic-keycloak-password.path;
  };

  services.nginx.virtualHosts = {
    "auth.veetik.com" = mkNginxPublic {
      locations = {
        "/".return = "404";
        "= /realms/main".proxyPass = backend;
        "/realms/main/".proxyPass = backend;
        "= /resources".proxyPass = backend;
        "/resources/".proxyPass = backend;
      };
    };

    "authadmin.internal.veetik.com" = mkNginxInternal {
      locations."/".proxyPass = backend;
    };
  };
}
