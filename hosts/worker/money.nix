{ config, mkNginxPublic, ... }:

let
  ports = config.homelab.ports;
in {
  imports = [ ../../modules/services/postgresql.nix ];

  age.secrets.money-enablebanking-private-key = {
    owner = "money";
    group = "money";
  };

  users.groups.money = {};
  users.users.money = {
    isSystemUser = true;
    group = "money";
  };

  virtualisation = {
    podman.enable = true;
    oci-containers = {
      backend = "podman";
      containers.money = {
        image = "docker.io/veetik/money@sha256:8ec792d8f1709138084636a7e7f6377597c0eb1785963a7c4bcf6703fa5d1db3";
        user = "money";
        extraOptions = [ "--hostuser=money" ];
        ports = [ "127.0.0.1:${toString ports.money}:8000" ];
        environmentFiles = [ config.age.secrets.money-env.path ];
        volumes = [
          "/run/postgresql:/run/postgresql"
          "${config.age.secrets.money-enablebanking-private-key.path}:/run/secrets/enablebanking-private-key:ro"
        ];
        environment = {
          IS_PROD = "1";
          DEMO_MODE = "1";
          PORT = "8000";
          BACKEND_URL = "https://money.veetik.com";
          OIDC_ISSUER = "https://auth.veetik.com/realms/main";
          OIDC_CLIENT_ID = "money";
          CLIENT_IP_HEADER = "X-Forwarded-For";
          ENABLEBANKING_ALLOWED_OIDC_SUBJECTS = "5abe0016-8773-4617-ba7e-3fe6ce892219";
          ENABLEBANKING_PRIVATE_KEY = "/run/secrets/enablebanking-private-key";
          DB_URL = "postgresql://money@localhost/money?host=/run/postgresql";
        };
      };
    };
  };

  homelab.postgresql.databases.money = {
    services = [ "podman-money" ];
    backup = {
      passwordFile = config.age.secrets.restic-money-password.path;
    };
  };

  services.nginx.virtualHosts."money.veetik.com" = mkNginxPublic {
    locations."/".proxyPass = "http://127.0.0.1:${toString ports.money}";
  };
}
